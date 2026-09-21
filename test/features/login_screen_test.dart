import 'package:comandas_app/core/network/providers.dart';
import 'package:comandas_app/features/auth/data/auth_repository.dart';
import 'package:comandas_app/features/auth/domain/auth_models.dart';
import 'package:comandas_app/features/auth/presentation/login_screen.dart';
import 'package:comandas_app/core/errors/api_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import '../mocks/fake_secure_storage.dart';

class MockAuthRepository extends AuthRepository {
  MockAuthRepository() : super(Dio(), FakeSecureStorage());

  bool shouldFail = false;

  @override
  Future<AuthResult> login({required String email, required String password}) async {
    if (shouldFail) {
      throw const ApiException('Credenciais inválidas', statusCode: 401);
    }
    return const AuthResult(
      user: AuthUser(id: '1', name: 'Test', email: 'test@test.com'),
      accessToken: 'token',
      refreshToken: 'refresh',
    );
  }
}

void main() {
  testWidgets('LoginScreen mostra erros de validação para campos vazios', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.tap(find.text('Entrar'));
    await tester.pump();

    expect(find.text('E-mail inválido'), findsOneWidget);
    expect(find.text('Senha muito curta'), findsOneWidget);
  });

  testWidgets('LoginScreen mostra SnackBar de erro em falha da API', (tester) async {
    final mockRepo = MockAuthRepository()..shouldFail = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(mockRepo)],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, 'test@test.com');
    await tester.enterText(find.byType(TextFormField).last, '123456');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Credenciais inválidas'), findsOneWidget);
  });
}
