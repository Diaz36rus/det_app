import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';
import 'app_toast.dart';
import 'on_shift_controller.dart';

/// Компактный переключатель «На смене» в шапке.
class OnShiftChip extends StatelessWidget {
  const OnShiftChip({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OnShiftController.instance,
      builder: (context, _) {
        final c = OnShiftController.instance;
        if (!c.canToggle) return const SizedBox.shrink();
        final on = c.onShift;
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: on ? 'Вы на смене — нажмите, чтобы уйти' : 'Нажмите, чтобы выйти на смену',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: c.loading
                    ? null
                    : () async {
                        final err = await c.setOnShift(!on);
                        if (!context.mounted) return;
                        if (err != null) {
                          showAppToast(context, err);
                        } else {
                          showAppToast(
                            context,
                            !on ? 'Вы на смене' : 'Смена закрыта',
                          );
                        }
                      },
                child: Ink(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: on
                        ? AppColors.success.withValues(alpha: 0.18)
                        : AppColors.surface2.withValues(alpha: 0.9),
                    border: Border.all(
                      color: on
                          ? AppColors.success.withValues(alpha: 0.65)
                          : AppColors.border.withValues(alpha: 0.9),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: on ? AppColors.success : AppColors.textDim,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        on ? 'На смене' : 'Не на смене',
                        style: GoogleFonts.manrope(
                          color: on ? AppColors.success : AppColors.textMuted,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
