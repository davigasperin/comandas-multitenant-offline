import 'package:comandas_app/core/network/providers.dart';
import 'package:comandas_app/core/network/socket_service.dart';
import 'package:comandas_app/features/orders/domain/order_model.dart';
import 'package:comandas_app/features/orders/presentation/kds_screen.dart';
import 'package:comandas_app/features/orders/presentation/orders_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testOrderOpen = Order(
    id: 'ord_1',
    tableLabel: 'Mesa 1',
    status: OrderStatus.open,
    openedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    items: const [
      OrderItem(id: 'i1', productName: 'Pizza', quantity: 1, unitPrice: 40.0),
    ],
  );

  final testOrderPrep = Order(
    id: 'ord_2',
    tableLabel: 'Mesa 2',
    status: OrderStatus.sentToKitchen,
    openedAt: DateTime.now().subtract(const Duration(minutes: 15)),
    items: const [
      OrderItem(id: 'i2', productName: 'Hambúrguer', quantity: 2, unitPrice: 25.0),
    ],
  );

  final testOrderDelivered = Order(
    id: 'ord_3',
    tableLabel: 'Mesa 3',
    status: OrderStatus.delivered,
    openedAt: DateTime.now().subtract(const Duration(minutes: 2)),
    items: const [
      OrderItem(id: 'i3', productName: 'Cerveja', quantity: 3, unitPrice: 10.0),
    ],
  );

  testWidgets('KdsScreen displays 3 columns and orders in correct columns', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          openOrdersProvider.overrideWith((ref) => Future.value([
                testOrderOpen,
                testOrderPrep,
                testOrderDelivered,
              ])),
          socketConnectionStateProvider.overrideWith(
            (ref) => Stream.value(SocketConnectionState.connected),
          ),
        ],
        child: const MaterialApp(
          home: KdsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('KDS - Cozinha'), findsOneWidget);
    expect(find.text('NOVOS'), findsOneWidget);
    expect(find.text('EM PREPARO'), findsOneWidget);
    expect(find.text('PRONTOS'), findsOneWidget);

    expect(find.text('Mesa 1'), findsOneWidget);
    expect(find.text('Mesa 2'), findsOneWidget);
    expect(find.text('Mesa 3'), findsOneWidget);

    expect(find.text('Preparar'), findsOneWidget);
    expect(find.text('Pronto'), findsOneWidget);
  });
}
