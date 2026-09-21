import 'package:equatable/equatable.dart';

/// Representa uma empresa/estabelecimento ao qual o usuário tem acesso.
/// Um mesmo usuário pode pertencer a múltiplos tenants (ex.: dono de
/// mais de um bar), por isso a troca de tenant é uma tela própria.
class Tenant extends Equatable {
  final String id;
  final String name;
  final String? logoUrl;
  final String role;

  String get roleLabel {
    switch (role) {
      case 'owner':
        return 'Proprietário';
      case 'manager':
        return 'Gerente';
      case 'waiter':
        return 'Garçom';
      case 'kitchen':
        return 'Cozinha';
      case 'admin':
        return 'Administrador';
      case 'cashier':
        return 'Caixa';
      case 'staff':
        return 'Equipe';
      default:
        return 'Membro';
    }
  }

  const Tenant({
    required this.id,
    required this.name,
    required this.role,
    this.logoUrl,
  });

  factory Tenant.fromJson(Map<String, dynamic> json) => Tenant(
        id: json['id'] as String,
        name: json['name'] as String,
        role: json['role'] as String? ?? 'member',
        logoUrl: json['logo_url'] as String?,
      );

  @override
  List<Object?> get props => [id, name, role, logoUrl];
}
