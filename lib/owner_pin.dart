import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'access_model.dart';
import 'app_theme.dart';
import 'auth/auth_controller.dart';

/// Запрос PIN владельца приложения. `true` — верный PIN у platform owner.
Future<bool> confirmOwnerDestructivePin(
  BuildContext context, {
  required String actionTitle,
}) async {
  final user = AuthController.instance.user;
  if (user == null || !user.isPlatformAdmin) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Недостаточно прав', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: Text(
          'Только владелец приложения может выполнить: $actionTitle',
          style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.35),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
        ],
      ),
    );
    return false;
  }

  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(actionTitle, style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Введите PIN владельца приложения для подтверждения.',
            style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'PIN',
              counterText: '',
            ),
            onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim() == kOwnerDestructivePin),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim() == kOwnerDestructivePin),
          child: const Text('Подтвердить'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  if (ok == true) return true;
  if (ok == false && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Неверный PIN или отмена')),
    );
  }
  return false;
}
