import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/network/providers.dart';
import '../../../core/network/socket_service.dart';
import '../domain/order_model.dart';
import '../presentation/order_detail_screen.dart';
import '../presentation/orders_screen.dart';

class KdsScreen extends ConsumerStatefulWidget {
  const KdsScreen({super.key});

  @override
  ConsumerState<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends ConsumerState<KdsScreen> {
  Timer? _pollingTimer;
  Timer? _clockTimer;
  StreamSubscription<String>? _orderEventsSubscription;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final socket = ref.read(socketServiceProvider);
      socket.connect();
      _orderEventsSubscription = socket.orderEventsStream.listen((_) {
        if (mounted) _invalidateAll();
      });
    });

    // Fallback de polling a cada 30s + relógio para cálculo do tempo de espera
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.invalidate(openOrdersProvider);
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _clockTimer?.cancel();
    _orderEventsSubscription?.cancel();
    super.dispose();
  }

  void _invalidateAll() {
    ref.invalidate(openOrdersProvider);
    ref.invalidate(closedOrdersProvider);
  }

  String _formatAge(DateTime openedAt) {
    final diff = _now.difference(openedAt);
    if (diff.inHours > 0) {
      return '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
    }
    if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ${diff.inSeconds.remainder(60)}s';
    }
    return '${diff.inSeconds}s';
  }

  Future<void> _updateStatus(
      String orderId, String targetStatus, String label) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(ordersRepositoryProvider)
          .updateOrderStatus(orderId: orderId, status: targetStatus);
      _invalidateAll();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Erro ao atualizar para $label: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Escuta eventos em tempo real do socket para invalidar o estado
    ref.listen(socketServiceProvider, (previous, next) {});

    // Escuta o fluxo de conexão do WebSocket
    final connectionStateAsync = ref.watch(socketConnectionStateProvider);
    final isConnected =
        connectionStateAsync.valueOrNull == SocketConnectionState.connected;

    final ordersAsync = ref.watch(openOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('KDS - Cozinha'),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color:
                    isConnected ? Colors.green.shade700 : Colors.red.shade700,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isConnected ? 'CONECTADO' : 'DESCONECTADO',
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => _invalidateAll(),
          ),
        ],
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text('Erro ao carregar KDS: $err'),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => _invalidateAll(),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
        data: (orders) {
          // Filtra pedidos fechados ou cancelados
          final activeOrders = orders
              .where((o) =>
                  o.status != OrderStatus.closed &&
                  o.status != OrderStatus.canceled)
              .toList();

          final openList =
              activeOrders.where((o) => o.status == OrderStatus.open).toList();
          final prepList = activeOrders
              .where((o) => o.status == OrderStatus.sentToKitchen)
              .toList();
          final deliveredList = activeOrders
              .where((o) => o.status == OrderStatus.delivered)
              .toList();

          return LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      child: _buildColumn(
                          context, 'Novos', openList, isConnected,
                          primaryActionName: 'Preparar',
                          targetStatus: 'sentToKitchen')),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(
                      child: _buildColumn(
                          context, 'Em preparo', prepList, isConnected,
                          primaryActionName: 'Pronto',
                          targetStatus: 'delivered')),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(
                      child: _buildColumn(
                          context, 'Prontos', deliveredList, isConnected)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildColumn(
    BuildContext context,
    String title,
    List<Order> orders,
    bool isConnected, {
    String? primaryActionName,
    String? targetStatus,
  }) {
    return Container(
      color: Colors.grey.shade50,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade200,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Badge(
                  label: Text('${orders.length}'),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
          Expanded(
            child: orders.isEmpty
                ? Center(
                    child: Text(
                      'Nenhum pedido',
                      style:
                          TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: orders.length,
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      final age = _formatAge(order.openedAt);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  OrderDetailScreen(orderId: order.id),
                            ),
                          ),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      order.tableLabel,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                    ),
                                    Row(
                                      children: [
                                        const Icon(Icons.timer_outlined,
                                            size: 14, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text(
                                          age,
                                          style: GoogleFonts.firaCode(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const Divider(height: 12),
                                ...order.items.map((item) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 2),
                                      child: Text(
                                        '• ${item.quantity}x ${item.productName}${item.notes != null ? " (${item.notes})" : ""}',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    )),
                                if (primaryActionName != null &&
                                    targetStatus != null) ...[
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        minimumSize: const Size(0, 36),
                                      ),
                                      onPressed: isConnected
                                          ? () => _updateStatus(order.id,
                                              targetStatus, primaryActionName)
                                          : null,
                                      icon: const Icon(Icons.arrow_forward,
                                          size: 16),
                                      label: Text(primaryActionName),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
