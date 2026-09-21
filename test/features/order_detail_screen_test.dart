import 'package:comandas_app/features/orders/domain/order_model.dart';
import 'dart:typed_data';

import 'package:comandas_app/core/network/providers.dart';
import 'package:comandas_app/features/orders/data/receipt_service.dart';
import 'package:comandas_app/features/orders/domain/product_model.dart';
import 'package:comandas_app/features/orders/presentation/order_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class MockReceiptService implements ReceiptService {
  bool printCalled = false;

  @override
  Future<Uint8List> generateReceiptPdf(Order order) async => Uint8List(0);

  @override
  Future<bool> printReceipt(Order order) async {
    printCalled = true;
    return true;
  }
}

void main() {
  final fakeOrder = Order(
    id: 'ord_1',
    tableLabel: 'Mesa 99',
    status: OrderStatus.open,
    items: const [
      OrderItem(
        id: 'it_1',
        productName: 'Cerveja',
        quantity: 2,
        unitPriceCents: 1500,
      )
    ],
    openedAt: DateTime.now(),
  );

  testWidgets('OrderDetailScreen renderiza itens, total e imprime recibo', (tester) async {
    final mockReceiptService = MockReceiptService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderDetailProvider('ord_1').overrideWith((ref) => Future.value(fakeOrder)),
          productsProvider.overrideWith((ref) => Future.value([
            const Product(id: 'p1', name: 'Suco', priceCents: 1000),
          ])),
          receiptServiceProvider.overrideWithValue(mockReceiptService),
        ],
        child: const MaterialApp(
          home: OrderDetailScreen(orderId: 'ord_1'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Mesa 99'), findsOneWidget);
    expect(find.text('2x Cerveja'), findsOneWidget);
    expect(find.text('R\$ 30,00'), findsNWidgets(2)); // Um no item (subtotal), um no Total da comanda
    expect(find.text('Item'), findsOneWidget);
    expect(find.byTooltip('Imprimir comanda'), findsOneWidget);

    await tester.tap(find.byTooltip('Imprimir comanda'));
    await tester.pumpAndSettle();
    expect(mockReceiptService.printCalled, isTrue);
  });

  testWidgets('OrderDetailScreen oculta o botão Adicionar item quando o status é closed', (tester) async {
    final closedOrder = Order(
      id: 'ord_1',
      tableLabel: 'Mesa 99',
      status: OrderStatus.closed,
      items: const [],
      openedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderDetailProvider('ord_1').overrideWith((ref) => Future.value(closedOrder)),
          productsProvider.overrideWith((ref) => Future.value([])),
        ],
        child: const MaterialApp(
          home: OrderDetailScreen(orderId: 'ord_1'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('FECHADA'), findsOneWidget);
    expect(find.text('Item'), findsNothing); // OutlinedButton oculto
    
    // O ElevatedButton exibe 'Fechada' e está desabilitado
    final btnFinder = find.widgetWithText(ElevatedButton, 'Fechada');
    expect(btnFinder, findsOneWidget);
    final btn = tester.widget<ElevatedButton>(btnFinder);
    expect(btn.enabled, isFalse);
  });
}
