import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

import '../../../core/network/providers.dart';
import '../domain/order_model.dart';
import 'order_detail_screen.dart';
import 'orders_screen.dart';

class PaymentRowItem {
  String method;
  int amountCents;
  int tenderedCents;
  final TextEditingController amountController;
  final TextEditingController tenderedController;

  PaymentRowItem({
    this.method = 'cash',
    this.amountCents = 0,
    this.tenderedCents = 0,
  })  : amountController = TextEditingController(),
        tenderedController = TextEditingController();

  void dispose() {
    amountController.dispose();
    tenderedController.dispose();
  }
}

class SettlementScreen extends ConsumerStatefulWidget {
  final Order order;

  const SettlementScreen({super.key, required this.order});

  @override
  ConsumerState<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends ConsumerState<SettlementScreen> {
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _serviceFeeController =
      TextEditingController(text: '10');
  String _discountType = 'fixed';

  List<PaymentRowItem> _payments = [];
  SettlementPreview? _preview;
  bool _isLoadingPreview = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _lockedIdempotencyKey;

  final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');

  @override
  void initState() {
    super.initState();
    _payments = [
      PaymentRowItem(
        method: 'cash',
        amountCents: widget.order.totalCents,
        tenderedCents: widget.order.totalCents,
      )
    ];
    _payments.first.amountController.text =
        _formatCents(widget.order.totalCents);
    _payments.first.tenderedController.text =
        _formatCents(widget.order.totalCents);
    _fetchPreview();
  }

  @override
  void dispose() {
    _discountController.dispose();
    _serviceFeeController.dispose();
    for (final p in _payments) {
      p.dispose();
    }
    super.dispose();
  }

  int _parseBrlToCents(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^0-9,\.]'), '').trim();
    if (cleaned.isEmpty) return 0;
    if (cleaned.contains(',')) {
      final parts = cleaned.replaceAll('.', '').split(',');
      final integerPart = int.tryParse(parts[0]) ?? 0;
      final decimalString =
          (parts.length > 1 ? parts[1] : '').padRight(2, '0').substring(0, 2);
      final decimalPart = int.tryParse(decimalString) ?? 0;
      return integerPart * 100 + decimalPart;
    } else if (cleaned.contains('.')) {
      final parts = cleaned.split('.');
      if (parts.length == 2 && parts[1].length <= 2) {
        final integerPart = int.tryParse(parts[0]) ?? 0;
        final decimalString = parts[1].padRight(2, '0').substring(0, 2);
        final decimalPart = int.tryParse(decimalString) ?? 0;
        return integerPart * 100 + decimalPart;
      }
      final integerPart = int.tryParse(parts.join()) ?? 0;
      return integerPart * 100;
    } else {
      final val = int.tryParse(cleaned) ?? 0;
      return val * 100;
    }
  }

