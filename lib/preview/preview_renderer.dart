import 'package:flutter/material.dart';

import 'preview_config.dart';

/// Сменный рендер превью. Сейчас — ракурсы/плейсхолдер; позже — GLB.
abstract class PreviewRenderer {
  Widget build(BuildContext context, PreviewConfig config);
}

/// Плейсхолдер-силуэт седана: кузов красится, хром затемняется по конфигу.
/// Когда появятся PNG-слои в assets/preview/… — заменим на RasterPreviewRenderer.
class PlaceholderPreviewRenderer implements PreviewRenderer {
  const PlaceholderPreviewRenderer();

  @override
  Widget build(BuildContext context, PreviewConfig config) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return CustomPaint(
          size: Size(w, h),
          painter: _SedanPlaceholderPainter(config),
        );
      },
    );
  }
}

class _SedanPlaceholderPainter extends CustomPainter {
  final PreviewConfig config;

  _SedanPlaceholderPainter(this.config);

  Color get _chromeColor {
    const stock = Color(0xFFD4D4D8);
    final t = config.chrome.darkenAmount;
    if (t <= 0) return stock;
    // К почти чёрному матовому «антихрому».
    return Color.lerp(stock, const Color(0xFF111113), t.clamp(0.0, 1.0))!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + size.height * 0.04;
    final scale = (size.width < size.height ? size.width : size.height) * 0.82;

    canvas.save();
    canvas.translate(cx, cy);
    // Лёгкий сдвиг ракурса без новых ассетов.
    switch (config.camera) {
      case PreviewCamera.side:
        break;
      case PreviewCamera.rearQuarter:
        canvas.scale(-1.0, 1.0);
        canvas.skew(-0.12, 0);
        break;
      case PreviewCamera.frontQuarter:
        canvas.skew(0.12, 0);
        break;
    }

    final body = config.bodyColor;
    final chrome = _chromeColor;
    final glass = Color.lerp(body, const Color(0xFF0F172A), 0.72)!;

    // Тень
    final shadow = Paint()
      ..color = Colors.black.withOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(0, scale * 0.28), width: scale * 0.85, height: scale * 0.08),
      shadow,
    );

    // Кузов (упрощённый седан сбоку)
    final bodyPath = Path()
      ..moveTo(-scale * 0.42, scale * 0.08)
      ..lineTo(-scale * 0.38, -scale * 0.02)
      ..lineTo(-scale * 0.18, -scale * 0.06)
      ..lineTo(-scale * 0.08, -scale * 0.22)
      ..lineTo(scale * 0.18, -scale * 0.22)
      ..lineTo(scale * 0.32, -scale * 0.06)
      ..lineTo(scale * 0.44, -scale * 0.02)
      ..lineTo(scale * 0.46, scale * 0.08)
      ..lineTo(scale * 0.42, scale * 0.16)
      ..lineTo(-scale * 0.40, scale * 0.16)
      ..close();

    canvas.drawPath(
      bodyPath,
      Paint()
        ..color = body
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      bodyPath,
      Paint()
        ..color = Colors.white.withOpacity(0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Стёкла
    final glassPath = Path()
      ..moveTo(-scale * 0.06, -scale * 0.06)
      ..lineTo(-scale * 0.02, -scale * 0.18)
      ..lineTo(scale * 0.16, -scale * 0.18)
      ..lineTo(scale * 0.26, -scale * 0.06)
      ..close();
    canvas.drawPath(glassPath, Paint()..color = glass.withOpacity(0.92));

    // Колёса
    final tire = Paint()..color = const Color(0xFF0A0A0B);
    final rim = Paint()..color = chrome;
    for (final x in [-scale * 0.26, scale * 0.24]) {
      canvas.drawCircle(Offset(x, scale * 0.16), scale * 0.085, tire);
      canvas.drawCircle(Offset(x, scale * 0.16), scale * 0.045, rim);
    }

    // Хром: молдинг низа, ручки, зеркало, выхлоп
    final chromePaint = Paint()..color = chrome;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(0, scale * 0.11), width: scale * 0.78, height: scale * 0.018),
        const Radius.circular(2),
      ),
      chromePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-scale * 0.02, -scale * 0.02, scale * 0.04, scale * 0.012),
        const Radius.circular(2),
      ),
      chromePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(scale * 0.10, -scale * 0.02, scale * 0.04, scale * 0.012),
        const Radius.circular(2),
      ),
      chromePaint,
    );
    // Зеркало
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-scale * 0.10, -scale * 0.08, scale * 0.05, scale * 0.025),
        const Radius.circular(3),
      ),
      chromePaint,
    );
    // Насадка выхлопа
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(scale * 0.40, scale * 0.12, scale * 0.04, scale * 0.02),
        const Radius.circular(2),
      ),
      chromePaint,
    );

    // Блик на кузове
    final gloss = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.22),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(-scale * 0.4, -scale * 0.22, scale * 0.8, scale * 0.2));
    canvas.drawPath(bodyPath, gloss);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SedanPlaceholderPainter oldDelegate) {
    return oldDelegate.config.bodyColor != config.bodyColor ||
        oldDelegate.config.chrome != config.chrome ||
        oldDelegate.config.camera != config.camera ||
        oldDelegate.config.bodyStyleId != config.bodyStyleId;
  }
}
