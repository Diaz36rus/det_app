import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Категории склада детейлинг-студии (v1).
class InventoryCategories {
  InventoryCategories._();

  static const wash = 'Мойка';
  static const polishProtect = 'Полировка и защита';
  static const interior = 'Химчистка и салон';
  static const filmWrap = 'Плёнка оклейка';
  static const filmTint = 'Плёнка тонировка';
  static const toolsConsumables = 'Инструмент и расходники';
  static const textile = 'Текстиль';
  static const ppe = 'СИЗ';
  static const other = 'Прочее';

  static const all = <String>[
    wash,
    polishProtect,
    interior,
    filmWrap,
    filmTint,
    toolsConsumables,
    textile,
    ppe,
    other,
  ];

  static bool isFilm(String? category) =>
      category == filmWrap || category == filmTint;

  static IconData icon(String category) => switch (category) {
        wash => Icons.local_car_wash_outlined,
        polishProtect => Icons.auto_awesome_outlined,
        interior => Icons.airline_seat_recline_normal_outlined,
        filmWrap => Icons.layers_outlined,
        filmTint => Icons.opacity_outlined,
        toolsConsumables => Icons.handyman_outlined,
        textile => Icons.dry_cleaning_outlined,
        ppe => Icons.health_and_safety_outlined,
        other => Icons.category_outlined,
        _ => Icons.inventory_2_outlined,
      };

  /// Карточки категорий склада (assets/images/inv_*.jpg).
  static String? imageAsset(String category) => switch (category) {
        wash => 'assets/images/inv_wash.jpg',
        polishProtect => 'assets/images/inv_polish.jpg',
        interior => 'assets/images/inv_interior.jpg',
        filmWrap => 'assets/images/inv_wrap.jpg',
        filmTint => 'assets/images/inv_tint.jpg',
        toolsConsumables => 'assets/images/inv_tools.jpg',
        textile => 'assets/images/inv_textile.jpg',
        ppe => 'assets/images/inv_ppe.jpg',
        other => 'assets/images/inv_other.jpg',
        _ => null,
      };

  /// TODO(later): учёт полировальных кругов/падов — не в v1.
}

/// Справочник брендов расходников (остаток всё равно по типу позиции).
/// Для плёнок бренд не используем — там рулоны / м.п.
class InventoryBrands {
  InventoryBrands._();

  static String normalize(String? raw) => (raw ?? '').trim();

  /// Стартовый набор популярных брендов детейлинга.
  static const popular = <String>[
    'Koch Chemie',
    'CarPro',
    'Gyeon',
    'Soft99',
    'Sonax',
    'Meguiar\'s',
    'Chemical Guys',
    'Auto Finesse',
    'Griot\'s Garage',
    '3D',
    'Adams',
    'Turtle Wax',
    'Krytex',
    'Hendlex',
    'Liquid Elements',
  ];
}

/// Единицы учёта склада (остаток на полке, не «рабочий раствор»).
///
/// Практика детейлинга (Koch/CarPro и др.):
/// — жидкая химия-концентрат: литры или целая тара (кан./фл.);
/// — полироли/пасты/керамика: флакон или набор;
/// — расходники/текстиль/СИЗ: шт / уп / рул.;
/// — плёнка: м.п. или рул. (номера рулонов отдельно).
class InventoryUnits {
  InventoryUnits._();

  static const liter = 'л';
  static const canister = 'кан.';
  static const bottle = 'фл.';
  static const piece = 'шт';
  static const pack = 'уп';
  static const roll = 'рул.';
  static const kg = 'кг';
  static const kit = 'наб.';
  static const meters = 'м.п.';

  static const consumableChoices = <String>[
    liter,
    canister,
    bottle,
    piece,
    pack,
    roll,
    kg,
    kit,
  ];

  static const filmChoices = <String>[meters, roll];

  static List<String> choicesForCategory(String? category) =>
      InventoryCategories.isFilm(category) ? filmChoices : consumableChoices;

