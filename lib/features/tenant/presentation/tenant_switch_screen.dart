import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/tenant_model.dart';
import '../../dashboard/presentation/dashboard_screen.dart';

final myTenantsProvider = FutureProvider.autoDispose<List<Tenant>>((ref) {
  return ref.watch(tenantRepositoryProvider).getMyTenants();
});

/// Tela exibida logo após o login, mostrando todas as empresas que o
/// usuário pode acessar. É aqui que o "multi-tenant" fica visível na UI:
/// escolher a empresa define o contexto de todas as telas seguintes.
class TenantSwitchScreen extends ConsumerWidget {
  const TenantSwitchScreen({super.key});

  Future<void> _selectAndContinue(
    BuildContext context,
    WidgetRef ref,
    Tenant tenant,
  ) async {
    await ref.read(tenantRepositoryProvider).selectTenant(tenant);
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantsAsync = ref.watch(myTenantsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Selecione a empresa')),
      body: tenantsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Erro ao carregar empresas: $err')),
        data: (tenants) {
          if (tenants.isEmpty) {
            return const Center(child: Text('Nenhuma empresa vinculada.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: tenants.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final tenant = tenants[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text(tenant.name[0])),
                  title: Text(tenant.name),
                  subtitle: Text(tenant.role),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _selectAndContinue(context, ref, tenant),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
