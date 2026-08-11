import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Простой автобэкап базы данных.
/// Копирует detailing.db в папку backups (максимум 14 копий, не чаще 1 раза в день).
class BackupHelper {
  static Future<void> runDailyBackup() async {
    try {
      // Та же папка Documents, где лежит detailing.db
      final docs = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(docs.path, "detailing.db"));

      // Если базы ещё нет — нечего копировать
      if (!await dbFile.exists()) return;

      final backupDir = Directory(p.join(docs.path, "det_app_backups"));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      // Уже делали бэкап сегодня? Тогда пропускаем
      final today = DateTime.now();
      final todayPrefix = "detailing_${_fmtDate(today)}_";
      final existing = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith(todayPrefix))
          .toList();
      if (existing.isNotEmpty) return;

      // Имя файла: detailing_2026-07-31_1902.db
      final stamp = "${_fmtDate(today)}_${_fmtTime(today)}";
      final destPath = p.join(backupDir.path, "detailing_$stamp.db");
      await dbFile.copy(destPath);

      // Оставляем только 14 самых свежих копий
      final allBackups = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith("detailing_") && f.path.endsWith(".db"))
          .toList();
      allBackups.sort((a, b) => b.path.compareTo(a.path)); // новые сверху
      if (allBackups.length > 14) {
        for (var old in allBackups.skip(14)) {
          await old.delete();
        }
      }
    } catch (_) {
      // Ошибка бэкапа не должна ронять программу
    }
  }

  /// Принудительный бэкап перед опасными действиями (очистка БД).
  /// Всегда создаёт копию, даже если бэкап уже был сегодня.
  static Future<String?> forceBackupNow() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(docs.path, "detailing.db"));
      if (!await dbFile.exists()) return null;

      final backupDir = Directory(p.join(docs.path, "det_app_backups"));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final now = DateTime.now();
      final stamp = "${_fmtDate(now)}_${_fmtTime(now)}";
      final destPath = p.join(backupDir.path, "detailing_$stamp.db");
      await dbFile.copy(destPath);

      final allBackups = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith("detailing_") && f.path.endsWith(".db"))
          .toList();
      allBackups.sort((a, b) => b.path.compareTo(a.path));
      if (allBackups.length > 14) {
        for (var old in allBackups.skip(14)) {
          await old.delete();
        }
      }
      return destPath;
    } catch (_) {
      return null;
    }
  }

  /// Время последнего бэкапа по имени файла `detailing_YYYY-MM-DD_HHMM.db`.
  static Future<DateTime?> lastBackupAt() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(docs.path, "det_app_backups"));
      if (!await backupDir.exists()) return null;
      final files = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith("detailing_") && f.path.endsWith(".db"))
          .toList();
      if (files.isEmpty) return null;
      files.sort((a, b) => b.path.compareTo(a.path));
      final name = p.basenameWithoutExtension(files.first.path);
      // detailing_2026-08-11_2154
      final m = RegExp(r'detailing_(\d{4}-\d{2}-\d{2})_(\d{2})(\d{2})$').firstMatch(name);
      if (m == null) return files.first.lastModifiedSync();
      final day = DateTime.parse(m.group(1)!);
      return DateTime(day.year, day.month, day.day, int.parse(m.group(2)!), int.parse(m.group(3)!));
    } catch (_) {
      return null;
    }
  }

  static String _fmtDate(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  }

  static String _fmtTime(DateTime d) {
    return "${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}";
  }
}