  static String menuLabel(String unit) => switch (unit) {
        liter => 'Литры (л) — объём концентрата',
        canister => 'Канистра (кан.) — целая тара',
        bottle => 'Флакон (фл.) — бутылка/банка',
        piece => 'Штуки (шт)',
        pack => 'Упаковка (уп)',
        roll => 'Рулон (рул.)',
        kg => 'Килограммы (кг)',
        kit => 'Набор (наб.)',
        meters => 'Метры погонные (м.п.)',
        _ => unit,
      };

  static String helperFor(String? unit, {String? category}) {
    if (InventoryCategories.isFilm(category)) {
      return 'В цехе расход всегда в м.п.';
    }
    return switch (normalize(unit, category: category)) {
      liter => 'Считаем литры концентрата (канистры 1–25 л)',
      canister => 'Считаем целые канистры, без разлива в литры',
      bottle => 'Считаем флаконы/банки как штуки тары',
      piece => 'Отдельные предметы',
      pack => 'Коробки/пачки (перчатки, салфетки, лезвия)',
      roll => 'Рулоны скотча / укрывной плёнки',
      kg => 'Пасты и материалы на вес',
      kit => 'Комплекты (керамика и т.п.)',
      _ => 'Единица остатка на складе',
    };
  }

  static String normalize(String? unit, {String? category}) {
    if (InventoryCategories.isFilm(category)) {
      return FilmUnits.normalize(unit);
    }
    final u = (unit ?? '').trim().toLowerCase().replaceAll(' ', '');
    if (u.isEmpty) return piece;
    if (u == 'л' || u == 'л.' || u == 'литр' || u == 'литры' || u == 'l' || u == 'liter' || u == 'liters') {
      return liter;
    }
    if (u.startsWith('кан') || u == 'канистра' || u == 'канистры') return canister;
    if (u.startsWith('фл') || u == 'бутылка' || u == 'банка' || u == 'bottle') return bottle;
    if (u.startsWith('уп') || u == 'упаковка' || u == 'пачка' || u == 'коробка' || u == 'pack') {
      return pack;
    }
    if (u == 'рул' || u == 'рул.' || u == 'рулон' || u == 'рулоны' || u == 'roll' || u == 'rolls') {
      return roll;
    }
    if (u == 'кг' || u == 'kg' || u == 'килограмм') return kg;
    if (u.startsWith('наб') || u == 'kit' || u == 'комплект') return kit;
    if (u == 'м' || u == 'м.' || u == 'мп' || u == 'м.п' || u == 'м.п.' || u == 'meters') {
      return meters;
    }
    if (u == 'шт' || u == 'шт.' || u == 'штук' || u == 'штука' || u == 'pcs') return piece;
    final raw = (unit ?? '').trim();
    return raw.isEmpty ? piece : raw;
  }

  /// Логичный дефолт по категории и названию.
  static String defaultFor({required String category, String? name}) {
    if (InventoryCategories.isFilm(category)) return meters;
    final n = (name ?? '').toLowerCase();
    if (n.contains('перчат') ||
        n.contains('салфет') ||
        n.contains('лезв') ||
        n.contains('пакет')) {
      return pack;
    }
    if (n.contains('скотч') || n.contains('лент') || n.contains('укрывн')) return roll;
    if (n.contains('керамик') || n.contains('набор') || n.contains('комплект')) return kit;
    if (n.contains('полирол') ||
        n.contains('паст') ||
        n.contains('кварц') ||
        n.contains('антидожд') ||
        n.contains('праймер') ||
        n.contains('ароматиз') ||
        n.contains('антибактер')) {
      return bottle;
    }
    if (category == InventoryCategories.wash ||
        category == InventoryCategories.interior ||
        n.contains('шампун') ||
        n.contains('очистител') ||
        n.contains('раствор') ||
        n.contains('ipa') ||
        n.contains('обезжир') ||
        n.contains('вода') ||
        n.contains('чернител') ||
        n.contains('воск')) {
      return liter;
    }
    return piece;
  }
}

/// Совместимость: единицы плёнки.
class FilmUnits {
  FilmUnits._();

  static const meters = InventoryUnits.meters;
  static const rolls = InventoryUnits.roll;
  static const choices = InventoryUnits.filmChoices;

