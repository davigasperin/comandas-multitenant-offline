import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comandas_app/core/network/providers.dart';
import 'package:comandas_app/features/orders/data/catalog_repository.dart';
import 'package:comandas_app/features/orders/domain/catalog_models.dart';
import 'package:comandas_app/features/orders/presentation/catalog_manager_screen.dart';

class FakeCatalogRepository extends CatalogRepository {
  bool deleteCalled = false;
  bool updateCalled = false;
  bool availabilityCalled = false;
  String? lastUpdatedName;
  int? lastUpdatedPriceCents;

  FakeCatalogRepository() : super(Dio());

  @override
  Future<List<CatalogCategory>> categories() async => [
    const CatalogCategory(id: 'c1', name: 'Bebidas', sortOrder: 1, active: true, productionArea: 'bar'),
  ];

  @override
  Future<List<CatalogProduct>> products() async => [
    const CatalogProduct(id: 'p1', name: 'Suco Natural', priceCents: 1200, active: true, available: true, sortOrder: 1),
    const CatalogProduct(id: 'p2', name: 'Sobremesa Inativa', priceCents: 1500, active: false, available: true, sortOrder: 2),
  ];

  @override
  Future<List<DiningTableModel>> tables() async => [
    const DiningTableModel(id: 't1', label: 'Mesa 01', capacity: 4, x: 10, y: 10, width: 80, height: 80, shape: 'square', active: true, occupied: false),
  ];

  @override
  Future<void> updateProduct({
    required String id,
    required String name,
    required int priceCents,
    String? categoryId,
    required bool available,
    required int sortOrder,
    bool? active,
  }) async {
    updateCalled = true;
    lastUpdatedName = name;
    lastUpdatedPriceCents = priceCents;
  }

  @override
  Future<void> setProductAvailability(String id, bool available) async {
    availabilityCalled = true;
  }

  @override
  Future<void> deleteProduct(String id) async {
    deleteCalled = true;
  }
}

void main() {
  testWidgets('CatalogManagerScreen exibe produtos, permite editar e excluir', (tester) async {
    final fakeRepo = FakeCatalogRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(fakeRepo),
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
    expect(find.text('Restaurar'), findsOneWidget);

    // 1. Alternar disponibilidade
    await tester.tap(find.byTooltip('Marcar esgotado'));
    await tester.pumpAndSettle();
    expect(fakeRepo.availabilityCalled, isTrue);

    // 2. Editar produto com valor em reais
    await tester.tap(find.byTooltip('Editar produto'));
    await tester.pumpAndSettle();

    expect(find.text('Editar produto'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Suco Natural'), 'Suco Especial');
    await tester.enterText(find.widgetWithText(TextFormField, '12,00'), '14,50');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(fakeRepo.updateCalled, isTrue);
    expect(fakeRepo.lastUpdatedName, 'Suco Especial');
    expect(fakeRepo.lastUpdatedPriceCents, 1450);

    // 3. Excluir produto com confirmação
    await tester.tap(find.byTooltip('Excluir produto'));
    await tester.pumpAndSettle();

    expect(find.text('Excluir produto?'), findsOneWidget);
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();

    expect(fakeRepo.deleteCalled, isTrue);
  });
}
