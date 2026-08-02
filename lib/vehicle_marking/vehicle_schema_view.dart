import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';
import 'tint_top_schema.dart';

class VehicleSchemaView extends StatefulWidget {
  final Set<String> selectedQuoteIds;
  final ValueChanged<String> onQuoteToggle;

  const VehicleSchemaView({
    super.key,
    required this.selectedQuoteIds,
    required this.onQuoteToggle,
  });

  @override
  State<VehicleSchemaView> createState() => _VehicleSchemaViewState();
}

class _VehicleSchemaViewState extends State<VehicleSchemaView> {
  String? _hoveredQuoteId;
  Size _paintSize = Size.zero;

  String? _hitTest(Offset local) {
    if (_paintSize == Size.zero) return null;
    for (final part in TintTopSchema.parts.reversed) {
      if (_roundedGlassPath(part.path, _paintSize).contains(local)) {
        return part.quoteId;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight.clamp(320.0, 720.0);
        final size = Size(h / 2.15, h);
        _paintSize = size;

        return Center(
          child: MouseRegion(
            onHover: (e) {
              final id = _hitTest(e.localPosition);
              if (id != _hoveredQuoteId) setState(() => _hoveredQuoteId = id);
            },
            onExit: (_) {
              if (_hoveredQuoteId != null) setState(() => _hoveredQuoteId = null);
            },
            cursor: _hoveredQuoteId != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                final id = _hitTest(details.localPosition);
                if (id != null) widget.onQuoteToggle(id);
              },
              child: CustomPaint(
                size: size,
                painter: _SedanTopPainter(
                  selectedQuoteIds: widget.selectedQuoteIds,
                  hoveredQuoteId: _hoveredQuoteId,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Offset _p(Size size, double x, double y) => Offset(x * size.width, y * size.height);

/// Скруглённый контур стекла по нормализованному полигону.
Path _roundedGlassPath(List<Offset> norm, Size size, {double radiusFactor = 0.035}) {
  if (norm.length < 3) return Path();
  final pts = norm.map((o) => Offset(o.dx * size.width, o.dy * size.height)).toList();
  final r = math.min(size.width, size.height) * radiusFactor;
  return _roundedPolygon(pts, r);
}

Path _roundedPolygon(List<Offset> pts, double radius) {
  final path = Path();
  final n = pts.length;
  for (int i = 0; i < n; i++) {
    final prev = pts[(i - 1 + n) % n];
    final curr = pts[i];
    final next = pts[(i + 1) % n];

    final toPrev = prev - curr;
    final toNext = next - curr;
    final lenPrev = toPrev.distance;
    final lenNext = toNext.distance;
    if (lenPrev < 0.001 || lenNext < 0.001) continue;

    final r = math.min(radius, math.min(lenPrev, lenNext) / 2.2);
    final p1 = curr + toPrev / lenPrev * r;
    final p2 = curr + toNext / lenNext * r;

    if (i == 0) {
      path.moveTo(p1.dx, p1.dy);
    } else {
      path.lineTo(p1.dx, p1.dy);
    }
    path.quadraticBezierTo(curr.dx, curr.dy, p2.dx, p2.dy);
  }
  path.close();
  return path;
}

/// Вид сверху седана — максимум деталей в CustomPainter.
class _SedanTopPainter extends CustomPainter {
  final Set<String> selectedQuoteIds;
  final String? hoveredQuoteId;

  _SedanTopPainter({
    required this.selectedQuoteIds,
    required this.hoveredQuoteId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawShadow(canvas, size);
    final body = _bodyPath(size);
    canvas.save();
    canvas.clipPath(body);
    _drawBodyFill(canvas, size, body);
    _drawHoodAndTrunk(canvas, size);
    _drawRoof(canvas, size);
    _drawDoorSeams(canvas, size);
    _drawPillars(canvas, size);
    _drawGlass(canvas, size);
    canvas.restore();

    _drawBodyStroke(canvas, body);
    _drawWheelArches(canvas, size);
    _drawWheels(canvas, size);
    _drawMirrors(canvas, size);
    _drawLights(canvas, size);
    _drawOrientation(canvas, size);
  }

  void _drawShadow(Canvas canvas, Size size) {
    final shadow = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.06, size.height * 0.03, size.width * 0.88, size.height * 0.94),
        Radius.circular(size.width * 0.2),
      ));
    canvas.drawPath(
      shadow,
      Paint()
        ..color = Colors.black.withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
  }

  Path _bodyPath(Size size) {
    final path = Path();
    path.moveTo(_p(size, 0.34, 0.035).dx, _p(size, 0.34, 0.035).dy);
    path.lineTo(_p(size, 0.66, 0.035).dx, _p(size, 0.66, 0.035).dy);
    path.cubicTo(
      _p(size, 0.82, 0.04).dx, _p(size, 0.82, 0.04).dy,
      _p(size, 0.91, 0.08).dx, _p(size, 0.91, 0.08).dy,
      _p(size, 0.915, 0.14).dx, _p(size, 0.915, 0.14).dy,
    );
    // правая передняя арка
    path.lineTo(_p(size, 0.925, 0.195).dx, _p(size, 0.925, 0.195).dy);
    path.cubicTo(
      _p(size, 0.99, 0.22).dx, _p(size, 0.99, 0.22).dy,
      _p(size, 0.99, 0.30).dx, _p(size, 0.99, 0.30).dy,
      _p(size, 0.93, 0.32).dx, _p(size, 0.93, 0.32).dy,
    );
    path.lineTo(_p(size, 0.93, 0.68).dx, _p(size, 0.93, 0.68).dy);
    // правая задняя арка
    path.cubicTo(
      _p(size, 0.99, 0.70).dx, _p(size, 0.99, 0.70).dy,
      _p(size, 0.99, 0.78).dx, _p(size, 0.99, 0.78).dy,
      _p(size, 0.925, 0.805).dx, _p(size, 0.925, 0.805).dy,
    );
    path.lineTo(_p(size, 0.915, 0.87).dx, _p(size, 0.915, 0.87).dy);
    path.cubicTo(
      _p(size, 0.90, 0.95).dx, _p(size, 0.90, 0.95).dy,
      _p(size, 0.78, 0.97).dx, _p(size, 0.78, 0.97).dy,
      _p(size, 0.66, 0.972).dx, _p(size, 0.66, 0.972).dy,
    );
    path.lineTo(_p(size, 0.34, 0.972).dx, _p(size, 0.34, 0.972).dy);
    path.cubicTo(
      _p(size, 0.22, 0.97).dx, _p(size, 0.22, 0.97).dy,
      _p(size, 0.10, 0.95).dx, _p(size, 0.10, 0.95).dy,
      _p(size, 0.085, 0.87).dx, _p(size, 0.085, 0.87).dy,
    );
    path.lineTo(_p(size, 0.075, 0.805).dx, _p(size, 0.075, 0.805).dy);
    path.cubicTo(
      _p(size, 0.01, 0.78).dx, _p(size, 0.01, 0.78).dy,
      _p(size, 0.01, 0.70).dx, _p(size, 0.01, 0.70).dy,
      _p(size, 0.07, 0.68).dx, _p(size, 0.07, 0.68).dy,
    );
    path.lineTo(_p(size, 0.07, 0.32).dx, _p(size, 0.07, 0.32).dy);
    path.cubicTo(
      _p(size, 0.01, 0.30).dx, _p(size, 0.01, 0.30).dy,
      _p(size, 0.01, 0.22).dx, _p(size, 0.01, 0.22).dy,
      _p(size, 0.075, 0.195).dx, _p(size, 0.075, 0.195).dy,
    );
    path.lineTo(_p(size, 0.085, 0.14).dx, _p(size, 0.085, 0.14).dy);
    path.cubicTo(
      _p(size, 0.09, 0.08).dx, _p(size, 0.09, 0.08).dy,
      _p(size, 0.18, 0.04).dx, _p(size, 0.18, 0.04).dy,
      _p(size, 0.34, 0.035).dx, _p(size, 0.34, 0.035).dy,
    );
    path.close();
    return path;
  }

  void _drawBodyFill(Canvas canvas, Size size, Path body) {
    final bounds = body.getBounds();
    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          bounds.topCenter,
          bounds.bottomCenter,
          const [
            Color(0xFF3A4660),
            Color(0xFF222B3C),
            Color(0xFF161D2A),
          ],
          const [0.0, 0.4, 1.0],
        ),
    );

    // боковой объём
    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width * 0.5, 0),
          const Offset(0, 0),
          [
            Colors.white.withOpacity(0.10),
            Colors.transparent,
          ],
        ),
    );
    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width * 0.5, 0),
          Offset(size.width, 0),
          [
            Colors.white.withOpacity(0.06),
            Colors.transparent,
          ],
        ),
    );
  }

  void _drawBodyStroke(Canvas canvas, Path body) {
    canvas.drawPath(
      body,
      Paint()
        ..color = const Color(0xFF6B7F9E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
    canvas.drawPath(
      body,
      Paint()
        ..color = Colors.white.withOpacity(0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawHoodAndTrunk(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFF4A5A72).withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15;

    final hood = Path()
      ..moveTo(_p(size, 0.27, 0.07).dx, _p(size, 0.27, 0.07).dy)
      ..lineTo(_p(size, 0.73, 0.07).dx, _p(size, 0.73, 0.07).dy)
      ..lineTo(_p(size, 0.80, 0.235).dx, _p(size, 0.80, 0.235).dy)
      ..lineTo(_p(size, 0.20, 0.235).dx, _p(size, 0.20, 0.235).dy)
      ..close();
    canvas.drawPath(
      hood,
      Paint()
        ..shader = ui.Gradient.linear(
          _p(size, 0.5, 0.07),
          _p(size, 0.5, 0.235),
          const [Color(0xFF2E3A50), Color(0xFF1C2433)],
        ),
    );
    canvas.drawPath(hood, line);
    canvas.drawLine(_p(size, 0.50, 0.085), _p(size, 0.50, 0.22), line);
    // боковые линии капота
    canvas.drawLine(_p(size, 0.38, 0.09), _p(size, 0.34, 0.22), line..strokeWidth = 0.9);
    canvas.drawLine(_p(size, 0.62, 0.09), _p(size, 0.66, 0.22), Paint()
      ..color = const Color(0xFF4A5A72).withOpacity(0.9)
      ..strokeWidth = 0.9);

    final trunk = Path()
      ..moveTo(_p(size, 0.25, 0.795).dx, _p(size, 0.25, 0.795).dy)
      ..lineTo(_p(size, 0.75, 0.795).dx, _p(size, 0.75, 0.795).dy)
      ..lineTo(_p(size, 0.71, 0.945).dx, _p(size, 0.71, 0.945).dy)
      ..lineTo(_p(size, 0.29, 0.945).dx, _p(size, 0.29, 0.945).dy)
      ..close();
    canvas.drawPath(
      trunk,
      Paint()
        ..shader = ui.Gradient.linear(
          _p(size, 0.5, 0.795),
          _p(size, 0.5, 0.945),
          const [Color(0xFF1C2433), Color(0xFF2A3548)],
        ),
    );
    canvas.drawPath(trunk, line);
  }

  void _drawRoof(Canvas canvas, Size size) {
    final roof = Path()
      ..moveTo(_p(size, 0.268, 0.355).dx, _p(size, 0.268, 0.355).dy)
      ..lineTo(_p(size, 0.732, 0.355).dx, _p(size, 0.732, 0.355).dy)
      ..lineTo(_p(size, 0.722, 0.675).dx, _p(size, 0.722, 0.675).dy)
      ..lineTo(_p(size, 0.278, 0.675).dx, _p(size, 0.278, 0.675).dy)
      ..close();
    canvas.drawPath(
      roof,
      Paint()
        ..shader = ui.Gradient.linear(
          _p(size, 0.5, 0.355),
          _p(size, 0.5, 0.675),
          const [Color(0xFF1A2230), Color(0xFF121820)],
        ),
    );
    canvas.drawPath(
      roof,
      Paint()
        ..color = const Color(0xFF3D4E68)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
  }

  void _drawDoorSeams(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4A5A72).withOpacity(0.65)
      ..strokeWidth = 1.05;

    // порог
    canvas.drawLine(_p(size, 0.115, 0.355), _p(size, 0.115, 0.67), paint);
    canvas.drawLine(_p(size, 0.885, 0.355), _p(size, 0.885, 0.67), paint);

    // разрез передней/задней двери (B)
    canvas.drawLine(_p(size, 0.135, 0.518), _p(size, 0.248, 0.518), paint);
    canvas.drawLine(_p(size, 0.752, 0.518), _p(size, 0.865, 0.518), paint);
  }

  void _drawPillars(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0xFF1A2230);

    // A — между лобовым и передними боковыми
    canvas.drawPath(
      Path()
        ..moveTo(_p(size, 0.235, 0.348).dx, _p(size, 0.235, 0.348).dy)
        ..lineTo(_p(size, 0.268, 0.355).dx, _p(size, 0.268, 0.355).dy)
        ..lineTo(_p(size, 0.248, 0.358).dx, _p(size, 0.248, 0.358).dy)
        ..close(),
      fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(_p(size, 0.765, 0.348).dx, _p(size, 0.765, 0.348).dy)
        ..lineTo(_p(size, 0.732, 0.355).dx, _p(size, 0.732, 0.355).dy)
        ..lineTo(_p(size, 0.752, 0.358).dx, _p(size, 0.752, 0.358).dy)
        ..close(),
      fill,
    );

    // B — между передними и задними боковыми
    void bPillar(double x0, double x1) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            size.width * x0,
            size.height * 0.505,
            size.width * x1,
            size.height * 0.532,
          ),
          const Radius.circular(2),
        ),
        fill,
      );
    }

    bPillar(0.132, 0.248);
    bPillar(0.752, 0.868);

    // C — у заднего стекла
    canvas.drawPath(
      Path()
        ..moveTo(_p(size, 0.255, 0.668).dx, _p(size, 0.255, 0.668).dy)
        ..lineTo(_p(size, 0.278, 0.675).dx, _p(size, 0.278, 0.675).dy)
        ..lineTo(_p(size, 0.265, 0.682).dx, _p(size, 0.265, 0.682).dy)
        ..close(),
      fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(_p(size, 0.745, 0.668).dx, _p(size, 0.745, 0.668).dy)
        ..lineTo(_p(size, 0.722, 0.675).dx, _p(size, 0.722, 0.675).dy)
        ..lineTo(_p(size, 0.735, 0.682).dx, _p(size, 0.735, 0.682).dy)
        ..close(),
      fill,
    );
  }

  void _drawWheelArches(Canvas canvas, Size size) {
    // тёмные вырезы у края кузова (визуальный акцент)
    final paint = Paint()..color = const Color(0xFF0A0D12).withOpacity(0.85);
    for (final c in const [
      Offset(0.035, 0.255),
      Offset(0.965, 0.255),
      Offset(0.035, 0.755),
      Offset(0.965, 0.755),
    ]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: _p(size, c.dx, c.dy),
          width: size.width * 0.09,
          height: size.height * 0.085,
        ),
        paint,
      );
    }
  }

  void _drawWheels(Canvas canvas, Size size) {
    for (final c in const [
      Offset(0.035, 0.255),
      Offset(0.965, 0.255),
      Offset(0.035, 0.755),
      Offset(0.965, 0.755),
    ]) {
      final center = _p(size, c.dx, c.dy);
      final tireW = size.width * 0.075;
      final tireH = size.height * 0.072;
      canvas.drawOval(
        Rect.fromCenter(center: center, width: tireW, height: tireH),
        Paint()..color = const Color(0xFF1A1F28),
      );
      canvas.drawOval(
        Rect.fromCenter(center: center, width: tireW * 0.55, height: tireH * 0.55),
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            tireW * 0.28,
            const [Color(0xFF6A7A92), Color(0xFF2A3344)],
          ),
      );
      canvas.drawOval(
        Rect.fromCenter(center: center, width: tireW * 0.22, height: tireH * 0.22),
        Paint()..color = const Color(0xFF121820),
      );
    }
  }

  void _drawMirrors(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0xFF2E3A50);
    final stroke = Paint()
      ..color = const Color(0xFF7A8BA8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    Path mirror(bool left) {
      final xBody = left ? 0.06 : 0.94;
      final xTip = left ? -0.01 : 1.01;
      final xMid = left ? 0.015 : 0.985;
      return Path()
        ..moveTo(_p(size, xBody, 0.335).dx, _p(size, xBody, 0.335).dy)
        ..lineTo(_p(size, xTip, 0.350).dx, _p(size, xTip, 0.350).dy)
        ..lineTo(_p(size, xMid, 0.392).dx, _p(size, xMid, 0.392).dy)
        ..lineTo(_p(size, xBody, 0.382).dx, _p(size, xBody, 0.382).dy)
        ..close();
    }

    for (final m in [mirror(true), mirror(false)]) {
      canvas.drawPath(m, fill);
      canvas.drawPath(m, stroke);
    }
  }

  void _drawLights(Canvas canvas, Size size) {
    final head = Paint()
      ..shader = ui.Gradient.linear(
        _p(size, 0.5, 0.04),
        _p(size, 0.5, 0.085),
        const [Color(0xFFF0F6FF), Color(0xFF6A9FD4)],
      );
    for (final rect in [
      Rect.fromLTRB(size.width * 0.17, size.height * 0.042, size.width * 0.31, size.height * 0.072),
      Rect.fromLTRB(size.width * 0.69, size.height * 0.042, size.width * 0.83, size.height * 0.072),
    ]) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(5)), head);
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(size.width * 0.35, size.height * 0.046, size.width * 0.65, size.height * 0.068),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF0A0D12),
    );

    final tail = Paint()
      ..shader = ui.Gradient.linear(
        _p(size, 0.5, 0.93),
        _p(size, 0.5, 0.97),
        const [Color(0xFFFF8A8A), Color(0xFFB91C1C)],
      );
    for (final rect in [
      Rect.fromLTRB(size.width * 0.19, size.height * 0.932, size.width * 0.34, size.height * 0.962),
      Rect.fromLTRB(size.width * 0.66, size.height * 0.932, size.width * 0.81, size.height * 0.962),
    ]) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(5)), tail);
    }
  }

  void _drawGlass(Canvas canvas, Size size) {
    for (final part in TintTopSchema.parts) {
      final selected = selectedQuoteIds.contains(part.quoteId);
      final hovered = hoveredQuoteId == part.quoteId;
      final path = _roundedGlassPath(part.path, size);
      final bounds = path.getBounds();

      if (selected) {
        // «затонированное» стекло
        canvas.drawPath(
          path,
          Paint()
            ..shader = ui.Gradient.linear(
              bounds.topLeft,
              bounds.bottomRight,
              [
                const Color(0xFF0B1220).withOpacity(0.92),
                const Color(0xFF152238).withOpacity(0.88),
                AppColors.primarySoft.withOpacity(0.75),
              ],
              const [0.0, 0.55, 1.0],
            ),
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = AppColors.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6,
        );
        canvas.drawPath(
          path,
          Paint()
            ..shader = ui.Gradient.linear(
              bounds.topCenter,
              bounds.center,
              [Colors.white.withOpacity(0.12), Colors.transparent],
            ),
        );
      } else {
        canvas.drawPath(
          path,
          Paint()
            ..shader = ui.Gradient.linear(
              bounds.topLeft,
              bounds.bottomRight,
              [
                const Color(0xFF8EB4D8).withOpacity(hovered ? 0.75 : 0.55),
                const Color(0xFF3A5570).withOpacity(hovered ? 0.7 : 0.5),
              ],
            ),
        );
        canvas.drawPath(
          path,
          Paint()
            ..shader = ui.Gradient.linear(
              bounds.topCenter,
              Offset(bounds.center.dx, bounds.top + bounds.height * 0.45),
              [
                Colors.white.withOpacity(hovered ? 0.35 : 0.22),
                Colors.transparent,
              ],
            ),
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = hovered ? AppColors.primary.withOpacity(0.9) : const Color(0xFFA8C8E8).withOpacity(0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = hovered ? 2.2 : 1.35,
        );
        if (hovered) {
          canvas.drawPath(
            path,
            Paint()..color = AppColors.primary.withOpacity(0.18),
          );
        }
      }
    }
  }

  void _drawOrientation(Canvas canvas, Size size) {
    final style = GoogleFonts.manrope(
      color: AppColors.textDim,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
    );
    final nose = TextPainter(
      text: TextSpan(text: 'ПЕРЕД', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    nose.paint(canvas, Offset((size.width - nose.width) / 2, 1));

    final rear = TextPainter(
      text: TextSpan(text: 'ЗАД', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    rear.paint(canvas, Offset((size.width - rear.width) / 2, size.height - rear.height - 1));
  }

  @override
  bool shouldRepaint(covariant _SedanTopPainter oldDelegate) {
    return oldDelegate.selectedQuoteIds != selectedQuoteIds ||
        oldDelegate.hoveredQuoteId != hoveredQuoteId;
  }
}
