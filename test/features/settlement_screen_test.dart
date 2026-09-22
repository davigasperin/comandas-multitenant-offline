import 'package:comandas_app/core/network/providers.dart';
import 'package:comandas_app/features/orders/data/orders_repository.dart';
import 'package:comandas_app/features/orders/domain/order_model.dart';
import 'package:comandas_app/features/orders/presentation/settlement_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_http_client_adapter.dart';

void main() {
  late Dio dio;
  late OrdersRepository repository;

  final sampleOrder = Order(
    id: 'ord_123',
    tableLabel: 'Mesa 5',
    status: OrderStatus.open,
    version: 3,
    openedAt: DateTime.now(),
    items: const [
      OrderItem(
        id: 'i1',
        productName: 'Hambúrguer',
        quantity: 2,
        unitPriceCents: 2500,
      ),
    ],
  );

  setUp(() {
    dio = Dio();
    repository = OrdersRepository(dio);
  });

  Widget buildTestableWidget({
    required Widget child,
    String? role = 'cashier',
  }) {
    return ProviderScope(
      overrides: [
        ordersRepositoryProvider.overrideWithValue(repository),
        currentTenantRoleProvider.overrideWith((ref) => Future.value(role)),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  testWidgets('SettlementScreen carrega preview e exibe valores calculados',
      (tester) async {
    dio.httpClientAdapter = FakeHttpClientAdapter((options) async {
      if (options.path.contains('/settlement-preview')) {
        return FakeHttpClientAdapter.json({
          'subtotal_cents': 5000,
          'discount_cents': 500,
          'service_fee_bps': 1000,
          'service_fee_cents': 450,
          'total_cents': 4950,
        }, 200);
      }
      return FakeHttpClientAdapter.json({}, 404);
    });

    await tester.pumpWidget(
      buildTestableWidget(
        child: SettlementScreen(order: sampleOrder),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Liquidar Mesa 5'), findsOneWidget);
    expect(find.text('Ajustes e Taxas'), findsOneWidget);
    expect(find.text('Total a Pagar:'), findsOneWidget);
    expect(find.text('Confirmar Pagamento'), findsOneWidget);
  });

  testWidgets(
      'SettlementScreen desabilita botão para garçom sem permissão de liquidar',
      (tester) async {
    dio.httpClientAdapter = FakeHttpClientAdapter((options) async {
      if (options.path.contains('/settlement-preview')) {
        return FakeHttpClientAdapter.json({
          'subtotal_cents': 5000,
          'discount_cents': 0,
          'service_fee_bps': 1000,
          'service_fee_cents': 500,
          'total_cents': 5500,
        }, 200);
      }
      return FakeHttpClientAdapter.json({}, 404);
    });

    await tester.pumpWidget(
      buildTestableWidget(
        child: SettlementScreen(order: sampleOrder),
        role: 'waiter',
      ),
    );

    await tester.pumpAndSettle();

    final btnFinder =
        find.widgetWithText(ElevatedButton, 'Confirmar Pagamento');
    final btn = tester.widget<ElevatedButton>(btnFinder);
    expect(btn.enabled, isFalse);
    expect(
      find.text('Apenas caixa ou gerente podem liquidar comandas.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'SettlementScreen divide pagamentos e submete com idempotência preservada',
      (tester) async {
    String? capturedIdempotencyKey;
    Map<String, dynamic>? capturedBody;

    dio.httpClientAdapter = FakeHttpClientAdapter((options) async {
      if (options.path.contains('/settlement-preview')) {
        return FakeHttpClientAdapter.json({
          'subtotal_cents': 5000,
          'discount_cents': 0,
          'service_fee_bps': 1000,
          'service_fee_cents': 500,
          'total_cents': 5500,
        }, 200);
      }
      if (options.path.contains('/settle')) {
        capturedIdempotencyKey =
            options.headers['X-Idempotency-Key']?.toString();
        capturedBody = options.data as Map<String, dynamic>;
        return FakeHttpClientAdapter.json({'success': true}, 200);
      }
      return FakeHttpClientAdapter.json({}, 404);
    });

    await tester.pumpWidget(
      buildTestableWidget(
        child: SettlementScreen(order: sampleOrder),
        role: 'manager',
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Dividir'));
    await tester.pumpAndSettle();

    expect(find.text('PIX'), findsOneWidget);

    final amountInputs = find.widgetWithText(TextField, 'Valor (R\$)');
    expect(amountInputs, findsNWidgets(2));

    await tester.enterText(amountInputs.at(0), '30,00');
    await tester.pumpAndSettle();

    await tester.enterText(amountInputs.at(1), '25,00');
    await tester.pumpAndSettle();

    final confirmBtn =
        find.widgetWithText(ElevatedButton, 'Confirmar Pagamento');
    await tester.ensureVisible(confirmBtn);
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    expect(capturedIdempotencyKey, isNotNull);
    expect(capturedBody, isNotNull);
    expect(capturedBody!['discount_cents'], 0);
    expect(capturedBody!['service_fee_bps'], 1000);
    expect(capturedBody!['expected_version'], 3);
    final payments = capturedBody!['payments'] as List<dynamic>;
    expect(payments, hasLength(2));
    expect(payments[0]['method'], 'cash');
    expect(payments[0]['amount_cents'], 3000);
    expect(payments[1]['method'], 'pix');
    expect(payments[1]['amount_cents'], 2500);
  });
}
