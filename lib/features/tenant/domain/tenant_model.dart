import 'package:equatable/equatable.dart';

/// Representa uma empresa/estabelecimento ao qual o usuário tem acesso.
/// Um mesmo usuário pode pertencer a múltiplos tenants (ex.: dono de
/// mais de um bar), por isso a troca de tenant é uma tela própria.
class Tenant extends Equatable {
  final String id;
  final String name;
  final String? logoUrl;
  final String role; // ex.: 'owner', 'manager', 'waiter'

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
