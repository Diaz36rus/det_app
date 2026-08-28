import 'package:flutter/material.dart';

import '../app_splash.dart';
import 'auth_controller.dart';
import 'login_screen.dart';

/// Ждёт bootstrap сессии, затем Login или [child].
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthController.instance,
      builder: (context, _) {
        final auth = AuthController.instance;
        switch (auth.status) {
          case AuthStatus.bootstrapping:
            return const AppSplashScreen(subtitle: 'Проверка сессии…');
          case AuthStatus.signedOut:
            return const LoginScreen();
          case AuthStatus.signedIn:
            return child;
        }
      },
    );
  }
}
