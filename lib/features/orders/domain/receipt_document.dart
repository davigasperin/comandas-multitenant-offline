import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'order_model.dart';

class ReceiptDocument {
  final Order order;
  final String establishmentName;

  const ReceiptDocument({
    required this.order,
    required this.establishmentName,
  });

  Future<Uint8List> buildPdf() async {
    final pdf = pw.Document();
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  establishmentName.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  'CONTROLE DE CONSUMO',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
              pw.Divider(thickness: 1),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    order.tableLabel,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                  ),
                  pw.Text(
                    order.status.label.toUpperCase(),
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
              pw.Text(
                'Abertura: ${dateFmt.format(order.openedAt)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Divider(thickness: 1),
              pw.Text(
                'ITENS DO PEDIDO',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              if (order.items.isEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8),
                  child: pw.Text(
                    'Nenhum item lançado.',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                )
              else
                ...order.items.map(
                  (item) => pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Expanded(
                              child: pw.Text(
                                '${item.quantity}x ${item.productName}',
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                            pw.Text(
                              currency.format(item.subtotal),
                              style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        pw.Text(
                          '${currency.format(item.unitPrice)} un.',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                        if (item.notes != null && item.notes!.isNotEmpty)
                          pw.Text(
                            'Obs: ${item.notes}',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                      ],
                    ),
                  ),
                ),
              pw.Divider(thickness: 1),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    currency.format(order.total),
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Text(
                  '*** NÃO É DOCUMENTO FISCAL ***',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'Impresso em: ${dateFmt.format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.SizedBox(height: 12),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }
}
