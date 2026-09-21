import 'package:comandas_app/features/tenant/domain/tenant_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('traduz os papéis conhecidos para português brasileiro', () {
    const labels = {
      'owner': 'Proprietário',
      'manager': 'Gerente',
      'waiter': 'Garçom',
      'kitchen': 'Cozinha',
      'admin': 'Administrador',
      'cashier': 'Caixa',
      'staff': 'Equipe',
      'member': 'Membro',
    };

    for (final entry in labels.entries) {
      final tenant = Tenant(id: '1', name: 'Teste', role: entry.key);
      expect(tenant.roleLabel, entry.value);
    }
  });

  test('usa rótulo localizado seguro para papel desconhecido', () {
    const tenant = Tenant(id: '1', name: 'Teste', role: 'desconhecido');

    expect(tenant.roleLabel, 'Membro');
  });
}
