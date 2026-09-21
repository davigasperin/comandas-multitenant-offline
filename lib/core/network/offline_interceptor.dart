import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mutation_queue_storage.dart';
import 'queued_mutation.dart';

class OfflineInterceptor extends Interceptor {
  static const queueKey = 'offline_request_queue';
  static const cachePrefix = 'offline_cache_v2_';
  final SharedPreferences prefs;
  final MutationQueueStorage queue;

  OfflineInterceptor(this.prefs, this.queue);

  String? _cacheKey(RequestOptions request) {
    final owner = request.extra['owner'];
    final tenant = request.headers['X-Tenant-Id'];
    if (owner == null || tenant == null || request.method != 'GET' ||
        !RegExp(r'^/orders(?:/[a-zA-Z0-9_-]+)?$').hasMatch(request.path)) return null;
    final query = request.queryParameters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return '$cachePrefix${jsonEncode([owner, tenant, request.path, query.map((e) => [e.key, e.value]).toList()])}';
  }

  bool _isTransient(DioExceptionType type) => const [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
      ].contains(type);

  @override
  Future<void> onResponse(Response response, ResponseInterceptorHandler handler) async {
    final key = _cacheKey(response.requestOptions);
    if (key != null && response.statusCode == 200) {
      await prefs.setString(key, jsonEncode(response.data));
    }
    handler.next(response);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    if (request.extra['skipOfflineQueue'] == true) {
      handler.next(err);
      return;
    }
    if (_isTransient(err.type) && const ['POST', 'PATCH', 'PUT', 'DELETE'].contains(request.method)) {
      final tenantId = request.headers['X-Tenant-Id']?.toString();
      final userId = request.extra['owner']?.toString();
      final idempotencyKey = request.headers['X-Idempotency-Key']?.toString();
      if (tenantId != null && userId != null && idempotencyKey != null) {
        await queue.enqueue(QueuedMutation(
          id: '${DateTime.now().microsecondsSinceEpoch}_$idempotencyKey',
          idempotencyKey: idempotencyKey,
          method: request.method,
          path: request.path,
          body: request.data is Map ? Map<String, dynamic>.from(request.data as Map) : null,
          tenantId: tenantId,
          userId: userId,
          createdAt: DateTime.now(),
        ));
        handler.resolve(Response(
          requestOptions: request,
          statusCode: 202,
          data: <String, dynamic>{'queued': true},
          extra: {'offline': true, 'queued': true},
        ));
        return;
      }
    }

    final key = _cacheKey(request);
    if (key != null && _isTransient(err.type)) {
      final cached = prefs.getString(key);
      if (cached != null) {
        handler.resolve(Response(requestOptions: request, statusCode: 200, data: jsonDecode(cached), extra: {'offline': true}));
        return;
      }
    }
    handler.next(err);
  }
}
