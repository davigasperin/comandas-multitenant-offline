import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/network/providers.dart';
import '../domain/order_model.dart';
import 'order_detail_screen.dart';

final openOrdersProvider = FutureProvider.autoDispose<List<Order>>((ref) {
  return ref.watch(ordersRepositoryProvider).getOpenOrders();
});

final closedOrdersProvider = FutureProvider.autoDispose<List<Order>>((ref) {
  return ref.watch(ordersRepositoryProvider).getClosedOrders();
});

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TabBarView(
      children: [
        _OrdersList(isClosed: false),
        _OrdersList(isClosed: true),
      ],
    );
  }
}

class _OrdersList extends ConsumerWidget {
  final bool isClosed;
  
  const _OrdersList({required this.isClosed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isClosed ? closedOrdersProvider : openOrdersProvider;
    final ordersAsync = ref.watch(provider);
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');

    return RefreshIndicator(
      onRefresh: () => ref.refresh(provider.future),
      child: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ListView(
          children: [
            const SizedBox(height: 80),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('Erro ao carregar comandas: $err', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => ref.refresh(provider.future),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          ],
        ),
        data: (orders) {
          if (orders.isEmpty) {
            return ListView(
              children: [
                const SizedBox(height: 80),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isClosed ? Icons.assignment_turned_in_outlined : Icons.receipt_long_outlined,
                        size: 48,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isClosed
                            ? 'Nenhuma comanda fechada.'
                            : 'Nenhuma comanda aberta no momento.',
                        style: const TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final order = orders[index];
              return Card(
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrderDetailScreen(orderId: order.id),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                order.tableLabel,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: order.status.color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: order.status.color.withValues(alpha: 0.3)),
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
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 84),
                          child: Text(
                            currency.format(order.total),
                            textAlign: TextAlign.right,
                            style: GoogleFonts.firaCode(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class CreateOrderFab extends ConsumerStatefulWidget {
  const CreateOrderFab({super.key});

  @override
  ConsumerState<CreateOrderFab> createState() => _CreateOrderFabState();
}

class _CreateOrderFabState extends ConsumerState<CreateOrderFab> {
  final _formKey = GlobalKey<FormState>();
  String _tableLabel = '';
  bool _isLoading = false;

  void _showDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Nova Comanda'),
          content: Form(
            key: _formKey,
            child: TextFormField(
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Mesa ou Cliente'),
              validator: (val) => val == null || val.trim().isEmpty 
                  ? 'Informe a mesa/comanda' 
                  : null,
              onSaved: (val) => _tableLabel = val!.trim(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: _submit,
              child: _isLoading 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Criar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(ordersRepositoryProvider);
      final newOrder = await repo.createOrder(tableLabel: _tableLabel);
      
      ref.invalidate(openOrdersProvider);
      
      navigator.pop(); // fecha dialog
      navigator.push(
        MaterialPageRoute(
          builder: (_) => OrderDetailScreen(orderId: newOrder.id),
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Erro ao criar comanda: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: _showDialog,
      icon: const Icon(Icons.add),
      label: const Text('Nova Comanda'),
    );
  }
}

