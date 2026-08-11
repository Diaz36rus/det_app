import 'package:flutter/material.dart';

/// Раньше показывал диалог «конфликт слота». Параллельные заказы нормальны —
/// календарь рисует их рядом, предупреждение не нужно.
Future<bool> confirmNoScheduleConflict(
  BuildContext context, {
  required String startTime,
  required String endTime,
  int? excludeOrderId,
}) async {
  return true;
}
