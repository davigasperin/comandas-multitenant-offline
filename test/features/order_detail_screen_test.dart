import 'package:comandas_app/features/orders/domain/order_model.dart';
import 'package:comandas_app/features/orders/domain/product_model.dart';
import 'package:comandas_app/features/orders/presentation/order_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
        unitPrice: 15.0,
      )
    ],
    openedAt: DateTime.now(),
  );

  testWidgets('OrderDetailScreen renders items, total and Add Item button', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderDetailProvider('ord_1').overrideWith((ref) => Future.value(fakeOrder)),
          productsProvider.overrideWith((ref) => Future.value([
            const Product(id: 'p1', name: 'Suco', price: 10.0),
          ])),
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
    expect(find.text('Item'), findsOneWidget); // Add Item button
  });

  testWidgets('OrderDetailScreen hides Add Item button if status is closed', (tester) async {
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
    expect(find.text('Item'), findsNothing); // OutlinedButton hidden
    
    // The ElevatedButton says 'Fechada' and is disabled
    final btnFinder = find.widgetWithText(ElevatedButton, 'Fechada');
    expect(btnFinder, findsOneWidget);
    final btn = tester.widget<ElevatedButton>(btnFinder);
    expect(btn.enabled, isFalse);
  });
}
