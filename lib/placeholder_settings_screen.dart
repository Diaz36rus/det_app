import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Простые заглушки разделов «Студия» / «Уведомления».
class PlaceholderSettingsScreen extends StatelessWidget {
  const PlaceholderSettingsScreen({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.tune_rounded,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              decoration: AppTheme.panelDecoration,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, size: 28, color: AppColors.primary),
                  ),
                  const SizedBox(height: 18),
                  Text(title, style: AppTheme.pageTitle.copyWith(fontSize: 22), textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: AppTheme.pageSubtitle.copyWith(fontSize: 14, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
