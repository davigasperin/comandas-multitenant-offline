import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/network/providers.dart';
import '../domain/order_model.dart';
import '../domain/product_model.dart';
import 'orders_screen.dart';
import 'settlement_screen.dart';

final orderDetailProvider =
    FutureProvider.autoDispose.family<Order, String>((ref, orderId) {
  return ref.watch(ordersRepositoryProvider).getOrderById(orderId);
});

final productsProvider = FutureProvider.autoDispose<List<Product>>((ref) {
  return ref.watch(ordersRepositoryProvider).getProducts();
});

class OrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  bool _isAddingItem = false;
  bool _isPrinting = false;

  void _invalidateAll() {
    ref.invalidate(orderDetailProvider(widget.orderId));
    ref.invalidate(openOrdersProvider);
    ref.invalidate(closedOrdersProvider);
  }

  Future<void> _handlePrint(Order order) async {
    setState(() => _isPrinting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final receiptService = ref.read(receiptServiceProvider);
      await receiptService.printReceipt(order);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Erro ao imprimir comanda: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPrinting = false);
      }
    }
  }

  Future<void> _navigateToSettlement(Order order) async {
    final settled = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SettlementScreen(order: order),
      ),
    );
    if (settled == true && mounted) {
      _invalidateAll();
    }
  }

  Future<void> _confirmCloseOrder(BuildContext hostContext, Order order) async {
    await _navigateToSettlement(order);
  }

  Future<void> _showAddProductSheet() async {
    final productsAsync = await ref.read(productsProvider.future);
    if (!mounted) return;

    if (productsAsync.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum produto cadastrado no momento.')),
      );
      return;
    }

    Product selectedProduct = productsAsync.first;
    int quantity = 1;
    final notesController = TextEditingController();
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(modalContext).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Adicionar item',
                      style:
                          Theme.of(modalContext).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<Product>(
                      initialValue: selectedProduct,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Produto'),
                      items: productsAsync.map((product) {
                        return DropdownMenuItem<Product>(
                          value: product,
                          child: Text(
                            '${product.name} - ${currency.format(product.price)}',
                          ),
                        );
                      }).toList(),
                      onChanged: (product) {
                        if (product == null) return;
                        setModalState(() => selectedProduct = product);
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Quantidade:',
                            style: TextStyle(fontSize: 16)),
                        const Spacer(),
                        IconButton.outlined(
                          icon: const Icon(Icons.remove),
                          onPressed: quantity > 1
                              ? () => setModalState(() => quantity--)
                              : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '$quantity',
                            style: GoogleFonts.firaCode(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton.outlined(
                          icon: const Icon(Icons.add),
                          onPressed: () => setModalState(() => quantity++),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'Observações (opcional)',
                        hintText: 'Ex.: Sem cebola, gelo à parte',
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isAddingItem
                            ? null
                            : () async {
                                final selected = selectedProduct;
                                final qty = quantity;
                                final notes =
                                    notesController.text.trim().isEmpty
                                        ? null
                                        : notesController.text.trim();
                                setModalState(() => _isAddingItem = true);
                                final scaffoldMessenger =
                                    ScaffoldMessenger.of(context);
                                try {
                                  await ref
                                      .read(ordersRepositoryProvider)
                                      .addItem(
                                        orderId: widget.orderId,
                                        productId: selected.id,
                                        quantity: qty,
                                        notes: notes,
                                      );
                                  _invalidateAll();
                                  if (modalContext.mounted) {
                                    Navigator.of(modalContext).pop();
                                  }
                                } catch (err) {
                                  if (!mounted) return;
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(
                                      content:
                                          Text('Erro ao adicionar item: $err'),
                                    ),
                                  );
                                } finally {
                                  if (modalContext.mounted) {
                                    setModalState(() => _isAddingItem = false);
                                  }
                                  if (mounted) {
                                    setState(() => _isAddingItem = false);
                                  }
                                }
                              },
                        child: _isAddingItem
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Adicionar (${currency.format(selectedProduct.price * quantity)})',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(widget.orderId));
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhe da comanda'),
        actions: [
          orderAsync.whenOrNull(
                data: (order) => IconButton(
                  tooltip: 'Imprimir comanda',
                  icon: _isPrinting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.print_outlined),
                  onPressed: _isPrinting ? null : () => _handlePrint(order),
                ),
              ) ??
              const SizedBox.shrink(),
        ],
      ),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Erro: $err')),
        data: (order) {
          final isClosed = order.status == OrderStatus.closed;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      order.tableLabel,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: order.status.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: order.status.color.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        order.status.label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: order.status.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: order.items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.playlist_add,
                                size: 48, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text('Nenhum item lançado.'),
                            const SizedBox(height: 16),
                            if (!isClosed)
                              OutlinedButton(
                                onPressed: _showAddProductSheet,
                                child: const Text('Adicionar Primeiro Item'),
                              ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: order.items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = order.items[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title:
                                Text('${item.quantity}x ${item.productName}'),
                            subtitle: Text(
                              '${currency.format(item.unitPrice)} cada'
                              '${item.selectedOptions != null ? "\n• ${item.selectedOptions}" : ""}'
                              '${item.notes != null ? "\n• ${item.notes}" : ""}',
                            ),
                            trailing: Text(
                              currency.format(item.subtotal),
                              style: GoogleFonts.firaCode(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    Text(
                      currency.format(order.total),
                      style: GoogleFonts.firaCode(
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    if (!isClosed) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed:
                              _isAddingItem ? null : _showAddProductSheet,
                          icon: _isAddingItem
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.add_shopping_cart),
                          label: const Text('Item'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isClosed
                              ? Colors.grey.shade400
                              : Theme.of(context).colorScheme.error,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: isClosed || _isAddingItem
                            ? null
                            : () => _confirmCloseOrder(context, order),
                        child: Text(isClosed ? 'Fechada' : 'Fechar'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
