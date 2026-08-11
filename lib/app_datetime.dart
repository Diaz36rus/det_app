import 'package:intl/intl.dart';

/// Единое форматирование дат/времени для UI.
///
/// В БД храним ISO-подобные строки (`2026-08-11T20:15` / с пробелом).
/// На экране — всегда человекочитаемый вид через эти хелперы.
class AppDateTime {
  AppDateTime._();

  static final _dtFull = DateFormat('dd.MM.yyyy HH:mm');
  static final _dtShort = DateFormat('dd.MM HH:mm');
  static final _dateOnly = DateFormat('dd.MM.yyyy');
  static final _timeOnly = DateFormat('HH:mm');
  static final _dbDay = DateFormat('yyyy-MM-dd');

  /// Разбор строк из БД / ISO.
  static DateTime? tryParse(Object? raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    // "09:00" — только время, без даты
    if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(s)) return null;
    var n = s.replaceFirst(' ', 'T').split('.').first;
    // "2026-08-11 20:15:00" → already handled by replace
    return DateTime.tryParse(n) ?? DateTime.tryParse(s);
  }

  /// `11.08.2026 20:15` — основной формат для списков и деталей.
  static String format(Object? raw, {String fallback = ''}) {
    final dt = tryParse(raw);
    if (dt == null) {
      final s = raw?.toString().trim() ?? '';
      if (s.isEmpty) return fallback;
      return s.replaceFirst('T', ' ');
    }
    return _dtFull.format(dt);
  }

  /// `11.08 20:15` — компактный (журнал, лента событий).
  static String formatShort(Object? raw, {String fallback = ''}) {
    final dt = tryParse(raw);
    if (dt == null) {
      final s = raw?.toString().trim() ?? '';
      if (s.isEmpty) return fallback;
      return s.replaceFirst('T', ' ');
    }
    return _dtShort.format(dt);
  }

  /// `11.08.2026`
  static String formatDate(Object? raw, {String fallback = ''}) {
    final dt = tryParse(raw);
    if (dt != null) return _dateOnly.format(dt);
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty) return fallback;
    if (s.length >= 10) {
      final day = tryParse(s.substring(0, 10));
      if (day != null) return _dateOnly.format(day);
    }
    return s;
  }

  /// `20:15`
  static String formatTime(Object? raw, {String fallback = ''}) {
    final dt = tryParse(raw);
    if (dt == null) {
      final s = raw?.toString().trim() ?? '';
      if (RegExp(r'^\d{1,2}:\d{2}').hasMatch(s)) return s.substring(0, s.length >= 5 ? 5 : s.length);
      return s.isEmpty ? fallback : s;
    }
    return _timeOnly.format(dt);
  }

  /// Для SQL-периодов: `yyyy-MM-dd`.
  static String toDbDate(DateTime dt) => _dbDay.format(dt);

  /// Текущий момент в формате записи БД (`yyyy-MM-ddTHH:mm`).
  static String nowDb() => DateTime.now().toIso8601String().substring(0, 16);
}
