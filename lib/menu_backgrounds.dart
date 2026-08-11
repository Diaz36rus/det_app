import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Фоновые картинки пунктов меню / цехов.
/// Файлы: [assets/bg/] — см. README.txt там же.
class MenuBackgrounds {
  MenuBackgrounds._();

  static const folder = 'assets/bg';

  /// Путь к asset или null (нет привязки).
  static String? assetFor({
    required int selectedIndex,
    String? workshop,
  }) {
    if (selectedIndex == 100) {
      return switch (workshop) {
        'Мойка' => '$folder/bg_workshop_wash.jpg',
        'Химчистка' => '$folder/bg_workshop_dryclean.jpg',
        'Полировка' => '$folder/bg_workshop_polish.jpg',
        'Оклейка' => '$folder/bg_workshop_wrap.jpg',
        'Интерьер' => '$folder/bg_workshop_interior.jpg',
        'Оборудование' => '$folder/bg_workshop_equipment.jpg',
        _ => null,
      };
    }

    return switch (selectedIndex) {
      0 => '$folder/bg_board.jpg',
      1 => '$folder/bg_new_order.jpg',
      2 => '$folder/bg_calendar.jpg',
      3 => '$folder/bg_clients.jpg',
      4 => '$folder/bg_cash.jpg',
      5 => '$folder/bg_stats.jpg',
      6 => '$folder/bg_masters.jpg',
      7 => '$folder/bg_inventory.jpg',
      8 => '$folder/bg_preview.jpg',
      9 => '$folder/bg_completed.jpg',
      _ => null,
    };
  }

  /// Подложка: тёмный фон + очень тихая картинка (если файл есть).
  static Widget buildLayer({
    required int selectedIndex,
    String? workshop,
    required Widget child,
  }) {
    final asset = assetFor(selectedIndex: selectedIndex, workshop: workshop);
    return ColoredBox(
      color: AppColors.bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (asset != null)
            Positioned.fill(
              child: Image.asset(
                asset,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                // Видно, но не спорит с карточками/таблицами.
                opacity: const AlwaysStoppedAnimation(0.28),
              ),
            ),
          if (asset != null)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.bg.withOpacity(0.35),
                      AppColors.bg.withOpacity(0.55),
                      AppColors.bg.withOpacity(0.72),
                    ],
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}
