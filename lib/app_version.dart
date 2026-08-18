import 'package:package_info_plus/package_info_plus.dart';

/// Локальная версия приложения и схема БД.
///
/// [build] / [version] подтягиваются из pubspec через [PackageInfo].
/// [dbSchema] должен совпадать с `openDatabase(..., version:)` в database.dart.
class AppVersion {
  AppVersion._();

  /// Версия схемы SQLite (синхрон с DatabaseHelper).
  static const int dbSchema = 26;

  static PackageInfo? _info;

  static Future<void> ensureLoaded() async {
    _info ??= await PackageInfo.fromPlatform();
  }

  static String get version {
    final v = _info?.version;
    return (v == null || v.isEmpty) ? '0.0.0' : v;
  }

  static int get build {
    final b = int.tryParse(_info?.buildNumber ?? '');
    return b ?? 0;
  }

  static String get label => '$version+$build';
}
