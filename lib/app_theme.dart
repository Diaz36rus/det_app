import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Тёмная студия как на ui-board: нейтральный уголь + violet только для акцентов.
class AppColors {
  /// Фон приложения.
  static const bg = Color(0xFF0B0B0F);
  /// Сайдбар / диалоги.
  static const surface = Color(0xFF121217);
  /// Карточки, колонки, поля.
  static const surface2 = Color(0xFF1A1A22);
  /// Линии (нейтральные, не фиолетовые).
  static const border = Color(0xFF2E2E3A);
  static const borderSoft = Color(0xFF23232C);
  /// Акцент действий / active.
  static const primary = Color(0xFFA78BFA);
  static const primarySoft = Color(0xFF2A2438);
  static const primaryDeep = Color(0xFF7C3AED);
  static const onPrimary = Color(0xFF0B0B0F);
  static const success = Color(0xFF22C55E);
  static const danger = Color(0xFFEF4444);
  static const text = Color(0xFFF4F4F5);
  static const textMuted = Color(0xFFA1A1AA);
  static const textDim = Color(0xFF71717A);
}

/// Цвета статусов заказа — календарь, доска, карточка заказа.
/// Разведены по hue (~каждый в своём секторе); предварительная — серый.
const Map<String, Color> kOrderStatusColors = {
  "Предварительная запись": Color(0xFF94A3B8), // slate / серый
  "Принят в работу": Color(0xFF1D4ED8), // глубокий синий
  "Мойка": Color(0xFF22D3EE), // cyan / вода
  "Химчистка": Color(0xFF9333EA), // фиолетовый
  "Полировка": Color(0xFFEAB308), // жёлтое золото
  "Кузовные работы": Color(0xFF64748B), // slate / металл
  "Оклейка": Color(0xFFEC4899), // розовый
  "Интерьер": Color(0xFF84CC16), // лайм
  "Оборудование": Color(0xFFC2410C), // кирпичный / медь
  "Подготовка к выдаче": Color(0xFFF97316), // оранжевый
  "Выдан": AppColors.success, // зелёный
};

class AppTheme {
  static const double radius = 12;
  static const double radiusLg = 16;
  static const EdgeInsets pagePadding = EdgeInsets.all(24);

  /// Заголовок страницы с учётом ширины (на телефоне меньше — AppBar уже показывает title).
  static TextStyle pageTitleFor(BuildContext context, {bool inAppBar = false}) {
    final mobile = MediaQuery.sizeOf(context).width < 900;
    if (inAppBar) {
      return GoogleFonts.manrope(
        color: AppColors.text,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      );
    }
    return pageTitle.copyWith(fontSize: mobile ? 22 : 26);
  }

  static TextStyle get pageTitle => GoogleFonts.manrope(
        color: AppColors.text,
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      );

  static TextStyle get pageSubtitle => GoogleFonts.manrope(
        color: AppColors.textDim,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.35,
      );

  static TextStyle get sectionTitle => GoogleFonts.manrope(
        color: AppColors.text,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      );

  static TextStyle get sectionLabel => GoogleFonts.manrope(
        color: AppColors.textDim,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      );

  /// Карточка: нейтральная обводка (violet — только акцентным элементам).
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.borderSoft),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      );

  static BoxDecoration get panelDecoration => BoxDecoration(
        color: AppColors.surface2.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(radiusLg),
        border: Border.all(color: AppColors.borderSoft),
      );

  /// Строка списка (клиент / сотрудник / завершённый): мягкая рамка.
  /// Левый акцент — только через равномерный border (иначе radius+clip режут контент).
  static BoxDecoration listTileDecoration({Color? accent}) {
    final edge = accent ?? AppColors.primary;
    return BoxDecoration(
      color: AppColors.surface2.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(radiusLg),
      border: Border.all(color: edge.withValues(alpha: 0.45)),
    );
  }

  static BoxDecoration interactiveDecoration({
    Color? accent,
    bool emphasized = false,
  }) {
    final edge = accent ?? AppColors.border;
    return BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: emphasized ? edge.withValues(alpha: 0.55) : edge.withValues(alpha: 0.35),
        width: emphasized ? 1.25 : 1,
      ),
    );
  }

  static BoxDecoration kpiDecoration({required Color accent, bool emphasize = false}) {
    return BoxDecoration(
      color: emphasize ? AppColors.surface2 : AppColors.surface2.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(radius),
      border: Border(
        left: BorderSide(color: accent.withValues(alpha: emphasize ? 0.9 : 0.55), width: 3),
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
        onPrimary: AppColors.onPrimary,
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
      cardTheme: CardThemeData(
        color: AppColors.surface2,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: AppColors.borderSoft),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderSoft,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
        elevation: 0,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: const BorderSide(color: AppColors.border, width: 1.4),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return AppColors.surface2;
        }),
        checkColor: WidgetStateProperty.all(AppColors.onPrimary),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface2,
        selectedColor: AppColors.primarySoft,
        disabledColor: AppColors.surface,
        labelStyle: GoogleFonts.manrope(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
        secondaryLabelStyle: GoogleFonts.manrope(
          color: AppColors.text,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
        side: const BorderSide(color: AppColors.borderSoft),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface2,
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
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.borderSoft,
          disabledForegroundColor: AppColors.textMuted,
          elevation: 0,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.borderSoft,
          disabledForegroundColor: AppColors.textMuted,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textMuted,
          minimumSize: const Size(44, 44),
          textStyle: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.border),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: AppColors.textMuted,
        ),
      ),
    );
  }
}
