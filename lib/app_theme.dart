import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Цвета приложения — тёмная студия детейлинга (не «админ-коробки»).
/// surface / surface2 — непрозрачные: drawer, сайдбар и карточки не смешивают текст
/// с фоном. Картинка меню — только в [MenuBackgrounds] под прозрачным контентом.
class AppColors {
  static const bg = Color(0xFF0B0D12);
  /// Панели / сайдбар / диалоги / drawer.
  static const surface = Color(0xFF141821);
  /// Карточки, поля ввода, колонки.
  static const surface2 = Color(0xFF1A2030);
  /// Мягкая линия разделения (почти невидима на фоне).
  static const border = Color(0xFF2A3344);
  /// Ещё тише — для неактивных обводок.
  static const borderSoft = Color(0xFF222A38);
  static const primary = Color(0xFF3B82F6);
  static const primarySoft = Color(0xFF1E3A5F);
  static const success = Color(0xFF22C55E);
  static const danger = Color(0xFFEF4444);
  static const text = Color(0xFFF1F5F9);
  static const textMuted = Color(0xFF94A3B8);
  static const textDim = Color(0xFF64748B);
}

/// Цвета статусов заказа — календарь, доска, карточка заказа.
const Map<String, Color> kOrderStatusColors = {
  "Предварительная запись": AppColors.textDim,
  "Принят в работу": AppColors.primary,
  "Мойка": Color(0xFF22D3EE),
  "Химчистка": Color(0xFFA78BFA),
  "Полировка": Color(0xFFF59E0B),
  "Оклейка": AppColors.danger,
  "Интерьер": Color(0xFF14B8A6),
  "Оборудование": Color(0xFFD97706),
  "Подготовка к выдаче": Color(0xFF6366F1),
  "Выдан": AppColors.success,
};

class AppTheme {
  static const double radius = 12;
  static const double radiusLg = 16;
  static const EdgeInsets pagePadding = EdgeInsets.all(24);

  static TextStyle get pageTitle => GoogleFonts.manrope(
        color: AppColors.text,
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      );

  static TextStyle get sectionTitle => GoogleFonts.manrope(
        color: AppColors.text,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      );

  static TextStyle get sectionLabel => GoogleFonts.manrope(
        color: AppColors.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      );

  /// Карточка без рамки — фон + лёгкая тень.
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x28000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      );

  /// Секция / колонка в диалогах — мягкий fill, без бордера.
  static BoxDecoration get panelDecoration => BoxDecoration(
        color: AppColors.surface2.withOpacity(0.92),
        borderRadius: BorderRadius.circular(radiusLg),
      );

  /// Интерактивный блок (кликабельный) — тонкая рамка.
  static BoxDecoration interactiveDecoration({
    Color? accent,
    bool emphasized = false,
  }) {
    final edge = accent ?? AppColors.border;
    return BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: emphasized ? edge.withOpacity(0.55) : edge.withOpacity(0.35),
        width: emphasized ? 1.25 : 1,
      ),
    );
  }

  /// KPI / метрика: цветной акцент слева, без коробки.
  static BoxDecoration kpiDecoration({required Color accent, bool emphasize = false}) {
    return BoxDecoration(
      color: emphasize ? AppColors.surface2 : AppColors.surface2.withOpacity(0.7),
      borderRadius: BorderRadius.circular(radius),
      border: Border(
        left: BorderSide(color: accent.withOpacity(emphasize ? 0.9 : 0.55), width: 3),
      ),
    );
  }

  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.success,
        surface: AppColors.surface,
        error: AppColors.danger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.text,
        onError: Colors.white,
      ),
    );

    return base.copyWith(
      textTheme: GoogleFonts.manropeTextTheme(base.textTheme).apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
      cardTheme: CardTheme(
        color: AppColors.surface2,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderSoft,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.surface2,
        foregroundColor: AppColors.textMuted,
        elevation: 0,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bg.withOpacity(0.55),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        labelStyle: const TextStyle(color: AppColors.textMuted),
        hintStyle: const TextStyle(color: AppColors.textDim),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppColors.borderSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF334155),
          disabledForegroundColor: AppColors.textMuted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textMuted,
          textStyle: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.borderSoft),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),
    );
  }
}
