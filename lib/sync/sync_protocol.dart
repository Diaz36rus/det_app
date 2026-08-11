import 'package:sqflite/sqflite.dart';

/// Кодирование ConflictAlgorithm для JSON.
String? conflictToName(ConflictAlgorithm? c) {
  if (c == null) return null;
  return c.name;
}

ConflictAlgorithm? conflictFromName(String? name) {
  if (name == null || name.isEmpty) return null;
  for (final v in ConflictAlgorithm.values) {
    if (v.name == name) return v;
  }
  return null;
}

/// Нормализация значений для JSON (Uint8List → base64 не нужен — в CRM нет blob).
Object? encodeSqlValue(Object? v) {
  if (v == null) return null;
  if (v is num || v is String || v is bool) return v;
  return v.toString();
}

List<Object?>? encodeArgs(List<Object?>? args) =>
    args?.map(encodeSqlValue).toList();

Map<String, Object?> encodeRow(Map<String, Object?> row) {
  return row.map((k, v) => MapEntry(k, encodeSqlValue(v)));
}