  static String normalize(String? unit) {
    final u = (unit ?? '').trim().toLowerCase().replaceAll(' ', '');
    if (u == 'рул' ||
        u == 'рул.' ||
        u == 'рулон' ||
        u == 'рулоны' ||
        u == 'roll' ||
        u == 'rolls') {
      return rolls;
    }
    return meters;
  }

  static bool isRolls(String? unit) => normalize(unit) == rolls;

  static String label(String? unit) => normalize(unit);
}

/// Стандартная позиция для первичного наполнения склада.
class InventorySeedItem {
  final String name;
  final String category;
  final String unit;
  final double minQty;
  final double metersPerRoll;

  const InventorySeedItem({
    required this.name,
    required this.category,
    this.unit = InventoryUnits.piece,
    this.minQty = 0,
    this.metersPerRoll = 0,
  });
}

/// Популярные расходники детейлинг-студии (добавляются один раз, дальше правятся вручную).
class InventorySeedCatalog {
  InventorySeedCatalog._();

  static const settingKey = 'inventory_standard_seed_v1';
  static const unitsFixKey = 'inventory_units_fix_v1';

  static const items = <InventorySeedItem>[
    // Мойка — жидкие концентраты: учёт в литрах.
    InventorySeedItem(name: 'Шампунь бесконтактный', category: InventoryCategories.wash, unit: InventoryUnits.liter, minQty: 5),
    InventorySeedItem(name: 'Шампунь активный (ручка)', category: InventoryCategories.wash, unit: InventoryUnits.liter, minQty: 3),
    InventorySeedItem(name: 'Очиститель дисков', category: InventoryCategories.wash, unit: InventoryUnits.liter, minQty: 2),
    InventorySeedItem(name: 'Очиститель битума', category: InventoryCategories.wash, unit: InventoryUnits.liter, minQty: 1),
    InventorySeedItem(name: 'Очиститель насекомых', category: InventoryCategories.wash, unit: InventoryUnits.liter, minQty: 1),
    InventorySeedItem(name: 'Очиститель стёкол', category: InventoryCategories.wash, unit: InventoryUnits.liter, minQty: 2),
    InventorySeedItem(name: 'Воск быстрый (quick wax)', category: InventoryCategories.wash, unit: InventoryUnits.liter, minQty: 1),
    InventorySeedItem(name: 'Чернитель резины', category: InventoryCategories.wash, unit: InventoryUnits.liter, minQty: 1),

    // Полировка — флаконы/наборы, не «литры с полки».
    InventorySeedItem(name: 'Полироль крупноабразивная', category: InventoryCategories.polishProtect, unit: InventoryUnits.bottle, minQty: 1),
    InventorySeedItem(name: 'Полироль среднеабразивная', category: InventoryCategories.polishProtect, unit: InventoryUnits.bottle, minQty: 1),
    InventorySeedItem(name: 'Полироль финишная', category: InventoryCategories.polishProtect, unit: InventoryUnits.bottle, minQty: 1),
    InventorySeedItem(name: 'Антиголограммная паста', category: InventoryCategories.polishProtect, unit: InventoryUnits.bottle, minQty: 1),
    InventorySeedItem(name: 'Обезжириватель / IPA', category: InventoryCategories.polishProtect, unit: InventoryUnits.liter, minQty: 2),
    InventorySeedItem(name: 'Кварцевая защита SiO2', category: InventoryCategories.polishProtect, unit: InventoryUnits.bottle, minQty: 1),
    InventorySeedItem(name: 'Керамическое покрытие', category: InventoryCategories.polishProtect, unit: InventoryUnits.kit, minQty: 1),
    InventorySeedItem(name: 'Антидождь для стёкол', category: InventoryCategories.polishProtect, unit: InventoryUnits.bottle, minQty: 1),

    // Химчистка
    InventorySeedItem(name: 'Очиститель ткани / ковров', category: InventoryCategories.interior, unit: InventoryUnits.liter, minQty: 2),
    InventorySeedItem(name: 'Очиститель кожи', category: InventoryCategories.interior, unit: InventoryUnits.liter, minQty: 1),
    InventorySeedItem(name: 'Кондиционер кожи', category: InventoryCategories.interior, unit: InventoryUnits.liter, minQty: 1),
    InventorySeedItem(name: 'Очиститель пластика', category: InventoryCategories.interior, unit: InventoryUnits.liter, minQty: 1),
    InventorySeedItem(name: 'Пятновыводитель', category: InventoryCategories.interior, unit: InventoryUnits.liter, minQty: 1),
    InventorySeedItem(name: 'Очиститель потолка', category: InventoryCategories.interior, unit: InventoryUnits.liter, minQty: 1),
    InventorySeedItem(name: 'Антибактериальная обработка', category: InventoryCategories.interior, unit: InventoryUnits.bottle, minQty: 2),
    InventorySeedItem(name: 'Ароматизатор салона', category: InventoryCategories.interior, unit: InventoryUnits.piece, minQty: 5),

    // Плёнка оклейка
    InventorySeedItem(
      name: 'Плёнка виниловая глянец',
      category: InventoryCategories.filmWrap,
      unit: InventoryUnits.meters,
      metersPerRoll: 18,
      minQty: 5,
    ),
    InventorySeedItem(
      name: 'Плёнка виниловая мат',
      category: InventoryCategories.filmWrap,
      unit: InventoryUnits.meters,
      metersPerRoll: 18,
      minQty: 5,
    ),
    InventorySeedItem(
      name: 'Плёнка PPF защитная',
      category: InventoryCategories.filmWrap,
      unit: InventoryUnits.meters,
      metersPerRoll: 15,
      minQty: 5,
    ),

    // Плёнка тонировка
    InventorySeedItem(
      name: 'Тонировка 5%',
      category: InventoryCategories.filmTint,
      unit: InventoryUnits.meters,
      metersPerRoll: 30,
      minQty: 5,
    ),
    InventorySeedItem(
      name: 'Тонировка 15%',
      category: InventoryCategories.filmTint,
      unit: InventoryUnits.meters,
      metersPerRoll: 30,
      minQty: 5,
    ),
    InventorySeedItem(
      name: 'Тонировка 20%',
      category: InventoryCategories.filmTint,
      unit: InventoryUnits.meters,
      metersPerRoll: 30,
      minQty: 5,
    ),
    InventorySeedItem(
      name: 'Тонировка 35%',
      category: InventoryCategories.filmTint,
      unit: InventoryUnits.meters,
      metersPerRoll: 30,
      minQty: 5,
    ),
    InventorySeedItem(
      name: 'Атермальная плёнка',
      category: InventoryCategories.filmTint,
      unit: InventoryUnits.meters,
      metersPerRoll: 30,
      minQty: 3,
    ),

    // Инструмент и расходники
    InventorySeedItem(name: 'Малярный скотч', category: InventoryCategories.toolsConsumables, unit: InventoryUnits.roll, minQty: 5),
    InventorySeedItem(name: 'Укрывная плёнка', category: InventoryCategories.toolsConsumables, unit: InventoryUnits.roll, minQty: 2),
    InventorySeedItem(name: 'Салфетки безворсовые', category: InventoryCategories.toolsConsumables, unit: InventoryUnits.pack, minQty: 3),
    InventorySeedItem(name: 'Аппликатор поролоновый', category: InventoryCategories.toolsConsumables, unit: InventoryUnits.piece, minQty: 10),
    InventorySeedItem(name: 'Триггер / распылитель', category: InventoryCategories.toolsConsumables, unit: InventoryUnits.piece, minQty: 5),
    InventorySeedItem(name: 'Кисть детейлинговая', category: InventoryCategories.toolsConsumables, unit: InventoryUnits.piece, minQty: 5),
    InventorySeedItem(name: 'Клейкая лента двусторонняя', category: InventoryCategories.toolsConsumables, unit: InventoryUnits.roll, minQty: 2),
    InventorySeedItem(name: 'Праймер для плёнки', category: InventoryCategories.toolsConsumables, unit: InventoryUnits.bottle, minQty: 2),
    InventorySeedItem(name: 'Ракель войлочный', category: InventoryCategories.toolsConsumables, unit: InventoryUnits.piece, minQty: 3),
    InventorySeedItem(name: 'Лезвия для плёнки', category: InventoryCategories.toolsConsumables, unit: InventoryUnits.pack, minQty: 2),
    InventorySeedItem(name: 'Раствор для тонировки', category: InventoryCategories.toolsConsumables, unit: InventoryUnits.liter, minQty: 2),
    InventorySeedItem(name: 'Выгонка / ракель тонировка', category: InventoryCategories.toolsConsumables, unit: InventoryUnits.piece, minQty: 2),

    // Текстиль
    InventorySeedItem(name: 'Микрофибра универсальная', category: InventoryCategories.textile, unit: InventoryUnits.piece, minQty: 20),
    InventorySeedItem(name: 'Микрофибра для стекла', category: InventoryCategories.textile, unit: InventoryUnits.piece, minQty: 10),
    InventorySeedItem(name: 'Микрофибра вафельная', category: InventoryCategories.textile, unit: InventoryUnits.piece, minQty: 10),
    InventorySeedItem(name: 'Полотенце сушки XL', category: InventoryCategories.textile, unit: InventoryUnits.piece, minQty: 5),
    InventorySeedItem(name: 'Аппликатор микрофибра', category: InventoryCategories.textile, unit: InventoryUnits.piece, minQty: 10),

    // СИЗ
    InventorySeedItem(name: 'Перчатки нитриловые M', category: InventoryCategories.ppe, unit: InventoryUnits.pack, minQty: 2),
    InventorySeedItem(name: 'Перчатки нитриловые L', category: InventoryCategories.ppe, unit: InventoryUnits.pack, minQty: 2),
    InventorySeedItem(name: 'Респиратор', category: InventoryCategories.ppe, unit: InventoryUnits.piece, minQty: 5),
    InventorySeedItem(name: 'Очки защитные', category: InventoryCategories.ppe, unit: InventoryUnits.piece, minQty: 3),
    InventorySeedItem(name: 'Фартук / комбинезон', category: InventoryCategories.ppe, unit: InventoryUnits.piece, minQty: 3),

    // Прочее
    InventorySeedItem(name: 'Дистиллированная вода', category: InventoryCategories.other, unit: InventoryUnits.liter, minQty: 10),
    InventorySeedItem(name: 'Удалитель силикона', category: InventoryCategories.other, unit: InventoryUnits.liter, minQty: 1),
    InventorySeedItem(name: 'Обезжириватель универсальный', category: InventoryCategories.other, unit: InventoryUnits.liter, minQty: 2),
    InventorySeedItem(name: 'Пакеты для ковриков', category: InventoryCategories.other, unit: InventoryUnits.pack, minQty: 1),
  ];
}

