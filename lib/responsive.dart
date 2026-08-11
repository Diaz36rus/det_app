import 'package:flutter/material.dart';

/// Breakpoints и хелперы адаптивной вёрстки (desktop sidebar vs mobile drawer).
class AppResponsive {
  static const double breakpoint = 900;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < breakpoint;

  static bool isWide(BuildContext context) => !isMobile(context);

  /// Ширина диалога: на телефоне почти на весь экран, на desktop — [desktop].
  static double dialogWidth(BuildContext context, {double desktop = 480}) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < breakpoint) return (w - 32).clamp(280.0, w);
    return desktop;
  }

  static EdgeInsets dialogInsetPadding(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.symmetric(horizontal: 12, vertical: 24);
    }
    return const EdgeInsets.symmetric(horizontal: 40, vertical: 24);
  }
}
