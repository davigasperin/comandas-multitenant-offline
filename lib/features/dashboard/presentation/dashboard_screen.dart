import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../../auth/presentation/login_screen.dart';
import '../../orders/presentation/orders_screen.dart';
import '../../tenant/presentation/tenant_switch_screen.dart';

final syncPendingCountProvider = StateProvider<int>((ref) {
  final syncService = ref.watch(syncServiceProvider);
  return syncService.pendingCount;
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(authRepositoryProvider).logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Comandas'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.receipt_long), text: 'Abertas'),
              Tab(icon: Icon(Icons.check_circle_outline), text: 'Fechadas'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Sincronizar dados pendentes',
              icon: Badge(
                isLabelVisible: ref.watch(syncServiceProvider).pendingCount > 0,
                label: Text('${ref.watch(syncServiceProvider).pendingCount}'),
                child: const Icon(Icons.sync),
              ),
              onPressed: () async {
                final syncService = ref.read(syncServiceProvider);
                final messenger = ScaffoldMessenger.of(context);
                final count = await syncService.sync();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(syncService.lastError != null
                        ? 'Sincronização: $count itens enviados. Erro: ${syncService.lastError}'
                        : 'Sincronização concluída: $count itens enviados.'),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Trocar empresa',
              icon: const Icon(Icons.swap_horiz),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TenantSwitchScreen()),
              ),
            ),
            IconButton(
              tooltip: 'Sair',
              icon: const Icon(Icons.logout),
              onPressed: () => _logout(context, ref),
            ),
          ],
        ),
        body: const OrdersScreen(),
        floatingActionButton: const CreateOrderFab(),
      ),
    );
  }
}

