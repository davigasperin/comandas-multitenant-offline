import 'dart:async';
import 'package:comandas_app/core/network/offline_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeResponseHandler extends ResponseInterceptorHandler {
  final Completer<Response> completer = Completer<Response>();

  @override
  void next(Response response) {
    completer.complete(response);
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

  test('Scoped cache resolves on offline error', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = MutationQueueStorage(prefs);
    final interceptor = OfflineInterceptor(prefs, storage);

    final resHandler = _FakeResponseHandler();
    interceptor.onResponse(
      Response(
        requestOptions: RequestOptions(
          path: '/orders',
          method: 'GET',
          headers: {'X-Tenant-Id': 'tenant-1'},
          extra: {'owner': 'user-1'},
        ),
        statusCode: 200,
        data: {'data': [{'id': 'ord-1'}]},
      ),
      resHandler,
    );
    await resHandler.completer.future;

    final errHandler = _FakeErrorHandler();
    interceptor.onError(
      DioException(
        requestOptions: RequestOptions(
          path: '/orders',
          method: 'GET',
          headers: {'X-Tenant-Id': 'tenant-1'},
          extra: {'owner': 'user-1'},
        ),
        type: DioExceptionType.connectionError,
      ),
      errHandler,
    );

    final resolved = await errHandler.completer.future;
    expect(resolved.statusCode, 200);
    expect((resolved.data as Map)['data'][0]['id'], 'ord-1');
    expect(resolved.extra['offline'], isTrue);
  });
}
