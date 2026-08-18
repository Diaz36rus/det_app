import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_theme.dart';
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
            return Scaffold(
              backgroundColor: AppColors.bg,
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Проверка сессии…',
                      style: GoogleFonts.manrope(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            );
          case AuthStatus.signedOut:
            return const LoginScreen();
          case AuthStatus.signedIn:
            return child;
        }
      },
    );
  }
}
