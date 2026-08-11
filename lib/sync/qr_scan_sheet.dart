import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:zxing2/qrcode.dart';

import '../app_theme.dart';
import 'sync_qr.dart';

/// Сканер QR внутри приложения → возвращает URL хоста или null.
/// Берёт кадр с камеры/из галереи и декодирует без системного браузера.
Future<String?> scanSyncHostQr(BuildContext context) async {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _QrScanSheet(),
  );
}

class _QrScanSheet extends StatefulWidget {
  const _QrScanSheet();

  @override
  State<_QrScanSheet> createState() => _QrScanSheetState();
}

class _QrScanSheetState extends State<_QrScanSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 92,
      );
      if (file == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final bytes = await file.readAsBytes();
      final url = _decodeQrUrl(bytes);
      if (!mounted) return;
      if (url == null) {
        setState(() {
          _busy = false;
          _error = 'QR не найден. Наведите чётче на код на экране ПК и повторите.';
        });
        return;
      }
      Navigator.pop(context, url);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Не удалось прочитать фото: $e';
      });
    }
  }

  String? _decodeQrUrl(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final src = (decoded.width > 1200 || decoded.height > 1200)
        ? img.copyResize(
            decoded,
            width: decoded.width > decoded.height ? 1200 : null,
            height: decoded.height >= decoded.width ? 1200 : null,
          )
        : decoded;

    final pixels = Int32List(src.width * src.height);
    var i = 0;
    for (final p in src) {
      pixels[i++] = (0xFF << 24) | (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
    }
    final source = RGBLuminanceSource(src.width, src.height, pixels);
    try {
      final result = QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source)));
      return parseSyncQrPayload(result.text);
    } catch (_) {
      try {
        final inverted = InvertedLuminanceSource(source);
        final result = QRCodeReader().decode(BinaryBitmap(HybridBinarizer(inverted)));
        return parseSyncQrPayload(result.text);
      } catch (_) {
        return null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Сканер QR хоста',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Сфотографируйте QR на экране ПК — адрес подставится в приложение. '
              'Не используйте системную камеру телефона (она откроет браузер).',
              style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13, height: 1.35),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: GoogleFonts.manrope(color: AppColors.danger, fontSize: 12, height: 1.3),
              ),
            ],
            const SizedBox(height: 14),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              ElevatedButton.icon(
                onPressed: () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined, size: 20),
                label: const Text('Сфотографировать QR'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 20),
                label: const Text('Выбрать из галереи'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
          ],
        ),
      ),
    );
  }
}
