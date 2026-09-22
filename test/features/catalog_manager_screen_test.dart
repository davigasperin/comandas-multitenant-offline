import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comandas_app/core/network/providers.dart';
import 'package:comandas_app/features/orders/data/catalog_repository.dart';
import 'package:comandas_app/features/orders/domain/catalog_models.dart';
import 'package:comandas_app/features/orders/presentation/catalog_manager_screen.dart';

class FakeCatalogRepository extends CatalogRepository {
  FakeCatalogRepository() : super(Dio());

  @override
  Future<List<CatalogCategory>> categories() async => [
    const CatalogCategory(id: 'c1', name: 'Bebidas', sortOrder: 1, active: true, productionArea: 'bar'),
  ];

  @override
  Future<List<CatalogProduct>> products() async => [
    const CatalogProduct(id: 'p1', name: 'Suco Natural', priceCents: 1200, active: true, available: true, sortOrder: 1),
  ];

  @override
  Future<List<DiningTableModel>> tables() async => [
    const DiningTableModel(id: 't1', label: 'Mesa 01', capacity: 4, x: 10, y: 10, width: 80, height: 80, shape: 'square', active: true, occupied: false),
  ];
}

void main() {
  testWidgets('CatalogManagerScreen exibe produtos e mapa de mesas', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
        ],
        child: const MaterialApp(
          home: CatalogManagerScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Catálogo e mesas'), findsOneWidget);
    expect(find.text('Suco Natural'), findsOneWidget);
    expect(find.text('R\$ 12,00'), findsOneWidget);
    expect(find.text('Mesa 01'), findsOneWidget);
  });
}
