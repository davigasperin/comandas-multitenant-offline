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

  test('getOpenOrders interpreta JSON corretamente', () async {
    dio.httpClientAdapter = FakeHttpClientAdapter((options) async {
      expect(options.queryParameters['status'], 'open,sentToKitchen,delivered');
      return FakeHttpClientAdapter.json({
        'data': [orderJson]
      }, 200);
    });

    final orders = await repository.getOpenOrders();
    expect(orders, hasLength(1));
    expect(orders.first.tableLabel, 'Mesa 1');
    expect(orders.first.status, OrderStatus.open);
    expect(orders.first.items.first.productName, 'Agua');
  });

  test('createOrder envia table_label e interpreta a nova comanda', () async {
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

  test('previewSettlement envia inteiros e interpreta resposta autoritativa',
      () async {
    dio.httpClientAdapter = FakeHttpClientAdapter((options) async {
      expect(options.method, 'POST');
      expect(options.path, '/orders/ord_1/settlement-preview');
      expect(options.data, {
        'discount_cents': 123,
        'service_fee_bps': 1050,
      });
      return FakeHttpClientAdapter.json({
        'subtotal_cents': 10000,
        'discount_cents': 123,
        'service_fee_bps': 1050,
        'service_fee_cents': 1037,
        'total_cents': 10914,
      }, 200);
    });

    final preview = await repository.previewSettlement(
      orderId: 'ord_1',
      discountCents: 123,
      serviceFeeBps: 1050,
    );

    expect(preview.totalCents, 10914);
    expect(preview.serviceFeeCents, 1037);
  });

  test('settleOrder usa chave fornecida e nunca permite fila offline',
      () async {
    dio.httpClientAdapter = FakeHttpClientAdapter((options) async {
      expect(options.method, 'POST');
      expect(options.path, '/orders/ord_1/settle');
      expect(options.headers['X-Idempotency-Key'], 'stable-key');
      expect(options.extra['skipOfflineQueue'], isTrue);
      expect(options.data['expected_version'], 7);
      expect(options.data['payments'], [
        {
          'method': 'cash',
          'amount_cents': 1000,
          'tendered_cents': 1200,
        }
      ]);
      return FakeHttpClientAdapter.json({}, 200);
    });

    final result = await repository.settleOrder(
      orderId: 'ord_1',
      payments: const [
        {
          'method': 'cash',
          'amount_cents': 1000,
          'tendered_cents': 1200,
        }
      ],
      expectedVersion: 7,
      idempotencyKey: 'stable-key',
    );

    expect(result, isTrue);
  });
}
