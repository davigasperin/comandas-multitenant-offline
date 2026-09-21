import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../../auth/presentation/login_screen.dart';
import '../../orders/presentation/orders_screen.dart';
import '../../orders/presentation/kds_screen.dart';
import '../../tenant/presentation/tenant_switch_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isSyncing = false;

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Sair da conta?'),
        content: const Text('Você precisará entrar com e-mail e senha novamente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    ref.read(socketServiceProvider).disconnect();
    await ref.read(authRepositoryProvider).logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _handleSync(BuildContext context) async {
    setState(() => _isSyncing = true);
    final syncService = ref.read(syncServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final count = await syncService.sync();
      ref.invalidate(openOrdersProvider);
      ref.invalidate(closedOrdersProvider);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(syncService.lastError != null
              ? 'Sincronização: $count itens enviados. Erro: ${syncService.lastError}'
              : 'Sincronização concluída: $count itens enviados.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = ref.watch(syncServiceProvider).pendingCount;

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
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Badge(
                      isLabelVisible: pendingCount > 0,
                      label: Text('$pendingCount'),
                      child: const Icon(Icons.sync),
                    ),
              onPressed: _isSyncing ? null : () => _handleSync(context),
            ),
             IconButton(
               tooltip: 'KDS cozinha',
               icon: const Icon(Icons.view_kanban_outlined),
               onPressed: () => Navigator.of(context).push(
                 MaterialPageRoute(builder: (_) => const KdsScreen()),
               ),
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
              onPressed: _logout,
            ),
          ],
        ),
        body: const OrdersScreen(),
        floatingActionButton: const CreateOrderFab(),
      ),
    );
  }
}
