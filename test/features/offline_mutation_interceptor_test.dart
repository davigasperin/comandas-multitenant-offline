import 'dart:async';
import 'package:comandas_app/core/network/mutation_queue_storage.dart';
import 'package:comandas_app/core/network/offline_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeErrorHandler extends ErrorInterceptorHandler {
  final Completer<Response> completer = Completer<Response>();

  @override
  void next(DioException err) {
    completer.completeError(err);
  }

  @override
  void resolve(Response response) {
    completer.complete(response);
  }

  @override
  void reject(DioException error, [bool? callNext]) {
    completer.completeError(error);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OfflineInterceptor intercepta mutação com falha e a enfileira com 202', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final queue = MutationQueueStorage(prefs);
    final interceptor = OfflineInterceptor(prefs, queue);

    final errHandler = _FakeErrorHandler();
    final requestOptions = RequestOptions(
      path: '/orders',
      method: 'POST',
      data: {'table_label': 'Mesa 42'},
      headers: {
        'X-Tenant-Id': 'tenant_test',
        'X-Idempotency-Key': 'idemp_key_123',
      },
      extra: {'owner': 'user_owner_1'},
    );

    interceptor.onError(
      DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.connectionError,
      ),
      errHandler,
    );

    final response = await errHandler.completer.future;
    expect(response.statusCode, 202);
    expect(response.extra['offline'], isTrue);
    expect(response.extra['queued'], isTrue);

    final pending = queue.getPendingFor(tenantId: 'tenant_test', userId: 'user_owner_1');
    expect(pending.length, 1);
    expect(pending.first.idempotencyKey, 'idemp_key_123');
    expect(pending.first.path, '/orders');
    expect(pending.first.body?['table_label'], 'Mesa 42');
  });

  test('OfflineInterceptor nunca enfileira liquidação financeira', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final queue = MutationQueueStorage(prefs);
    final interceptor = OfflineInterceptor(prefs, queue);
    final handler = _FakeErrorHandler();
    final request = RequestOptions(
      path: '/orders/order_1/settle',
      method: 'POST',
      data: {'payments': <dynamic>[]},
      headers: {'X-Tenant-Id': 'tenant_test'},
      extra: {'owner': 'user_owner_1'},
    );

    interceptor.onError(
      DioException(requestOptions: request, type: DioExceptionType.connectionError),
      handler,
    );

    await expectLater(handler.completer.future, throwsA(isA<DioException>()));
    expect(queue.getAll(), isEmpty);
  });
}
