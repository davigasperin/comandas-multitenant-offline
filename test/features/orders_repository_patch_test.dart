import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comandas_app/features/orders/data/orders_repository.dart';

class MockAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode({
        'id': 'ord_123',
        'table_label': 'Mesa 10',
        'status': 'sentToKitchen',
        'opened_at': DateTime.now().toIso8601String(),
        'items': [],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('OrdersRepository sends PATCH /orders/:id/status', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000/v1'));
    final adapter = MockAdapter();
    dio.httpClientAdapter = adapter;

    final repo = OrdersRepository(dio);
    await repo.updateOrderStatus(orderId: 'ord_123', status: 'sentToKitchen');

    expect(adapter.lastRequest?.method, 'PATCH');
    expect(adapter.lastRequest?.path, '/orders/ord_123/status');
    expect(adapter.lastRequest?.data, {'status': 'sentToKitchen'});
  });
}
