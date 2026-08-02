/// Справочник категорий, методов оплаты и шаблонов операций кассы.
class CashMethods {
  static const cash = 'Наличные';
  static const card = 'Карта';
  static const transfer = 'Перевод';
  static const invoice = 'По счету';

  static const all = [cash, card, transfer, invoice];
}

class CashCategories {
  static const expense = [
    'Материалы / химия',
    'Расходники',
    'Плёнка / тонировка',
    'Инструмент',
    'Ремонт оборудования',
    'Аренда',
    'Коммуналка',
    'Интернет / связь',
    'Охрана',
    'Зарплата',
    'Аванс',
    'Подряд / выезд',
    'Выезд',
    'Доставка / такси',
    'Питание / кофе',
    'Инкассация',
    'Прочее',
  ];

  static const income = [
    'Предоплата',
    'Доплата',
    'Продажа материалов',
    'Продажа аксессуаров',
    'Продажа плёнки',
    'Сертификаты',
    'Возврат подотчётных',
    'Прочий приход',
    'Прочее',
  ];

  static List<String> forType(String type) => type == 'Приход' ? income : expense;
}

class CashTemplate {
  final String key;
  final String label;
  final String type; // Приход | Расход
  final String category;
  final String method;
  final String defaultDescription;
  final bool needsMaster;
  final bool needsInventory;
  final bool isCollection; // инкассация

  const CashTemplate({
    required this.key,
    required this.label,
    required this.type,
    required this.category,
    required this.method,
    required this.defaultDescription,
    this.needsMaster = false,
    this.needsInventory = false,
    this.isCollection = false,
  });
}

/// Порядок: частые расходы → продажи/приходы → прочие.
const List<CashTemplate> kCashTemplates = [
  // --- Расход ---
  CashTemplate(
    key: 'chem',
    label: 'Химия',
    type: 'Расход',
    category: 'Материалы / химия',
    method: CashMethods.card,
    defaultDescription: 'Закупка химии / автокосметики',
    needsInventory: true,
  ),
  CashTemplate(
    key: 'film',
    label: 'Плёнка',
    type: 'Расход',
    category: 'Плёнка / тонировка',
    method: CashMethods.transfer,
    defaultDescription: 'Закупка плёнки / тонировки',
    needsInventory: true,
  ),
  CashTemplate(
    key: 'salary',
    label: 'Зарплата',
    type: 'Расход',
    category: 'Зарплата',
    method: CashMethods.cash,
    defaultDescription: 'Выплата зарплаты',
    needsMaster: true,
  ),
  CashTemplate(
    key: 'advance',
    label: 'Аванс',
    type: 'Расход',
    category: 'Аванс',
    method: CashMethods.cash,
    defaultDescription: 'Аванс сотруднику',
    needsMaster: true,
  ),
  CashTemplate(
    key: 'rent',
    label: 'Аренда',
    type: 'Расход',
    category: 'Аренда',
    method: CashMethods.transfer,
    defaultDescription: 'Аренда помещения',
  ),
  CashTemplate(
    key: 'equip_repair',
    label: 'Ремонт оборуд.',
    type: 'Расход',
    category: 'Ремонт оборудования',
    method: CashMethods.card,
    defaultDescription: 'Ремонт оборудования',
  ),
  CashTemplate(
    key: 'field',
    label: 'Выезд',
    type: 'Расход',
    category: 'Выезд',
    method: CashMethods.cash,
    defaultDescription: 'Выездной сервис',
  ),
  CashTemplate(
    key: 'delivery',
    label: 'Доставка',
    type: 'Расход',
    category: 'Доставка / такси',
    method: CashMethods.cash,
    defaultDescription: 'Такси / доставка материалов',
  ),
  CashTemplate(
    key: 'internet',
    label: 'Интернет',
    type: 'Расход',
    category: 'Интернет / связь',
    method: CashMethods.transfer,
    defaultDescription: 'Интернет / телефония',
  ),
  CashTemplate(
    key: 'security',
    label: 'Охрана',
    type: 'Расход',
    category: 'Охрана',
    method: CashMethods.transfer,
    defaultDescription: 'Охрана / сигнализация',
  ),
  CashTemplate(
    key: 'staff_food',
    label: 'Кофе / еда',
    type: 'Расход',
    category: 'Питание / кофе',
    method: CashMethods.cash,
    defaultDescription: 'Питание / вода / кофе для зала',
  ),
  CashTemplate(
    key: 'collect',
    label: 'Инкассация',
    type: 'Расход',
    category: 'Инкассация',
    method: CashMethods.cash,
    defaultDescription: 'Инкассация в банк',
    isCollection: true,
  ),
  CashTemplate(
    key: 'other_out',
    label: 'Прочий −',
    type: 'Расход',
    category: 'Прочее',
    method: CashMethods.cash,
    defaultDescription: 'Прочий расход',
  ),

  // --- Приход ---
  CashTemplate(
    key: 'mat_sale',
    label: 'Продажа мат.',
    type: 'Приход',
    category: 'Продажа материалов',
    method: CashMethods.cash,
    defaultDescription: 'Продажа материалов / химии',
  ),
  CashTemplate(
    key: 'accessories',
    label: 'Аксессуары',
    type: 'Приход',
    category: 'Продажа аксессуаров',
    method: CashMethods.cash,
    defaultDescription: 'Продажа аксессуаров',
  ),
  CashTemplate(
    key: 'film_retail',
    label: 'Плёнка розн.',
    type: 'Приход',
    category: 'Продажа плёнки',
    method: CashMethods.cash,
    defaultDescription: 'Продажа плёнки / тонировки в розницу',
  ),
  CashTemplate(
    key: 'certificate',
    label: 'Сертификат',
    type: 'Приход',
    category: 'Сертификаты',
    method: CashMethods.cash,
    defaultDescription: 'Продажа сертификата / подарочной карты',
  ),
  CashTemplate(
    key: 'imprest',
    label: 'Подотчёт',
    type: 'Приход',
    category: 'Возврат подотчётных',
    method: CashMethods.cash,
    defaultDescription: 'Возврат подотчётных от сотрудника',
  ),
  CashTemplate(
    key: 'other_in',
    label: 'Прочий +',
    type: 'Приход',
    category: 'Прочий приход',
    method: CashMethods.cash,
    defaultDescription: 'Прочий приход',
  ),
];

CashTemplate? cashTemplateByKey(String? key) {
  if (key == null || key.isEmpty) return null;
  for (final t in kCashTemplates) {
    if (t.key == key) return t;
  }
  return null;
}