  int _parsePercentageToBps(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^0-9,\.]'), '').trim();
    if (cleaned.isEmpty) return 0;
    if (cleaned.contains(',')) {
      final parts = cleaned.replaceAll('.', '').split(',');
      final integerPart = int.tryParse(parts[0]) ?? 0;
      final decimalString =
          (parts.length > 1 ? parts[1] : '').padRight(2, '0').substring(0, 2);
      final decimalPart = int.tryParse(decimalString) ?? 0;
      return integerPart * 100 + decimalPart;
    } else if (cleaned.contains('.')) {
      final parts = cleaned.split('.');
      final integerPart = int.tryParse(parts[0]) ?? 0;
      final decimalString =
          (parts.length > 1 ? parts[1] : '').padRight(2, '0').substring(0, 2);
      final decimalPart = int.tryParse(decimalString) ?? 0;
      return integerPart * 100 + decimalPart;
    } else {
      final val = int.tryParse(cleaned) ?? 0;
      return val * 100;
    }
  }

  String _formatCents(int cents) {
    final value = cents / 100.0;
    return NumberFormat('#,##0.00', 'pt_BR').format(value);
  }

  Future<void> _fetchPreview() async {
    setState(() {
      _isLoadingPreview = true;
      _errorMessage = null;
    });

    final discountValue = _discountType == 'fixed'
        ? _parseBrlToCents(_discountController.text)
        : _parsePercentageToBps(_discountController.text);
    final serviceFeeBps = _parsePercentageToBps(_serviceFeeController.text);

    try {
      final preview =
          await ref.read(ordersRepositoryProvider).previewSettlement(
                orderId: widget.order.id,
                discountCents: _discountType == 'fixed' ? discountValue : 0,
                discountType: _discountType,
                discountValue: discountValue,
                serviceFeeBps: serviceFeeBps,
              );
      if (mounted) {
        setState(() {
          _preview = preview;
          _isLoadingPreview = false;
          if (_payments.length == 1) {
            _payments.first.amountCents = preview.totalCents;
            _payments.first.tenderedCents = preview.totalCents;
            _payments.first.amountController.text =
                _formatCents(preview.totalCents);
            _payments.first.tenderedController.text =
                _formatCents(preview.totalCents);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingPreview = false;
          _errorMessage = 'Erro ao atualizar prévia: $e';
        });
      }
    }
  }

  int get _payableTotalCents => _preview?.totalCents ?? widget.order.totalCents;

  int get _paidSumCents => _payments.fold(0, (sum, p) => sum + p.amountCents);

  int get _tenderedCashCents => _payments
      .where((p) => p.method == 'cash')
      .fold(0, (sum, p) => sum + p.tenderedCents);

  int get _cashAmountCents => _payments
      .where((p) => p.method == 'cash')
      .fold(0, (sum, p) => sum + p.amountCents);

  int get _trocoCents {
    final diff = _tenderedCashCents - _cashAmountCents;
    return diff > 0 ? diff : 0;
  }

  int get _remainingCents => _payableTotalCents - _paidSumCents;

  bool get _isPaymentValid {
    if (_isSubmitting || _isLoadingPreview) return false;
    if (_paidSumCents < _payableTotalCents) return false;
    for (final p in _payments) {
      if (p.amountCents <= 0) return false;
      if (p.method == 'cash' && p.tenderedCents < p.amountCents) return false;
    }
    return true;
  }

  Future<void> _submitSettlement() async {
    if (!_isPaymentValid) return;

    final rawRole = ref.read(currentTenantRoleProvider).valueOrNull;
    final role =
        const {'owner': 'manager', 'admin': 'manager'}[rawRole] ?? rawRole;
    final canSettle = const {'cashier', 'manager'}.contains(role);
    if (!canSettle) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apenas caixa ou gerente podem liquidar comandas.'),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    _lockedIdempotencyKey ??=
        'idemp_settle_${widget.order.id}_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(999999)}';

    final discountValue = _discountType == 'fixed'
        ? _parseBrlToCents(_discountController.text)
        : _parsePercentageToBps(_discountController.text);
    final serviceFeeBps = _parsePercentageToBps(_serviceFeeController.text);
    final paymentsPayload = _payments.map((p) {
      return {
        'method': p.method,
        'amount_cents': p.amountCents,
        'tendered_cents': p.method == 'cash' ? p.tenderedCents : p.amountCents,
      };
    }).toList();

    try {
      final success = await ref.read(ordersRepositoryProvider).settleOrder(
            orderId: widget.order.id,
            payments: paymentsPayload,
            discountCents: _discountType == 'fixed' ? discountValue : 0,
            discountType: _discountType,
            discountValue: discountValue,
            serviceFeeBps: serviceFeeBps,
            expectedVersion: widget.order.version,
            idempotencyKey: _lockedIdempotencyKey,
          );

      if (!mounted) return;

      if (success) {
        ref.invalidate(orderDetailProvider(widget.order.id));
        ref.invalidate(openOrdersProvider);
        ref.invalidate(closedOrdersProvider);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.order.tableLabel} liquidada com sucesso.'),
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Falha na confirmação da liquidação.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Erro ao liquidar: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro na liquidação: $e')),
      );
    }
  }

  Future<void> _generatePixCharge() async {
    if (_payments.length != 1 || _payments.first.method != 'pix') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Para o Pix automático, use uma única forma de pagamento Pix.')),
      );
      return;
    }
    final discountValue = _discountType == 'fixed'
        ? _parseBrlToCents(_discountController.text)
        : _parsePercentageToBps(_discountController.text);
    final serviceFeeBps = _parsePercentageToBps(_serviceFeeController.text);
    setState(() => _isSubmitting = true);
    try {
      final charge = await ref.read(ordersRepositoryProvider).createPixCharge(
            orderId: widget.order.id,
            expectedVersion: widget.order.version,
            discountCents: _discountType == 'fixed' ? discountValue : 0,
            discountType: _discountType,
            discountValue: discountValue,
            serviceFeeBps: serviceFeeBps,
          );
      if (!mounted) return;
      final payload = charge['copy_paste']?.toString() ?? '';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cobrança Pix criada'),
          content: SelectableText(payload),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: payload));
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Pix copia e cola copiado.')),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copiar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar Pix: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _addPaymentRow() {
    setState(() {
      final remaining = _remainingCents > 0 ? _remainingCents : 0;
      final newRow = PaymentRowItem(
        method: 'pix',
        amountCents: remaining,
        tenderedCents: remaining,
      );
      newRow.amountController.text = _formatCents(remaining);
      newRow.tenderedController.text = _formatCents(remaining);
      _payments.add(newRow);
    });
  }

  void _removePaymentRow(int index) {
    if (_payments.length <= 1) return;
    setState(() {
      _payments[index].dispose();
      _payments.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rawRole = ref.watch(currentTenantRoleProvider).valueOrNull;
    final role =
        const {'owner': 'manager', 'admin': 'manager'}[rawRole] ?? rawRole;
    final canSettle = const {'cashier', 'manager'}.contains(role);

    return Scaffold(
      appBar: AppBar(
        title: Text('Liquidar ${widget.order.tableLabel}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade900),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ajustes e Taxas',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SizedBox(
                          width: 118,
                          child: DropdownButtonFormField<String>(
                            initialValue: _discountType,
                            decoration: const InputDecoration(
                              labelText: 'Desconto',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'fixed',
                                child: Text('R\$'),
                              ),
                              DropdownMenuItem(
                                value: 'percent',
                                child: Text('%'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _discountType = value;
                                _discountController.clear();
                              });
                              _fetchPreview();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _discountController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              labelText: _discountType == 'fixed'
                                  ? 'Valor do desconto'
                                  : 'Percentual',
                              hintText: '0,00',
                              prefixText:
                                  _discountType == 'fixed' ? 'R\$ ' : null,
                              suffixText:
                                  _discountType == 'percent' ? '%' : null,
                            ),
                            onChanged: (_) => _fetchPreview(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _serviceFeeController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Taxa de serviço (%)',
                              hintText: '10',
                              suffixText: '%',
                            ),
                            onChanged: (_) => _fetchPreview(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_isLoadingPreview)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Subtotal:'),
                          Text(
                            currency.format((_preview?.subtotalCents ??
                                    widget.order.totalCents) /
                                100.0),
                            style: GoogleFonts.firaCode(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Desconto:'),
                          Text(
                            '- ${currency.format((_preview?.discountCents ?? 0) / 100.0)}',
                            style: GoogleFonts.firaCode(color: Colors.green),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                              'Taxa (${((_preview?.serviceFeeBps ?? 1000) / 100).toStringAsFixed(1)}%):'),
                          Text(
                            '+ ${currency.format((_preview?.serviceFeeCents ?? 0) / 100.0)}',
                            style: GoogleFonts.firaCode(),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total a Pagar:',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            currency.format(_payableTotalCents / 100.0),
                            style: GoogleFonts.firaCode(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_payments.length == 1 && _payments.first.method == 'pix') ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isSubmitting ? null : _generatePixCharge,
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Gerar cobrança Pix automática'),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Formas de Pagamento',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          onPressed: _addPaymentRow,
                          icon: const Icon(Icons.add),
                          label: const Text('Dividir'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._payments.asMap().entries.map((entry) {
                      final index = entry.key;
                      final row = entry.value;
                      final isCash = row.method == 'cash';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<String>(
                                initialValue: row.method,
                                decoration: const InputDecoration(
                                  labelText: 'Método',
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'cash', child: Text('Dinheiro')),
                                  DropdownMenuItem(
                                      value: 'pix', child: Text('PIX')),
                                  DropdownMenuItem(
                                      value: 'credit', child: Text('Crédito')),
                                  DropdownMenuItem(
                                      value: 'debit', child: Text('Débito')),
                                  DropdownMenuItem(
                                      value: 'voucher', child: Text('Voucher')),
                                ],
                                onChanged: (val) {
                                  if (val == null) return;
                                  setState(() {
                                    row.method = val;
                                    if (val != 'cash') {
                                      row.tenderedCents = row.amountCents;
                                      row.tenderedController.text =
                                          row.amountController.text;
                                    }
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: row.amountController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Valor (R\$)',
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                ),
                                onChanged: (text) {
                                  setState(() {
                                    row.amountCents = _parseBrlToCents(text);
                                    if (!isCash) {
                                      row.tenderedCents = row.amountCents;
                                    }
                                  });
                                },
                              ),
                            ),
                            if (isCash) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: row.tenderedController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                    labelText: 'Recebido (R\$)',
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                  ),
                                  onChanged: (text) {
                                    setState(() {
                                      row.tenderedCents =
                                          _parseBrlToCents(text);
                                    });
                                  },
                                ),
                              ),
                            ],
                            if (_payments.length > 1)
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                onPressed: () => _removePaymentRow(index),
                              ),
                          ],
                        ),
                      );
                    }),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Informado:'),
                        Text(
                          currency.format(_paidSumCents / 100.0),
                          style:
                              GoogleFonts.firaCode(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Saldo Restante:'),
                        Text(
                          currency.format(
                              (_remainingCents > 0 ? _remainingCents : 0) /
                                  100.0),
                          style: GoogleFonts.firaCode(
                            color:
                                _remainingCents > 0 ? Colors.red : Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (_trocoCents > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Troco:'),
                          Text(
                            currency.format(_trocoCents / 100.0),
                            style: GoogleFonts.firaCode(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: _isPaymentValid && canSettle
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade400,
                foregroundColor: Colors.white,
              ),
              onPressed:
                  _isPaymentValid && canSettle ? _submitSettlement : null,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Confirmar Pagamento'),
            ),
            if (!canSettle)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Apenas caixa ou gerente podem liquidar comandas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
