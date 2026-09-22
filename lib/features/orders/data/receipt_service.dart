import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../tenant/data/tenant_repository.dart';
import '../domain/order_model.dart';
import '../domain/receipt_document.dart';
import '../../management/data/management_repository.dart';

abstract class ReceiptService {
  Future<Uint8List> generateReceiptPdf(Order order);
  Future<bool> printReceipt(Order order);
}

class StandardReceiptService implements ReceiptService {
  final TenantRepository _tenantRepository;
  final ManagementRepository? _managementRepository;

  StandardReceiptService(this._tenantRepository, [this._managementRepository]);

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
    var paperWidth = 80;
    try {
      final setting = await _managementRepository?.getPrinterSetting();
      paperWidth = (setting?['paper_width'] as num?)?.toInt() ?? 80;
    } catch (_) {
      // Mantém 80 mm em modo offline ou quando a preferência ainda não existe.
    }
    final document = ReceiptDocument(
      order: order,
      establishmentName: establishment,
      paperWidthMm: paperWidth,
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
