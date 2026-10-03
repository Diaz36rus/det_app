/// Источник заказа / лида (ручной справочник, без inbox).
class OrderLeadSources {
  OrderLeadSources._();

  static const String unset = '';
  static const String wordOfMouth = 'Сарафан';
  static const String avito = 'Avito';
  static const String telegram = 'Telegram';
  static const String site = 'Сайт';
  static const String repeat = 'Повтор';
  static const String other = 'Прочее';

  static const List<String> all = [
    wordOfMouth,
    avito,
    telegram,
    site,
    repeat,
    other,
  ];

  static String display(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return 'Не указан';
    return v;
  }

  static String normalize(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return unset;
    for (final s in all) {
      if (s.toLowerCase() == v.toLowerCase()) return s;
    }
    return other;
  }
}
