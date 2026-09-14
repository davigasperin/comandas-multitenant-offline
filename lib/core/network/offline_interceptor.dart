import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineInterceptor extends Interceptor {
  static const queueKey = 'offline_request_queue';
  static const cachePrefix = 'offline_cache_v2_';
  final SharedPreferences prefs;

  OfflineInterceptor(this.prefs);

  String? _cacheKey(RequestOptions request) {
    final owner = request.extra['owner'];
    final tenant = request.headers['X-Tenant-Id'];
    if (owner == null || tenant == null || request.method != 'GET' ||
        !RegExp(r'^/orders(?:/[a-zA-Z0-9_-]+)?$').hasMatch(request.path)) {
      return null;
    }
    final query = request.queryParameters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return '$cachePrefix${jsonEncode([owner, tenant, request.path, query.map((e) => [e.key, e.value]).toList()])}';
  }

  @override
  Future<void> onResponse(Response response, ResponseInterceptorHandler handler) async {
    final key = _cacheKey(response.requestOptions);
    if (key != null && response.statusCode == 200) {
      try {
        await prefs.setString(key, jsonEncode(response.data));
      } catch (_) {}
    }
    handler.next(response);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final key = _cacheKey(err.requestOptions);
    if (key != null && const [DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout, DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout].contains(err.type)) {
      try {
        final cached = prefs.getString(key);
        if (cached != null) {
          handler.resolve(Response(requestOptions: err.requestOptions,
            statusCode: 200, data: jsonDecode(cached), extra: {'offline': true}));
          return;
        }
      } catch (_) {}
    }
    handler.next(err);
  }
}
