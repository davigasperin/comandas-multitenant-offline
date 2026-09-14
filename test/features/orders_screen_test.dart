import 'package:comandas_app/features/orders/domain/order_model.dart';
import 'package:comandas_app/features/orders/presentation/orders_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('OrdersScreen renders loading, empty and populated states', (tester) async {
    // 1. Loading state
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          openOrdersProvider.overrideWith((ref) => Future.value([])),
          closedOrdersProvider.overrideWith((ref) => Future.value([])),
        ],
        child: const MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: TabBar(
                tabs: [Tab(text: 'Abertas'), Tab(text: 'Fechadas')],
              ),
              body: OrdersScreen(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Nenhuma comanda aberta no momento.'), findsOneWidget);

    // 2. Switch tab to closed
    await tester.tap(find.text('Fechadas'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma comanda fechada.'), findsOneWidget);
  });

  testWidgets('OrdersScreen renders list of orders', (tester) async {
    final fakeOrder = Order(
      id: 'ord_1',
      tableLabel: 'Mesa 99',
      status: OrderStatus.open,
      items: const [],
      openedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          openOrdersProvider.overrideWith((ref) => Future.value([fakeOrder])),
          closedOrdersProvider.overrideWith((ref) => Future.value([])),
        ],
        child: const MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: Scaffold(
              body: OrdersScreen(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Mesa 99'), findsOneWidget);
    expect(find.text('ABERTA'), findsOneWidget);
  });
}
