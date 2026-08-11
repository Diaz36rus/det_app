// Автоопределение элемента кузова по тексту описания дефекта.
// Пример: «капот, скол» / «крыло скол» / «стойка лобового» → вкладки Капот / Крыло / Стойка.

class DefectPartDef {
  final String key;
  final String label;
  final List<String> aliases;

  const DefectPartDef({
    required this.key,
    required this.label,
    required this.aliases,
  });
}

/// Канонические элементы (длинные алиасы важны — матчим от длинных к коротким).
const List<DefectPartDef> kDefectParts = [
  DefectPartDef(
    key: 'stoyka_lobovogo',
    label: 'Стойка лобового',
    aliases: [
      'стойка лобового',
      'стойки лобового',
      'стойке лобового',
      'стойку лобового',
      'а-стойка',
      'а стойка',
      'a-стойка',
    ],
  ),
  DefectPartDef(
    key: 'lobovoe',
    label: 'Лобовое',
    aliases: [
      'лобовое стекло',
      'лобового стекла',
      'лобовое',
      'лобового',
      'лобовуха',
    ],
  ),
  DefectPartDef(
    key: 'zadnee_steklo',
    label: 'Заднее стекло',
    aliases: ['заднее стекло', 'заднего стекла', 'заднее'],
  ),
  DefectPartDef(
    key: 'kapot',
    label: 'Капот',
    aliases: ['капот', 'капота', 'капоте', 'капотом', 'капоту'],
  ),
  DefectPartDef(
    key: 'krysha',
    label: 'Крыша',
    aliases: ['крыша', 'крыши', 'крыше', 'крышу', 'крышей'],
  ),
  DefectPartDef(
    key: 'bagazhnik',
    label: 'Багажник',
    aliases: [
      'багажник',
      'багажника',
      'багажнике',
      'крышка багажника',
      'дверь багажника',
    ],
  ),
  DefectPartDef(
    key: 'krylo',
    label: 'Крыло',
    aliases: [
      'крыло',
      'крыла',
      'крыле',
      'крылу',
      'крылом',
      'крылья',
      'крыльев',
      'переднее крыло',
      'заднее крыло',
    ],
  ),
  DefectPartDef(
    key: 'dver',
    label: 'Дверь',
    aliases: [
      'дверь',
      'двери',
      'дверью',
      'дверь пп',
      'дверь пл',
      'дверь зп',
      'дверь зл',
      'передняя дверь',
      'задняя дверь',
    ],
  ),
  DefectPartDef(
    key: 'bamper_pered',
    label: 'Бампер пер.',
    aliases: [
      'передний бампер',
      'переднего бампера',
      'бампер передний',
      'бампер пер',
    ],
  ),
  DefectPartDef(
    key: 'bamper_zad',
    label: 'Бампер зад.',
    aliases: [
      'задний бампер',
      'заднего бампера',
      'бампер задний',
      'бампер зад',
    ],
  ),
  DefectPartDef(
    key: 'bamper',
    label: 'Бампер',
    aliases: ['бампер', 'бампера', 'бампере', 'бампером'],
  ),
  DefectPartDef(
    key: 'porog',
    label: 'Порог',
    aliases: ['порог', 'порога', 'пороге', 'пороги', 'порогов'],
  ),
  DefectPartDef(
    key: 'stoyka',
    label: 'Стойка',
    aliases: ['стойка', 'стойки', 'стойке', 'стойку', 'стойкой', 'стойках'],
  ),
  DefectPartDef(
    key: 'zerkalo',
    label: 'Зеркало',
    aliases: ['зеркало', 'зеркала', 'зеркале', 'зеркал'],
  ),
  DefectPartDef(
    key: 'disk',
    label: 'Диск',
    aliases: ['диск', 'диска', 'диске', 'диски', 'дисков', 'колесный диск'],
  ),
  DefectPartDef(
    key: 'porog_plastik',
    label: 'Накладка порога',
    aliases: ['накладка порога', 'молдинг'],
  ),
  DefectPartDef(
    key: 'fary',
    label: 'Фары',
    aliases: ['фара', 'фары', 'фару', 'фаре', 'оптика'],
  ),
  DefectPartDef(
    key: 'fonari',
    label: 'Фонари',
    aliases: ['фонарь', 'фонари', 'фонаря', 'стоп-сигнал'],
  ),
  DefectPartDef(
    key: 'radiator',
    label: 'Решётка',
    aliases: ['решетка', 'решётка', 'радиаторная решетка'],
  ),
];

const kDefectPartOther = 'Прочее';

String _norm(String s) => s.toLowerCase().replaceAll('ё', 'е').trim();

/// Возвращает ярлык элемента или [kDefectPartOther], если не распознано.
String detectDefectPart(String description) {
  final norm = _norm(description);
  if (norm.isEmpty) return kDefectPartOther;

  String? bestLabel;
  var bestLen = 0;

  for (final part in kDefectParts) {
    for (final alias in part.aliases) {
      final a = _norm(alias);
      if (a.isEmpty || a.length < bestLen) continue;
      final re = RegExp(
        '(^|[^a-zа-я0-9])${RegExp.escape(a)}([^a-zа-я0-9]|\$)',
        caseSensitive: false,
      );
      if (re.hasMatch(norm) && a.length > bestLen) {
        bestLen = a.length;
        bestLabel = part.label;
      }
    }
  }
  return bestLabel ?? kDefectPartOther;
}

/// Группы для UI: сначала известные элементы (по числу), «Прочее» в конце.
List<MapEntry<String, List<T>>> groupDefectsByPart<T>(
  Iterable<T> items,
  String Function(T) descriptionOf,
) {
  final map = <String, List<T>>{};
  for (final item in items) {
    final part = detectDefectPart(descriptionOf(item));
    (map[part] ??= []).add(item);
  }

  final keys = map.keys.toList()
    ..sort((a, b) {
      if (a == kDefectPartOther) return 1;
      if (b == kDefectPartOther) return -1;
      final ca = map[a]!.length;
      final cb = map[b]!.length;
      if (ca != cb) return cb.compareTo(ca);
      return a.compareTo(b);
    });

  return [for (final k in keys) MapEntry(k, map[k]!)];
}
