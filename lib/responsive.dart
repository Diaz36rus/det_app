import 'package:flutter/material.dart';

/// Breakpoints и хелперы адаптивной вёрстки (desktop sidebar vs mobile drawer).
class AppResponsive {
  static const double breakpoint = 900;

  /// Минимальная зона нажатия на телефоне.
  static const double minTap = 48;

  static const double pagePadHMobile = 14;
  static const double pagePadHDesktop = 24;
  static const double pagePadVMobile = 12;
  static const double pagePadVDesktop = 20;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < breakpoint;

  static bool isWide(BuildContext context) => !isMobile(context);

  static double pagePadH(BuildContext context) =>
      isMobile(context) ? pagePadHMobile : pagePadHDesktop;

  static double pagePadV(BuildContext context) =>
      isMobile(context) ? pagePadVMobile : pagePadVDesktop;

  static EdgeInsets pageInsets(BuildContext context, {double bottom = 16}) {
    final h = pagePadH(context);
    final t = pagePadV(context);
    return EdgeInsets.fromLTRB(h, t, h, bottom);
  }

  /// Ширина диалога: на телефоне почти на весь экран, на desktop — [desktop].
  static double dialogWidth(BuildContext context, {double desktop = 480}) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < breakpoint) return (w - 24).clamp(280.0, w);
    return desktop;
  }

  static EdgeInsets dialogInsetPadding(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.symmetric(horizontal: 10, vertical: 16);
    }
    return const EdgeInsets.symmetric(horizontal: 40, vertical: 24);
  }

  /// Ширина колонки канбана на телефоне (~86% экрана, peek следующей).
  static double kanbanColumnWidth(BuildContext context) {
    if (!isMobile(context)) return 280;
    final w = MediaQuery.sizeOf(context).width;
    return (w * 0.86).clamp(260.0, 340.0);
  }
}
