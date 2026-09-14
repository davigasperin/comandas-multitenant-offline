import 'package:equatable/equatable.dart';

class AuthUser extends Equatable {
  final String id;
  final String name;
  final String email;

  const AuthUser({required this.id, required this.name, required this.email});

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
      );

  @override
  List<Object?> get props => [id, name, email];
}

class AuthResult extends Equatable {
  final AuthUser user;
  final String accessToken;
  final String refreshToken;

  const AuthResult({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
      );

  @override
  List<Object?> get props => [user, accessToken, refreshToken];
}
