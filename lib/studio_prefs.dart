import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';

/// Локальные настройки студии (app_settings). Облачный профиль — отдельно через Auth.
class StudioPrefs {
  StudioPrefs._();

  static const phone = 'studio_phone';
  static const address = 'studio_address';
  static const whatsapp = 'studio_whatsapp';
  static const website = 'studio_website';
  static const calendarStartHour = 'calendar_start_hour';
  static const calendarEndHour = 'calendar_end_hour';
  static const defaultBranchId = 'studio_default_branch_id';
  static const defaultCashRegisterId = 'studio_default_cash_register_id';
  static const tplBooking = 'msg_tpl_booking';
  static const tplDebt = 'msg_tpl_debt';
  static const tplReady = 'msg_tpl_ready';
  static const logoPathKey = 'studio_logo_path';

  static const defaultStartHour = 8;
  static const defaultEndHour = 22;

  static Future<Map<String, String>> loadContacts() async {
    final db = DatabaseHelper();
    return {
      'phone': (await db.getAppSetting(phone)) ?? '',
      'address': (await db.getAppSetting(address)) ?? '',
      'whatsapp': (await db.getAppSetting(whatsapp)) ?? '',
      'website': (await db.getAppSetting(website)) ?? '',
    };
  }

  static Future<void> saveContacts({
    required String phoneValue,
    required String addressValue,
    required String whatsappValue,
    required String websiteValue,
  }) async {
    final db = DatabaseHelper();
    await db.setAppSetting(phone, phoneValue.trim());
    await db.setAppSetting(address, addressValue.trim());
    await db.setAppSetting(whatsapp, whatsappValue.trim());
    await db.setAppSetting(website, websiteValue.trim());
  }

  /// Путь к локальному логотипу (файл в Documents), или null.
  static Future<String?> loadLogoPath() async {
    final path = await DatabaseHelper().getAppSetting(logoPathKey);
    if (path == null || path.trim().isEmpty) return null;
    if (!await File(path).exists()) return null;
    return path;
  }

  /// Копирует выбранный файл в Documents/studio_logo.ext и сохраняет путь.
  static Future<String?> saveLogoFromFile(String sourcePath) async {
    final src = File(sourcePath);
    if (!await src.exists()) return null;
    final docs = await getApplicationDocumentsDirectory();
    final ext = p.extension(sourcePath).toLowerCase();
    final safeExt = (ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.webp') ? ext : '.jpg';
    final dest = File(p.join(docs.path, 'studio_logo$safeExt'));
    if (await dest.exists()) {
      try {
        await dest.delete();
      } catch (_) {}
    }
    await src.copy(dest.path);
    await DatabaseHelper().setAppSetting(logoPathKey, dest.path);
    return dest.path;
  }

  static Future<void> clearLogo() async {
    final path = await DatabaseHelper().getAppSetting(logoPathKey);
    if (path != null && path.isNotEmpty) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await DatabaseHelper().setAppSetting(logoPathKey, '');
  }

  static Future<(int, int)> loadCalendarHours() async {
    final db = DatabaseHelper();
    final s = int.tryParse((await db.getAppSetting(calendarStartHour)) ?? '') ?? defaultStartHour;
    final e = int.tryParse((await db.getAppSetting(calendarEndHour)) ?? '') ?? defaultEndHour;
    final start = s.clamp(0, 23);
    final end = e.clamp(start, 23);
    return (start, end);
  }

  static Future<void> saveCalendarHours(int start, int end) async {
    final db = DatabaseHelper();
    final s = start.clamp(0, 23);
    final e = end.clamp(s, 23);
    await db.setAppSetting(calendarStartHour, '$s');
    await db.setAppSetting(calendarEndHour, '$e');
  }

  static Future<int?> loadDefaultBranchId() async {
    final v = await DatabaseHelper().getAppSetting(defaultBranchId);
    return int.tryParse(v ?? '');
  }

  static Future<void> saveDefaultBranchId(int? id) async {
    await DatabaseHelper().setAppSetting(defaultBranchId, id == null ? '' : '$id');
  }

  static Future<int?> loadDefaultCashRegisterId() async {
    final v = await DatabaseHelper().getAppSetting(defaultCashRegisterId);
    return int.tryParse(v ?? '');
  }

  static Future<void> saveDefaultCashRegisterId(int? id) async {
    await DatabaseHelper().setAppSetting(defaultCashRegisterId, id == null ? '' : '$id');
  }

  static Future<Map<String, String>> loadMessageTemplates() async {
    final db = DatabaseHelper();
    return {
      'booking': (await db.getAppSetting(tplBooking)) ?? '',
      'debt': (await db.getAppSetting(tplDebt)) ?? '',
      'ready': (await db.getAppSetting(tplReady)) ?? '',
    };
  }

  static Future<void> saveMessageTemplates({
    required String booking,
    required String debt,
    required String ready,
  }) async {
    final db = DatabaseHelper();
    await db.setAppSetting(tplBooking, booking.trim());
    await db.setAppSetting(tplDebt, debt.trim());
    await db.setAppSetting(tplReady, ready.trim());
  }

  /// Подстановка плейсхолдеров: {name} {order} {debt} {car}
  static String applyTemplate(
    String template, {
    required String name,
    required String order,
    String debt = '',
    String car = '',
  }) {
    return template
        .replaceAll('{name}', name)
        .replaceAll('{order}', order)
        .replaceAll('{debt}', debt)
        .replaceAll('{car}', car);
  }
}