/// Причины движений склада.
class InventoryMoveReasons {
  InventoryMoveReasons._();

  static const purchase = 'purchase';
  static const orderDeduct = 'order_deduct';
  static const manual = 'manual';
  static const inventoryCount = 'inventory_count';
  static const cashPurchase = 'cash_purchase';
  static const recipeDeduct = 'recipe_deduct';
  static const recipeRestore = 'recipe_restore';
  static const filmDeduct = 'film_deduct';
  static const filmRestore = 'film_restore';

  static String label(String reason) {
    return switch (reason) {
      purchase => 'Приход',
      cashPurchase => 'Закупка (касса)',
      orderDeduct => 'Списание по заказу',
      recipeDeduct => 'Рецепт (выполнено)',
      recipeRestore => 'Возврат рецепта',
      filmDeduct => 'Плёнка (цех)',
      filmRestore => 'Плёнка (отмена)',
      inventoryCount => 'Инвентаризация',
      manual => 'Ручная правка',
      _ => reason,
    };
  }

  /// Журнал «Движения» на складе — только логистика, не расход цеха/рецептов.
  static const logistics = <String>{
    purchase,
    cashPurchase,
    manual,
    inventoryCount,
  };

  static bool isLogistics(String? reason) => logistics.contains(reason);
}

/// Номер рулона и любые складские коды — всегда UPPERCASE.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = newValue.text.toUpperCase();
    if (upper == newValue.text) return newValue;
    return TextEditingValue(
      text: upper,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

String normalizeRollNumber(String raw) => raw.trim().toUpperCase();
