/// Статус при создании заказа: будущее начало или дата — предварительная запись.
String resolveInitialOrderStatus(String? startTime, {String? dueDate}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  DateTime? parseFlexible(String? raw) {
    if (raw == null) return null;
    final n = raw.replaceFirst('T', ' ').split('.').first.trim();
    if (n.isEmpty) return null;
    try {
      if (n.length == 10) {
        return DateTime.parse(n); // yyyy-MM-dd
      }
      final iso = n.contains(' ') ? n.replaceFirst(' ', 'T') : n;
      return DateTime.parse(iso);
    } catch (_) {
      return null;
    }
  }

  final start = parseFlexible(startTime);
  if (start != null && start.isAfter(now)) {
    return "Предварительная запись";
  }

  final due = parseFlexible(dueDate);
  if (due != null) {
    final dueDay = DateTime(due.year, due.month, due.day);
    if (dueDay.isAfter(today)) {
      return "Предварительная запись";
    }
  }

  if ((startTime == null || startTime.trim().isEmpty) &&
      (dueDate == null || dueDate.trim().isEmpty)) {
    return "Предварительная запись";
  }
  return "Принят в работу";
}
