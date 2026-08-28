import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'defect_parts.dart';

/// Выгрузка фото дефектов: папка «клиент_машина» → подпапки по элементам.
class DefectPhotosExport {
  DefectPhotosExport._();

  static String sanitizeFolderName(String raw) {
    var s = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.isEmpty) return 'Без_имени';
    if (s.length > 80) s = s.substring(0, 80).trim();
    return s;
  }

  static String clientCarFolderName({
    required String clientName,
    required String makeModel,
    required String plate,
  }) {
    final parts = <String>[
      if (clientName.trim().isNotEmpty) clientName.trim(),
      if (makeModel.trim().isNotEmpty) makeModel.trim(),
      if (plate.trim().isNotEmpty) plate.trim(),
    ];
    if (parts.isEmpty) return 'Без_клиента';
    return sanitizeFolderName(parts.join('_'));
  }

  static Future<Directory> resolveRoot() async {
    Future<Directory?> tryDir(String path) async {
      try {
        final d = Directory(path);
        await d.create(recursive: true);
        final probe = File(p.join(d.path, '.write_ok'));
        await probe.writeAsString('ok', flush: true);
        await probe.delete();
        return d;
      } catch (_) {
        return null;
      }
    }

    if (!kIsWeb && Platform.isWindows) {
      final preferred = await tryDir(r'D:\DetApp\defects');
      if (preferred != null) return preferred;
    }
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) {
          final d = await tryDir(p.join(downloads.path, 'DetApp_defects'));
          if (d != null) return d;
        }
      } catch (_) {}
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final d = await tryDir(p.join(ext.path, 'DetApp_defects'));
          if (d != null) return d;
        }
      } catch (_) {}
    }
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(docs.path, 'det_app_defects'));
    await d.create(recursive: true);
    return d;
  }

  /// Пишет все фото из [defects] (+ опционально черновик) и открывает папку.
  /// Возвращает путь к папке заказа или `null`, если фото нет.
  static Future<String?> writeAll({
    required List<Map<String, dynamic>> defects,
    required String clientName,
    required String makeModel,
    required String plate,
    List<String> draftPhotosB64 = const [],
    String draftDescription = '',
    bool openFolder = true,
  }) async {
    final byPart = <String, List<Uint8List>>{};

    void addBytes(String part, Uint8List bytes) {
      if (bytes.isEmpty) return;
      byPart.putIfAbsent(part, () => []).add(bytes);
    }

    for (final d in defects) {
      final desc = d['description']?.toString() ?? '';
      final part = detectDefectPart(desc);
      final photos = (d['photos'] as List?) ?? const [];
      for (final photo in photos) {
        final b64 = (photo is Map ? photo['photo_b64'] : null)?.toString() ?? '';
        if (b64.isEmpty) continue;
        try {
          addBytes(part, base64Decode(b64));
        } catch (_) {}
      }
    }

    if (draftPhotosB64.isNotEmpty) {
      final part = draftDescription.trim().isEmpty
          ? kDefectPartOther
          : detectDefectPart(draftDescription);
      for (final b64 in draftPhotosB64) {
        if (b64.isEmpty) continue;
        try {
          addBytes(part, base64Decode(b64));
        } catch (_) {}
      }
    }

    if (byPart.isEmpty) return null;

    final root = await resolveRoot();
    final orderDir = Directory(
      p.join(
        root.path,
        clientCarFolderName(
          clientName: clientName,
          makeModel: makeModel,
          plate: plate,
        ),
      ),
    );
    if (await orderDir.exists()) {
      await orderDir.delete(recursive: true);
    }
    await orderDir.create(recursive: true);

    var total = 0;
    for (final entry in byPart.entries) {
      final partDir = Directory(
        p.join(orderDir.path, sanitizeFolderName(entry.key)),
      );
      await partDir.create(recursive: true);
      var i = 0;
      for (final photo in entry.value) {
        i += 1;
        total += 1;
        final file = File(
          p.join(partDir.path, '${i.toString().padLeft(3, '0')}.jpg'),
        );
        await file.writeAsBytes(photo, flush: true);
      }
    }

    if (total == 0) return null;

    if (openFolder) {
      try {
        await OpenFilex.open(orderDir.path);
      } catch (_) {}
    }
    return orderDir.path;
  }
}
