import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import 'login_screen.dart';

/// Decide, na abertura do app, se o usuário cai direto no dashboard
/// (sessão + tenant já salvos) ou precisa logar de novo.
class SessionGate extends ConsumerWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authRepo = ref.watch(authRepositoryProvider);

    return FutureBuilder<bool>(
      future: authRepo.hasValidSession(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final hasSession = snapshot.data ?? false;
        return hasSession ? const DashboardScreen() : const LoginScreen();
      },
    );
  }
}
