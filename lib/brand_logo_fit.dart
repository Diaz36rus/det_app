import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vector_graphics/vector_graphics.dart';

/// Автомасштаб брендовых SVG: дотягивает иконки с «воздухом» в viewBox,
/// плотные (BMW/Mini) оставляют scale ≈ 1, без обрезки круга.
class BrandLogoFit {
  BrandLogoFit._();

  static final Map<String, double> _scale = {};
  static final Map<String, Future<double>> _inflight = {};

  /// Доля квадрата под непрозрачный контент.
  static const targetFill = 0.90;
  static const minScale = 0.88;
  static const maxScale = 2.05;

  static double? cached(String asset) => _scale[asset];

  static Future<double> resolve(String asset) {
    final hit = _scale[asset];
    if (hit != null) return Future<double>.value(hit);
    return _inflight.putIfAbsent(asset, () => _measure(asset));
  }

  static Future<double> _measure(String asset) async {
    if (!asset.toLowerCase().endsWith('.svg')) {
      return _store(asset, 1.0);
    }
    try {
      const int s = 96;
      final info = await vg.loadPicture(SvgAssetLoader(asset), null);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final sz = info.size;
      if (sz.width <= 0 || sz.height <= 0) {
        info.picture.dispose();
        return _store(asset, 1.0);
      }
      final fit = s / math.max(sz.width, sz.height);
      final dw = sz.width * fit;
      final dh = sz.height * fit;
      canvas.translate((s - dw) / 2, (s - dh) / 2);
      canvas.scale(fit);
      canvas.drawPicture(info.picture);
      info.picture.dispose();

      final image = await recorder.endRecording().toImage(s, s);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (bytes == null) return _store(asset, 1.0);

      var minX = s;
      var minY = s;
      var maxX = 0;
      var maxY = 0;
      var found = false;
      final data = bytes.buffer.asUint8List();
      for (var y = 0; y < s; y++) {
        for (var x = 0; x < s; x++) {
          final a = data[(y * s + x) * 4 + 3];
          if (a < 20) continue;
          found = true;
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
      if (!found) return _store(asset, 1.0);

      final bw = (maxX - minX + 1).toDouble();
      final bh = (maxY - minY + 1).toDouble();
      final frac = math.max(bw, bh) / s;
      if (frac < 0.05) return _store(asset, 1.0);

      final raw = targetFill / frac;
      return _store(asset, raw.clamp(minScale, maxScale).toDouble());
    } catch (_) {
      return _store(asset, 1.0);
    } finally {
      _inflight.remove(asset);
    }
  }

  static double _store(String asset, double v) {
    _scale[asset] = v;
    return v;
  }
}
