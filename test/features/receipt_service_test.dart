import 'package:comandas_app/features/orders/data/receipt_service.dart';
import 'package:comandas_app/features/orders/domain/order_model.dart';
import 'package:comandas_app/features/tenant/data/tenant_repository.dart';
import 'package:comandas_app/features/tenant/domain/tenant_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import '../mocks/fake_secure_storage.dart';

class MockTenantRepository extends TenantRepository {
  MockTenantRepository() : super(Dio(), FakeSecureStorage());

  @override
  Future<String?> getSelectedTenantId() async => 'ten_1';

  @override
  Future<List<Tenant>> getMyTenants() async {
    return [
      const Tenant(id: 'ten_1', name: 'Bar do Zé Teste', role: 'owner'),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ReceiptService receiptService;
  late MockTenantRepository tenantRepository;

  setUp(() {
    tenantRepository = MockTenantRepository();
    receiptService = StandardReceiptService(tenantRepository);
  });

  final testOrder = Order(
    id: 'ord_123',
    tableLabel: 'Mesa 05',
    status: OrderStatus.open,
    openedAt: DateTime.parse('2026-09-14T19:30:00Z'),
    items: const [
      OrderItem(
        id: 'it_1',
        productName: 'Chopp Pilsen',
        quantity: 3,
        unitPrice: 12.0,
        notes: 'Caneca congelada',
      ),
      OrderItem(
        id: 'it_2',
        productName: 'Porção de Pastel',
        quantity: 1,
        unitPrice: 28.0,
      ),
    ],
  );

  test('generateReceiptPdf generates valid non-empty 80mm PDF bytes', () async {
    final pdfBytes = await receiptService.generateReceiptPdf(testOrder);

    expect(pdfBytes, isNotNull);
    expect(pdfBytes.isNotEmpty, isTrue);
    // PDF Magic bytes %PDF
    expect(pdfBytes.sublist(0, 4), equals([0x25, 0x50, 0x44, 0x46]));
  });

  test('generateReceiptPdf handles empty order items without failure', () async {
    final emptyOrder = Order(
      id: 'ord_empty',
      tableLabel: 'Comanda 99',
      status: OrderStatus.open,
      openedAt: DateTime.now(),
      items: const [],
    );

    final pdfBytes = await receiptService.generateReceiptPdf(emptyOrder);
    expect(pdfBytes, isNotNull);
    expect(pdfBytes.length, greaterThan(100));
  });
}
