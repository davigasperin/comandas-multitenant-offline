import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../tenant/data/tenant_repository.dart';
import '../domain/order_model.dart';
import '../domain/receipt_document.dart';

abstract class ReceiptService {
  Future<Uint8List> generateReceiptPdf(Order order);
  Future<bool> printReceipt(Order order);
}

class StandardReceiptService implements ReceiptService {
  final TenantRepository _tenantRepository;

  StandardReceiptService(this._tenantRepository);

  Future<String> _resolveEstablishmentName() async {
    try {
      final selectedId = await _tenantRepository.getSelectedTenantId();
      if (selectedId != null) {
        final tenants = await _tenantRepository.getMyTenants();
        final current = tenants.where((t) => t.id == selectedId).firstOrNull;
        if (current != null && current.name.trim().isNotEmpty) {
          return current.name.trim();
        }
      }
    } catch (_) {
      // Contingência segura para modo offline ou falha na listagem de empresas
    }
    return 'Estabelecimento';
  }

  @override
  Future<Uint8List> generateReceiptPdf(Order order) async {
    final establishment = await _resolveEstablishmentName();
    final document = ReceiptDocument(
      order: order,
      establishmentName: establishment,
    );
    return document.buildPdf();
  }

  @override
  Future<bool> printReceipt(Order order) async {
    final pdfBytes = await generateReceiptPdf(order);
    return Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: 'Comanda_${order.tableLabel.replaceAll(' ', '_')}',
    );
  }
}
