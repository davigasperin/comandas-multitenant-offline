import 'package:comandas_app/features/orders/data/orders_repository.dart';
import 'package:comandas_app/features/orders/domain/order_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_http_client_adapter.dart';

void main() {
  late Dio dio;
  late OrdersRepository repository;

  setUp(() {
    dio = Dio();
    repository = OrdersRepository(dio);
  });

  final orderJson = {
    'id': 'ord_1',
    'table_label': 'Mesa 1',
    'status': 'open',
    'opened_at': '2023-01-01T10:00:00Z',
    'items': [
      {
        'id': 'it_1',
        'product_name': 'Agua',
        'quantity': 2,
        'unit_price': 5.0,
      }
    ],
  };

  test('getOpenOrders parses JSON correctly', () async {
    dio.httpClientAdapter = FakeHttpClientAdapter((options) async {
      expect(options.queryParameters['status'], 'open,sentToKitchen,delivered');
      return FakeHttpClientAdapter.json({'data': [orderJson]}, 200);
    });

    final orders = await repository.getOpenOrders();
    expect(orders, hasLength(1));
    expect(orders.first.tableLabel, 'Mesa 1');
    expect(orders.first.status, OrderStatus.open);
    expect(orders.first.items.first.productName, 'Agua');
  });

  test('createOrder sends table_label and parses new Order', () async {
    dio.httpClientAdapter = FakeHttpClientAdapter((options) async {
      expect(options.method, 'POST');
      expect(options.data['table_label'], 'Mesa 2');
      final newOrder = Map<String, dynamic>.from(orderJson)
        ..['table_label'] = 'Mesa 2';
      return FakeHttpClientAdapter.json(newOrder, 201);
    });

    final order = await repository.createOrder(tableLabel: 'Mesa 2');
    expect(order.tableLabel, 'Mesa 2');
  });
}
