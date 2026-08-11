import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'database.dart';

/// Пытается сменить статус. При запрете «Выдан» показывает причины.
/// Возвращает `true`, если статус обновлён.
Future<bool> tryUpdateOrderStatus(
  BuildContext context,
  int orderId,
  String newStatus,
) async {
  final ok = await DatabaseHelper().updateStatus(orderId, newStatus);
  if (ok) return true;
  if (!context.mounted) return false;

  final reasons = await DatabaseHelper().validateIssueOrder(orderId);
  if (!context.mounted) return false;

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        "Нельзя выдать заказ",
        style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Сначала закройте долг, отметьте все работы и заполните чек-лист выдачи.",
                style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              for (final r in reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("• ", style: TextStyle(color: AppColors.danger)),
                      Expanded(
                        child: Text(
                          r,
                          style: GoogleFonts.manrope(
                            color: AppColors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Понятно"),
        ),
      ],
    ),
  );
  return false;
}
