import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

// --- НАЧАЛО БЛОКА: КОНСТАНТЫ ---
List<String> STATUSES = [
  "Предварительная запись", "Принят в работу", "Мойка", "Химчистка", "Полировка",
  "Оклейка", "Интерьер", "Оборудование", "Подготовка к выдаче", "Выдан"
];

List<String> WORKSHOPS = ["Мойка", "Химчистка", "Полировка", "Оклейка", "Интерьер", "Оборудование"];

Map<String, List<String>> WORKSHOP_STATUSES = {
  "Мойка": ["Мойка"],
  "Химчистка": ["Химчистка"],
  "Полировка": ["Полировка"],
  "Оклейка": ["Оклейка"],
  "Интерьер": ["Интерьер"],
  "Оборудование": ["Оборудование"]
};

/// Роли мастеров, которые могут работать в цехе (имя роли = цех + смежные + Универсал).
Map<String, List<String>> WORKSHOP_ROLES = {
  "Мойка": ["Мойка", "Универсал"],
  "Химчистка": ["Химчистка", "Кузовные работы", "Универсал"],
  "Полировка": ["Полировка", "Кузовные работы", "Универсал"],
  "Оклейка": ["Оклейка", "Кузовные работы", "Универсал"],
  "Интерьер": ["Интерьер", "Тюнинг/Интерьер", "Универсал"],
  "Оборудование": ["Оборудование", "Кузовные работы", "Универсал"],
};

bool masterRoleFitsWorkshop(String? role, String workshop) {
  final r = (role ?? "").trim();
  if (r.isEmpty) return false;
  if (r == workshop) return true;
  final allowed = WORKSHOP_ROLES[workshop];
  if (allowed != null && allowed.contains(r)) return true;
  return false;
}

/// Автопривязка услуги к цеху по категории прайса / названию.
String? workshopForService({String? category, String? name}) {
  final blob = "${category ?? ''} ${name ?? ''}".toLowerCase();
  if (blob.trim().isEmpty) return null;

  // Точные совпадения с цехами (сначала более длинные имена)
  final ordered = [...WORKSHOPS]..sort((a, b) => b.length.compareTo(a.length));
  for (final w in ordered) {
    if (blob.contains(w.toLowerCase())) return w;
  }

  if (blob.contains('химчист')) return 'Химчистка';
  if (blob.contains('полир') || blob.contains('керамик') || blob.contains('силант') ||
      blob.contains('антидожд') || blob.contains('krytex')) {
    return 'Полировка';
  }
  if (blob.contains('оклей') || blob.contains('пленк') || blob.contains('тонир')) return 'Оклейка';
  if (blob.contains('интерьер') || blob.contains('салон') || blob.contains('уборк')) return 'Интерьер';
  if (blob.contains('оборуд') || blob.contains('двигател')) return 'Оборудование';
  if (blob.contains('мойк') || blob.contains('багаж')) return 'Мойка';
  return null;
}

/// Шапка пакета оклейки в заказе (одна коммерческая строка).
bool isWrapPackageHeader(String? name) => (name ?? '').trim() == 'Оклейка';

/// Позиция состава пакета оклейки (не тонировка, не шапка).
bool isWrapPackageLine({String? category, String? name}) {
  final n = (name ?? '').trim();
  if (n.isEmpty || isWrapPackageHeader(n)) return false;
  if (n.startsWith('Тонировка')) return false;
  if (n.startsWith('Оклейка ·')) return true;
  if ((category ?? '').trim() == 'Оклейка (Пленка)') return true;
  // Устаревшие имена до каталога «Оклейка · …»
  if (n == 'Оклейка капота' || n == 'Оклейка крыши' || n == 'Полная оклейка кузова') {
    return true;
  }
  return false;
}
// --- КОНЕЦ БЛОКА ---

/// Старые категории с emoji → без emoji (миграция + seed).
const Map<String, String> CATEGORY_RENAMES = {
  "🧽 Мойка": "Мойка",
  "🧼 Химчистка": "Химчистка",
  "✨ Полировка": "Полировка",
  "🛡️ Керамика и Силант": "Керамика и Силант",
  "🌧️ Антидождь": "Антидождь",
  "🧹 Уборка салона": "Уборка салона",
  "🎨 Оклейка (Пленка)": "Оклейка (Пленка)",
  "🪟 Тонировка": "Тонировка",
};

// --- НАЧАЛО БЛОКА: ПРАЙС-ЛИСТ ---
List<Map<String, dynamic>> SERVICES_TREE = [
  {"cat": "Мойка", "name": "Экспресс-мойка", "p1": 800, "p2": 1000, "p3": 1200, "p4": 1400, "fp": 0},
  {"cat": "Мойка", "name": "Мойка кузова", "p1": 1400, "p2": 1800, "p3": 2200, "p4": 2600, "fp": 0},
  {"cat": "Мойка", "name": "Комплексная мойка", "p1": 2500, "p2": 3000, "p3": 3500, "p4": 4000, "fp": 0},
  {"cat": "Мойка", "name": "Уборка багажника", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 200},
  {"cat": "Химчистка", "name": "Химчистка салона", "p1": 20000, "p2": 23000, "p3": 26000, "p4": 29000, "fp": 0},
  {"cat": "Химчистка", "name": "Химчистка 1го сидения (Ткань)", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 2500},
  {"cat": "Химчистка", "name": "Химчистка 1го сидения (Кожа)", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 2000},
  {"cat": "Химчистка", "name": "Химчистка локально", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 1000},
  {"cat": "Химчистка", "name": "Химчистка двигателя", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 6000},
  {"cat": "Химчистка", "name": "Химчистка дисков", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 6000},
  {"cat": "Химчистка", "name": "Детейлинг уборка салона", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 10000},
  {"cat": "Полировка", "name": "Восстановительная полировка", "p1": 30000, "p2": 35000, "p3": 40000, "p4": 45000, "fp": 0},
  {"cat": "Полировка", "name": "Легкая полировка", "p1": 10000, "p2": 12000, "p3": 14000, "p4": 16000, "fp": 0},
  {"cat": "Керамика и Силант", "name": "Керамика на кузов (1 слой)", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 10000},
  {"cat": "Керамика и Силант", "name": "Керамика на кузов (2 слоя)", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 15000},
  {"cat": "Керамика и Силант", "name": "Быстрая сухая керамика", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 5000},
  {"cat": "Керамика и Силант", "name": "Быстрая мокрая керамика", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 2000},
  {"cat": "Керамика и Силант", "name": "Силант на кузов", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 3000},
  {"cat": "Антидождь", "name": "Krytex лобовое стекло", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 3500},
  {"cat": "Антидождь", "name": "Krytex передняя полусфера", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 6000},
  {"cat": "Антидождь", "name": "Krytex все остекление 1 кл.", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 8000},
  {"cat": "Антидождь", "name": "Krytex все остекление 2 кл.", "p1": 0, "p2": 10000, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Антидождь", "name": "Krytex все остекление 3 кл.", "p1": 0, "p2": 0, "p3": 12000, "p4": 0, "fp": 0},
  {"cat": "Антидождь", "name": "Krytex все остекление 4 кл.", "p1": 0, "p2": 0, "p3": 0, "p4": 12000, "fp": 0},
  // Оклейка: частые + зоны риска (цены — fixed_price, класс не влияет)
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · Капот", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · Фары", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · Крыша (полоса)", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · Полная оклейка кузова", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · ЗР · Капот", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · ЗР · Передний бампер", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · ЗР · Фары", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · ЗР · Передние крылья", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · ЗР · Расширители передних арок", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · ЗР · Зеркала", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · ЗР · Стойки лобового", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · ЗР · Полоса крыши", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · ЗР · Стойки глянцевые", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · ЗР · Пороги внутри (короткие)", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · ЗР · Пороги внутри (длинные)", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · ЗР · Зона погрузки", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · ЗР · Зона под ручками", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Оклейка (Пленка)", "name": "Оклейка · ЗР · Зона пескоструя заднего бампера", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  // Тонировка по зонам (цены — заполни в «Услуги»)
  {"cat": "Тонировка", "name": "Тонировка · Лобовое стекло", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Тонировка", "name": "Тонировка · Передние боковые", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Тонировка", "name": "Тонировка · Задние боковые", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Тонировка", "name": "Тонировка · Заднее стекло", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Тонировка", "name": "Тонировка · Задняя полусфера", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
  {"cat": "Тонировка", "name": "Тонировка · Полный комплект", "p1": 0, "p2": 0, "p3": 0, "p4": 0, "fp": 0},
];
// --- КОНЕЦ БЛОКА ---

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Полный сброс: закрыть соединение, удалить файл БД, создать заново + дефолтные данные.
  /// Бэкапы в det_app_backups не трогает.
  Future<void> resetDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, "detailing.db");
    await deleteDatabase(path);
    await initDefaultData();
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, "detailing.db");
    // v15: баг-репорты в БД (вместо файла)
    return await openDatabase(path, version: 15, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''CREATE TABLE clients (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT DEFAULT '', is_vip INTEGER DEFAULT 0)''');
    await db.execute('''CREATE TABLE cars (id INTEGER PRIMARY KEY AUTOINCREMENT, client_id INTEGER NOT NULL, make_model TEXT NOT NULL, plate TEXT DEFAULT '', vin TEXT DEFAULT '', category TEXT DEFAULT '1')''');
    await db.execute('''CREATE TABLE orders (
      id INTEGER PRIMARY KEY AUTOINCREMENT, client_id INTEGER NOT NULL, car_id INTEGER NOT NULL, 
      status TEXT DEFAULT 'Принят в работу', price REAL DEFAULT 0, notes TEXT DEFAULT '', 
      paid_amount REAL DEFAULT 0, is_completed INTEGER DEFAULT 0, due_date TEXT DEFAULT '', 
      created_at TEXT DEFAULT '', master_id INTEGER DEFAULT NULL, master_ids TEXT DEFAULT '', 
      done_tasks TEXT DEFAULT '', start_time TEXT DEFAULT '', end_time TEXT DEFAULT '', 
      end_date TEXT DEFAULT '', client_notes TEXT DEFAULT '', client_visible_notes TEXT DEFAULT '', 
      master_notes TEXT DEFAULT '', payment_method TEXT DEFAULT 'Не указан', task_prices TEXT DEFAULT '',
      is_workshop_completed INTEGER DEFAULT 0,
      discount_percent REAL DEFAULT 0,
      discount_fixed REAL DEFAULT 0,
      promo_code TEXT DEFAULT ''
    )''');
    await db.execute('''CREATE TABLE masters (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, role TEXT DEFAULT 'Универсал')''');
    await db.execute('''CREATE TABLE order_events (id INTEGER PRIMARY KEY AUTOINCREMENT, order_id INTEGER NOT NULL, event_text TEXT, created_at TEXT)''');
    await db.execute('''CREATE TABLE payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL,
      amount REAL,
      method TEXT,
      created_at TEXT,
      shift_id INTEGER
    )''');
    await db.execute('''CREATE TABLE cash_flow (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT,
      amount REAL,
      description TEXT,
      created_at TEXT,
      category TEXT DEFAULT 'Прочее',
      method TEXT DEFAULT 'Наличные',
      shift_id INTEGER,
      counterparty TEXT DEFAULT '',
      master_id INTEGER,
      inventory_id INTEGER,
      inventory_qty REAL DEFAULT 0,
      order_id INTEGER,
      template_key TEXT DEFAULT '',
      note TEXT DEFAULT ''
    )''');
    await db.execute('''CREATE TABLE cash_shifts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      opened_at TEXT NOT NULL,
      closed_at TEXT,
      opening_cash REAL DEFAULT 0,
      closing_cash REAL,
      expected_cash REAL,
      fact_cash REAL,
      difference REAL,
      note TEXT DEFAULT '',
      status TEXT DEFAULT 'open'
    )''');
    await db.execute('''CREATE TABLE custom_works (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, category TEXT DEFAULT 'Прочее', price REAL DEFAULT 0)''');
    await db.execute('''CREATE TABLE services (id INTEGER PRIMARY KEY AUTOINCREMENT, category TEXT NOT NULL, name TEXT NOT NULL UNIQUE, price1 REAL DEFAULT 0, price2 REAL DEFAULT 0, price3 REAL DEFAULT 0, price4 REAL DEFAULT 0, fixed_price REAL DEFAULT 0)''');
    await db.execute('''CREATE TABLE inventory (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, quantity REAL DEFAULT 0, unit TEXT DEFAULT 'шт')''');
    await db.execute('''CREATE TABLE service_recipes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      service_name TEXT NOT NULL,
      inventory_id INTEGER NOT NULL,
      qty REAL NOT NULL DEFAULT 1
    )''');
    await db.execute('''CREATE TABLE roles (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)''');
    await db.execute('''CREATE TABLE promocodes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT NOT NULL UNIQUE,
      discount_percent REAL DEFAULT 0,
      discount_fixed REAL DEFAULT 0,
      is_active INTEGER DEFAULT 1
    )''');
    await db.execute('''CREATE TABLE order_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER, name TEXT, price REAL, master_ids TEXT,
      start_time TEXT, end_time TEXT, workshop TEXT,
      is_done INTEGER DEFAULT 0,
      parent_id INTEGER
    )''');
    await db.execute('''CREATE TABLE bug_reports (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      place TEXT DEFAULT '',
      situation TEXT DEFAULT '',
      details TEXT NOT NULL,
      status TEXT DEFAULT 'open',
      fix_note TEXT DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT
    )''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE orders ADD COLUMN is_workshop_completed INTEGER DEFAULT 0;");
    }
    if (oldVersion < 5) {
      // Удаляем старую таблицу работ (если она создалась криво) и создаем новую, правильную
      await db.execute("DROP TABLE IF EXISTS order_items;");
      await db.execute('''
        CREATE TABLE order_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          order_id INTEGER, 
          name TEXT, 
          price REAL, 
          master_ids TEXT
        )
      ''');
    }
    if (oldVersion < 6) {
      await db.execute("ALTER TABLE orders ADD COLUMN tech_wash_start TEXT;");
      await db.execute("ALTER TABLE orders ADD COLUMN tech_wash_end TEXT;");
    }
    // --- Версия 7: время и цех у каждой услуги ---
    if (oldVersion < 7) {
      await db.execute("ALTER TABLE order_items ADD COLUMN start_time TEXT;");
      await db.execute("ALTER TABLE order_items ADD COLUMN end_time TEXT;");
      await db.execute("ALTER TABLE order_items ADD COLUMN workshop TEXT;");
    }
    // --- Версия 8: галочка «работа выполнена» ---
    if (oldVersion < 8) {
      await db.execute("ALTER TABLE order_items ADD COLUMN is_done INTEGER DEFAULT 0;");
    }
    // --- Версия 9: рецепты склада, категории без emoji, тонировка по зонам ---
    if (oldVersion < 9) {
      await db.execute('''CREATE TABLE IF NOT EXISTS service_recipes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service_name TEXT NOT NULL,
        inventory_id INTEGER NOT NULL,
        qty REAL NOT NULL DEFAULT 1
      )''');
      for (final e in CATEGORY_RENAMES.entries) {
        await db.update(
          'services',
          {'category': e.value},
          where: 'category = ?',
          whereArgs: [e.key],
        );
      }
      // Заглушку «Тонировка» без цен заменяем на зоны
      final tintRows = await db.query('services', where: 'name = ?', whereArgs: ['Тонировка']);
      if (tintRows.isNotEmpty) {
        final t = tintRows.first;
        final allZero = [t['price1'], t['price2'], t['price3'], t['price4'], t['fixed_price']]
            .every((v) => ((v as num?)?.toDouble() ?? 0) == 0);
        if (allZero) {
          await db.delete('services', where: 'name = ?', whereArgs: ['Тонировка']);
        }
      }
      for (final s in SERVICES_TREE.where((s) => s['cat'] == 'Тонировка')) {
        await db.insert(
          'services',
          {
            'category': s['cat'],
            'name': s['name'],
            'price1': s['p1'],
            'price2': s['p2'],
            'price3': s['p3'],
            'price4': s['p4'],
            'fixed_price': s['fp'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
    // --- Версия 10: скидки и промокоды ---
    if (oldVersion < 10) {
      await db.execute("ALTER TABLE orders ADD COLUMN discount_percent REAL DEFAULT 0;");
      await db.execute("ALTER TABLE orders ADD COLUMN discount_fixed REAL DEFAULT 0;");
      await db.execute("ALTER TABLE orders ADD COLUMN promo_code TEXT DEFAULT '';");
      await db.execute('''CREATE TABLE IF NOT EXISTS promocodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        discount_percent REAL DEFAULT 0,
        discount_fixed REAL DEFAULT 0,
        is_active INTEGER DEFAULT 1
      )''');
    }
    // --- Версия 11: оклейка — частые + зоны риска ---
    if (oldVersion < 11) {
      await _migrateWrapServices(db);
    }
    // --- Версия 12: пакет оклейки (parent_id) ---
    if (oldVersion < 12) {
      await db.execute('ALTER TABLE order_items ADD COLUMN parent_id INTEGER;');
      await _migrateWrapPackages(db);
    }
    // --- Версия 13: убрана «Уборка салона» ---
    if (oldVersion < 13) {
      await db.delete(
        'services',
        where: "category = ? OR name = ?",
        whereArgs: ['Уборка салона', 'Уборка салона'],
      );
    }
    // --- Версия 14: сильная касса ---
    if (oldVersion < 14) {
      await db.execute("ALTER TABLE payments ADD COLUMN shift_id INTEGER;");
      await db.execute("ALTER TABLE cash_flow ADD COLUMN category TEXT DEFAULT 'Прочее';");
      await db.execute("ALTER TABLE cash_flow ADD COLUMN method TEXT DEFAULT 'Наличные';");
      await db.execute("ALTER TABLE cash_flow ADD COLUMN shift_id INTEGER;");
      await db.execute("ALTER TABLE cash_flow ADD COLUMN counterparty TEXT DEFAULT '';");
      await db.execute("ALTER TABLE cash_flow ADD COLUMN master_id INTEGER;");
      await db.execute("ALTER TABLE cash_flow ADD COLUMN inventory_id INTEGER;");
      await db.execute("ALTER TABLE cash_flow ADD COLUMN inventory_qty REAL DEFAULT 0;");
      await db.execute("ALTER TABLE cash_flow ADD COLUMN order_id INTEGER;");
      await db.execute("ALTER TABLE cash_flow ADD COLUMN template_key TEXT DEFAULT '';");
      await db.execute("ALTER TABLE cash_flow ADD COLUMN note TEXT DEFAULT '';");
      await db.execute('''CREATE TABLE IF NOT EXISTS cash_shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        opened_at TEXT NOT NULL,
        closed_at TEXT,
        opening_cash REAL DEFAULT 0,
        closing_cash REAL,
        expected_cash REAL,
        fact_cash REAL,
        difference REAL,
        note TEXT DEFAULT '',
        status TEXT DEFAULT 'open'
      )''');
      await db.update('cash_flow', {'category': 'Прочее', 'method': 'Наличные'},
          where: "category IS NULL OR category = '' OR method IS NULL OR method = ''");
    }
    // --- Версия 15: баг-репорты в приложении ---
    if (oldVersion < 15) {
      await db.execute('''CREATE TABLE IF NOT EXISTS bug_reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        place TEXT DEFAULT '',
        situation TEXT DEFAULT '',
        details TEXT NOT NULL,
        status TEXT DEFAULT 'open',
        fix_note TEXT DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT
      )''');
    }
  }

  /// Собирает сиротские позиции оклейки в пакеты по заказам.
  static Future<void> _migrateWrapPackages(Database db) async {
    final all = await db.query('order_items');
    final byOrder = <int, List<Map<String, dynamic>>>{};
    for (final row in all) {
      final oid = (row['order_id'] as num?)?.toInt();
      if (oid == null) continue;
      byOrder.putIfAbsent(oid, () => []).add(row);
    }
    for (final entry in byOrder.entries) {
      final orderId = entry.key;
      final items = entry.value;
      final orphans = items.where((i) {
        if (isWrapPackageHeader(i['name']?.toString())) return false;
        if (!isWrapPackageLine(name: i['name']?.toString())) return false;
        final pid = i['parent_id'];
        return pid == null;
      }).toList();
      if (orphans.isEmpty) continue;

      Map<String, dynamic>? header;
      for (final i in items) {
        if (isWrapPackageHeader(i['name']?.toString()) && i['parent_id'] == null) {
          header = i;
          break;
        }
      }

      final orphanSum = orphans.fold<double>(
        0,
        (s, i) => s + ((i['price'] as num?)?.toDouble() ?? 0),
      );

      int headerId;
      if (header != null) {
        headerId = (header['id'] as num).toInt();
        final existing = (header['price'] as num?)?.toDouble() ?? 0;
        if (orphanSum > 0 && existing == 0) {
          await db.update(
            'order_items',
            {'price': orphanSum},
            where: 'id = ?',
            whereArgs: [headerId],
          );
        }
      } else {
        headerId = await db.insert('order_items', {
          'order_id': orderId,
          'name': 'Оклейка',
          'price': orphanSum,
          'master_ids': '',
          'is_done': 0,
          'workshop': 'Оклейка',
          'parent_id': null,
        });
      }

      for (final child in orphans) {
        await db.update(
          'order_items',
          {'parent_id': headerId, 'price': 0},
          where: 'id = ?',
          whereArgs: [(child['id'] as num).toInt()],
        );
      }
    }
  }

  /// Удаляет старые позиции оклейки и добавляет новый каталог (fp=0).
  static Future<void> _migrateWrapServices(Database db) async {
    const oldNames = [
      'Оклейка капота',
      'Оклейка крыши',
      'Полная оклейка кузова',
    ];
    for (final name in oldNames) {
      await db.delete('services', where: 'name = ?', whereArgs: [name]);
    }
    for (final s in SERVICES_TREE.where((s) => s['cat'] == 'Оклейка (Пленка)')) {
      await db.insert(
        'services',
        {
          'category': s['cat'],
          'name': s['name'],
          'price1': s['p1'],
          'price2': s['p2'],
          'price3': s['p3'],
          'price4': s['p4'],
          'fixed_price': s['fp'],
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Итоговая цена: сумма работ минус % затем фикс. Не ниже 0.
  static double priceAfterDiscount(double worksTotal, double percent, double fixed) {
    var total = worksTotal * (1 - (percent.clamp(0, 100) / 100));
    total -= fixed;
    if (total < 0) total = 0;
    return double.parse(total.toStringAsFixed(2));
  }

  Future<void> initDefaultData() async {
    final db = await database;
    List<Map> services = await db.query('services');
    if (services.isEmpty) {
      for (var s in SERVICES_TREE) {
        await db.insert('services', {'category': s['cat'], 'name': s['name'], 'price1': s['p1'], 'price2': s['p2'], 'price3': s['p3'], 'price4': s['p4'], 'fixed_price': s['fp']});
      }
    } else {
      // Добиваем новые позиции тонировки / оклейки на уже существующих базах
      for (final s in SERVICES_TREE.where(
        (s) => s['cat'] == 'Тонировка' || s['cat'] == 'Оклейка (Пленка)',
      )) {
        await db.insert(
          'services',
          {
            'category': s['cat'],
            'name': s['name'],
            'price1': s['p1'],
            'price2': s['p2'],
            'price3': s['p3'],
            'price4': s['p4'],
            'fixed_price': s['fp'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      // Убираем устаревшие имена оклейки, если ещё остались
      for (final name in ['Оклейка капота', 'Оклейка крыши', 'Полная оклейка кузова']) {
        await db.delete('services', where: 'name = ?', whereArgs: [name]);
      }
      await db.delete(
        'services',
        where: "category = ? OR name = ?",
        whereArgs: ['Уборка салона', 'Уборка салона'],
      );
    }
    List<Map> roles = await db.query('roles');
    if (roles.isEmpty) {
      await db.insert('roles', {'name': 'Администратор'});
      await db.insert('roles', {'name': 'Приемщик'});
      await db.insert('roles', {'name': 'Мойка'});
      await db.insert('roles', {'name': 'Химчистка'});
      await db.insert('roles', {'name': 'Полировка'});
      await db.insert('roles', {'name': 'Оклейка'});
      await db.insert('roles', {'name': 'Интерьер'});
      await db.insert('roles', {'name': 'Оборудование'});
      await db.insert('roles', {'name': 'Кузовные работы'});
      await db.insert('roles', {'name': 'Тюнинг/Интерьер'});
      await db.insert('roles', {'name': 'Универсал'});
    } else {
      // Добиваем роли цехов, если база уже была
      for (final w in WORKSHOPS) {
        await db.insert('roles', {'name': w}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  // --- ЗАКАЗЫ ---
  Future<List<Map<String, dynamic>>> getAllOrders() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT orders.*, clients.name as client_name, clients.phone as client_phone, cars.make_model, cars.plate, m.name as master_name,
        (SELECT COUNT(*) FROM order_items WHERE order_items.order_id = orders.id AND NOT (order_items.name = 'Оклейка' AND order_items.parent_id IS NULL)) as works_total,
        (SELECT COUNT(*) FROM order_items WHERE order_items.order_id = orders.id AND order_items.is_done = 1 AND NOT (order_items.name = 'Оклейка' AND order_items.parent_id IS NULL)) as works_done
      FROM orders JOIN clients ON orders.client_id = clients.id JOIN cars ON orders.car_id = cars.id
      LEFT JOIN masters m ON orders.master_id = m.id
      WHERE orders.is_completed = 0 ORDER BY orders.id DESC
    ''');
  }

  Future<Map<String, dynamic>?> getOrderById(int orderId) async {
    final db = await database;
    List<Map> res = await db.rawQuery('''
      SELECT orders.*, clients.name as client_name, clients.phone as client_phone, clients.is_vip,
             cars.make_model, cars.plate, cars.vin, cars.category,
             m.name as master_name,
             (SELECT COUNT(*) FROM order_items WHERE order_items.order_id = orders.id AND NOT (order_items.name = 'Оклейка' AND order_items.parent_id IS NULL)) as works_total,
             (SELECT COUNT(*) FROM order_items WHERE order_items.order_id = orders.id AND order_items.is_done = 1 AND NOT (order_items.name = 'Оклейка' AND order_items.parent_id IS NULL)) as works_done
      FROM orders
      JOIN clients ON orders.client_id = clients.id
      JOIN cars ON orders.car_id = cars.id
      LEFT JOIN masters m ON orders.master_id = m.id
      WHERE orders.id = ?
    ''', [orderId]);
    return res.isNotEmpty ? Map<String, dynamic>.from(res.first) : null;
  }

  /// Завершённые заказы (Выдан). Опциональный поиск по клиенту/авто/id.
  Future<List<Map<String, dynamic>>> getCompletedOrders([String query = ""]) async {
    final db = await database;
    final q = query.trim();
    if (q.isEmpty) {
      return await db.rawQuery('''
        SELECT orders.*, clients.name as client_name, clients.phone as client_phone,
               cars.make_model, cars.plate, cars.vin, m.name as master_name,
               (SELECT COUNT(*) FROM order_items WHERE order_items.order_id = orders.id AND NOT (order_items.name = 'Оклейка' AND order_items.parent_id IS NULL)) as works_total,
               (SELECT COUNT(*) FROM order_items WHERE order_items.order_id = orders.id AND order_items.is_done = 1 AND NOT (order_items.name = 'Оклейка' AND order_items.parent_id IS NULL)) as works_done
        FROM orders
        JOIN clients ON orders.client_id = clients.id
        JOIN cars ON orders.car_id = cars.id
        LEFT JOIN masters m ON orders.master_id = m.id
        WHERE orders.is_completed = 1
        ORDER BY orders.id DESC
      ''');
    }
    final like = "%$q%";
    return await db.rawQuery('''
      SELECT orders.*, clients.name as client_name, clients.phone as client_phone,
             cars.make_model, cars.plate, cars.vin, m.name as master_name,
             (SELECT COUNT(*) FROM order_items WHERE order_items.order_id = orders.id AND NOT (order_items.name = 'Оклейка' AND order_items.parent_id IS NULL)) as works_total,
             (SELECT COUNT(*) FROM order_items WHERE order_items.order_id = orders.id AND order_items.is_done = 1 AND NOT (order_items.name = 'Оклейка' AND order_items.parent_id IS NULL)) as works_done
      FROM orders
      JOIN clients ON orders.client_id = clients.id
      JOIN cars ON orders.car_id = cars.id
      LEFT JOIN masters m ON orders.master_id = m.id
      WHERE orders.is_completed = 1 AND (
        clients.name LIKE ? OR clients.phone LIKE ? OR cars.make_model LIKE ?
        OR cars.plate LIKE ? OR cars.vin LIKE ? OR orders.notes LIKE ?
        OR CAST(orders.id AS TEXT) LIKE ?
      )
      ORDER BY orders.id DESC
    ''', [like, like, like, like, like, like, like]);
  }

  Future<List<Map<String, dynamic>>> getOrdersForCalendar(String dateStr) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT orders.id, orders.status, orders.start_time, orders.end_time, orders.due_date, orders.tech_wash_start, orders.tech_wash_end, 
             clients.name as client_name, cars.make_model, cars.plate
      FROM orders
      JOIN clients ON orders.client_id = clients.id
      JOIN cars ON orders.car_id = cars.id
      WHERE orders.is_completed = 0 AND (
        date(orders.due_date) = date(?) 
        OR (orders.tech_wash_start IS NOT NULL AND date(orders.tech_wash_start) = date(?))
      )
      ORDER BY orders.start_time ASC
    ''', [dateStr, dateStr]);
  }

  /// Работы с заданным временем на выбранный день (для режима «Детальное время»).
  /// Дата = первые 10 символов (ГГГГ-ММ-ДД).
  Future<List<Map<String, dynamic>>> getOrderItemsForCalendar(String dateStr) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT order_items.id as item_id, order_items.order_id, order_items.name as work_name,
             order_items.start_time, order_items.end_time, order_items.workshop,
             order_items.is_done, order_items.parent_id,
             clients.name as client_name, cars.make_model, cars.plate
      FROM order_items
      JOIN orders ON order_items.order_id = orders.id
      JOIN clients ON orders.client_id = clients.id
      JOIN cars ON orders.car_id = cars.id
      WHERE orders.is_completed = 0
        AND order_items.start_time IS NOT NULL
        AND order_items.start_time != ''
        AND order_items.workshop IS NOT NULL
        AND order_items.workshop != ''
        AND substr(replace(order_items.start_time, 'T', ' '), 1, 10) = ?
      ORDER BY order_items.start_time ASC
    ''', [dateStr]);
  }

  Future<int> addClient(String name, String phone, {int isVip = 0}) async {
    final db = await database;
    return await db.insert('clients', {'name': name, 'phone': phone, 'is_vip': isVip});
  }

  Future<int> addCar(int clientId, String makeModel, String plate, {String vin = "", String category = "1"}) async {
    final db = await database;
    return await db.insert('cars', {'client_id': clientId, 'make_model': makeModel, 'plate': plate, 'vin': vin, 'category': category});
  }

  Future<void> updateCar(int carId, {String? makeModel, String? plate, String? vin, String? category}) async {
    final db = await database;
    final data = <String, dynamic>{};
    if (makeModel != null) data['make_model'] = makeModel;
    if (plate != null) data['plate'] = plate;
    if (vin != null) data['vin'] = vin;
    if (category != null) data['category'] = category;
    if (data.isEmpty) return;
    await db.update('cars', data, where: 'id = ?', whereArgs: [carId]);
  }

  Future<int> addOrder(int clientId, int carId, double price, String notes, 
      {String status = "Принят в работу", String dueDate = "", String startTime = ""}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String().substring(0, 16);
    return await db.insert('orders', {
      'client_id': clientId, 'car_id': carId, 'status': status, 'price': price, 
      'notes': notes, 'created_at': now, 'due_date': dueDate, 'start_time': startTime
    });
  }

  /// Создаёт заказ и сразу строки order_items, затем синхронизирует notes/price.
  Future<int> addOrderWithItems(
    int clientId,
    int carId,
    List<Map<String, dynamic>> items, {
    String status = "Принят в работу",
    String dueDate = "",
    String startTime = "",
    String endTime = "",
    String endDate = "",
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String().substring(0, 16);
    String notes = items.map((i) => i['name'] as String).join(", ");
    double price = items.fold(0.0, (sum, i) => sum + ((i['price'] as num?)?.toDouble() ?? 0));
    int orderId = await db.insert('orders', {
      'client_id': clientId,
      'car_id': carId,
      'status': status,
      'price': price,
      'notes': notes,
      'created_at': now,
      'due_date': dueDate,
      'start_time': startTime,
      'end_time': endTime,
      'end_date': endDate,
    });
    for (var item in items) {
      final name = item['name'] as String;
      final cat = item['category']?.toString();
      final ws = (item['workshop'] as String?) ??
          workshopForService(category: cat, name: name);
      final price = (item['price'] as num?)?.toDouble() ?? 0;
      await addOrderItem(
        orderId,
        name,
        price,
        sync: false,
        workshop: ws,
        category: cat,
      );
    }
    await syncOrderFromItems(orderId);
    return orderId;
  }

  /// Денормализует notes и price заказа из order_items (+ скидка заказа).
  Future<void> syncOrderFromItems(int orderId) async {
    final db = await database;
    final items = await db.query('order_items', where: 'order_id = ?', whereArgs: [orderId]);
    final notes = items.map((i) => i['name'] as String).join(", ");
    final works = items.fold(0.0, (sum, i) => sum + ((i['price'] as num?)?.toDouble() ?? 0));
    final orderRows = await db.query(
      'orders',
      columns: ['discount_percent', 'discount_fixed'],
      where: 'id = ?',
      whereArgs: [orderId],
    );
    final pct = orderRows.isEmpty
        ? 0.0
        : (orderRows.first['discount_percent'] as num?)?.toDouble() ?? 0;
    final fixed = orderRows.isEmpty
        ? 0.0
        : (orderRows.first['discount_fixed'] as num?)?.toDouble() ?? 0;
    final price = priceAfterDiscount(works, pct, fixed);
    await db.update('orders', {'notes': notes, 'price': price}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateOrderDiscount(
    int orderId, {
    double? discountPercent,
    double? discountFixed,
    String? promoCode,
  }) async {
    final db = await database;
    final data = <String, dynamic>{};
    if (discountPercent != null) data['discount_percent'] = discountPercent;
    if (discountFixed != null) data['discount_fixed'] = discountFixed;
    if (promoCode != null) data['promo_code'] = promoCode;
    if (data.isNotEmpty) {
      await db.update('orders', data, where: 'id = ?', whereArgs: [orderId]);
    }
    await syncOrderFromItems(orderId);
  }

  Future<Map<String, dynamic>?> getPromocode(String code) async {
    final db = await database;
    final rows = await db.query(
      'promocodes',
      where: 'UPPER(code) = UPPER(?) AND is_active = 1',
      whereArgs: [code.trim()],
    );
    return rows.isNotEmpty ? Map<String, dynamic>.from(rows.first) : null;
  }

  Future<List<Map<String, dynamic>>> getPromocodes() async {
    final db = await database;
    return await db.query('promocodes', orderBy: 'code ASC');
  }

  Future<void> upsertPromocode(String code, double percent, double fixed) async {
    final db = await database;
    await db.insert(
      'promocodes',
      {
        'code': code.trim().toUpperCase(),
        'discount_percent': percent,
        'discount_fixed': fixed,
        'is_active': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deletePromocode(int id) async {
    final db = await database;
    await db.delete('promocodes', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getClientByPhone(String phone) async {
    final db = await database;
    List<Map> res = await db.query('clients', where: 'phone = ?', whereArgs: [phone]);
    return res.isNotEmpty ? Map<String, dynamic>.from(res.first) : null;
  }

  Future<int?> getCarId(int clientId, String plate) async {
    final db = await database;
    List<Map> res = await db.query('cars', where: 'client_id = ? AND plate = ?', whereArgs: [clientId, plate]);
    return res.isNotEmpty ? res.first['id'] as int? : null;
  }

  /// Причины, почему нельзя поставить «Выдан». Пустой список = можно.
  Future<List<String>> validateIssueOrder(int orderId) async {
    final db = await database;
    final rows = await db.query(
      'orders',
      columns: ['price', 'paid_amount'],
      where: 'id = ?',
      whereArgs: [orderId],
    );
    if (rows.isEmpty) return ['Заказ не найден'];

    final price = (rows.first['price'] as num?)?.toDouble() ?? 0;
    final paid = (rows.first['paid_amount'] as num?)?.toDouble() ?? 0;
    final debt = price - paid;
    final reasons = <String>[];

    if (debt > 0.01) {
      final debtStr = debt.toStringAsFixed(debt == debt.roundToDouble() ? 0 : 2);
      reasons.add('Долг: $debtStr ₽');
    }

    final openWorks = await db.rawQuery(
      'SELECT COUNT(*) as c FROM order_items WHERE order_id = ? AND is_done = 0',
      [orderId],
    );
    final openCount = (openWorks.first['c'] as num?)?.toInt() ?? 0;
    if (openCount > 0) {
      reasons.add('Не выполнены работы: $openCount');
    }

    return reasons;
  }

  /// Обновляет статус. Для «Выдан» сначала проверка долга и незакрытых работ.
  /// Возвращает `false`, если выдача запрещена (БД не менялась).
  Future<bool> updateStatus(int orderId, String newStatus) async {
    if (newStatus == "Выдан") {
      final reasons = await validateIssueOrder(orderId);
      if (reasons.isNotEmpty) return false;
    }
    final db = await database;
    final isComp = newStatus == "Выдан" ? 1 : 0;
    await db.update(
      'orders',
      {'status': newStatus, 'is_completed': isComp},
      where: 'id = ?',
      whereArgs: [orderId],
    );
    return true;
  }

    // --- УДАЛЕНИЕ ЗАКАЗА ---
  Future<void> deleteOrder(int orderId) async {
    final db = await database;
    await db.delete('order_items', where: 'order_id = ?', whereArgs: [orderId]);
    await db.delete('order_events', where: 'order_id = ?', whereArgs: [orderId]);
    await db.delete('payments', where: 'order_id = ?', whereArgs: [orderId]);
    await db.delete('orders', where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> setWorkshopTaskCompleted(int orderId, int isCompleted) async {
    final db = await database;
    await db.update('orders', {'is_workshop_completed': isCompleted}, where: 'id = ?', whereArgs: [orderId]);
  }

  // --- РАБОТЫ ЗАКАЗА (ORDER ITEMS) ---
  Future<List<Map<String, dynamic>>> getOrderItems(int orderId) async {
    final db = await database;
    return await db.query('order_items', where: 'order_id = ?', whereArgs: [orderId]);
  }

  /// Id шапки пакета оклейки (создаёт при отсутствии).
  Future<int> ensureWrapPackage(int orderId) async {
    final db = await database;
    final existing = await db.query(
      'order_items',
      where: "order_id = ? AND name = ? AND parent_id IS NULL",
      whereArgs: [orderId, 'Оклейка'],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return (existing.first['id'] as num).toInt();
    }
    return await db.insert('order_items', {
      'order_id': orderId,
      'name': 'Оклейка',
      'price': 0,
      'master_ids': '',
      'is_done': 0,
      'workshop': 'Оклейка',
      'parent_id': null,
    });
  }

  Future<int> addOrderItem(
    int orderId,
    String name,
    double price, {
    bool sync = true,
    String? workshop,
    String? category,
  }) async {
    final db = await database;
    final ws = workshop ?? workshopForService(category: category, name: name);

    // Позиции оклейки из прайса → состав пакета (цена только на шапке).
    if (isWrapPackageLine(category: category, name: name)) {
      final parentId = await ensureWrapPackage(orderId);
      final headerRows = await db.query(
        'order_items',
        columns: ['start_time', 'end_time', 'master_ids'],
        where: 'id = ?',
        whereArgs: [parentId],
        limit: 1,
      );
      final header = headerRows.isNotEmpty ? headerRows.first : null;
      final id = await db.insert('order_items', {
        'order_id': orderId,
        'name': name,
        'price': 0,
        'master_ids': header?['master_ids'] ?? '',
        'is_done': 0,
        'workshop': ws ?? 'Оклейка',
        'parent_id': parentId,
        'start_time': header?['start_time'],
        'end_time': header?['end_time'],
      });
      if (sync) await syncOrderFromItems(orderId);
      return id;
    }

    int id = await db.insert('order_items', {
      'order_id': orderId,
      'name': name,
      'price': price,
      'master_ids': '',
      'is_done': 0,
      'workshop': ws,
      'parent_id': null,
    });
    if (sync) await syncOrderFromItems(orderId);
    return id;
  }

  Future<void> updateOrderItemPrice(int itemId, double price) async {
    final db = await database;
    final rows = await db.query(
      'order_items',
      columns: ['order_id'],
      where: 'id = ?',
      whereArgs: [itemId],
    );
    await db.update(
      'order_items',
      {'price': price},
      where: 'id = ?',
      whereArgs: [itemId],
    );
    final orderId = rows.isNotEmpty ? rows.first['order_id'] as int? : null;
    if (orderId != null) await syncOrderFromItems(orderId);
  }

  Future<void> updateOrderItemDone(int itemId, bool isDone) async {
    final db = await database;
    final rows = await db.query(
      'order_items',
      columns: ['name', 'is_done'],
      where: 'id = ?',
      whereArgs: [itemId],
    );
    final wasDone = rows.isNotEmpty && ((rows.first['is_done'] as num?)?.toInt() ?? 0) == 1;
    await db.update('order_items', {'is_done': isDone ? 1 : 0}, where: 'id = ?', whereArgs: [itemId]);
    // Списание склада только при первом переходе в «выполнено»
    if (isDone && !wasDone && rows.isNotEmpty) {
      await deductRecipeForService(rows.first['name']?.toString() ?? '');
    }
  }

  Future<void> deleteOrderItem(int itemId) async {
    final db = await database;
    final rows = await db.query(
      'order_items',
      columns: ['order_id', 'name', 'parent_id'],
      where: 'id = ?',
      whereArgs: [itemId],
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    final orderId = row['order_id'] as int?;
    final name = row['name']?.toString();
    final parentId = (row['parent_id'] as num?)?.toInt();

    if (isWrapPackageHeader(name)) {
      // Удаляем шапку вместе со всем составом.
      await db.delete('order_items', where: 'parent_id = ?', whereArgs: [itemId]);
      await db.delete('order_items', where: 'id = ?', whereArgs: [itemId]);
    } else {
      await db.delete('order_items', where: 'id = ?', whereArgs: [itemId]);
      if (parentId != null) {
        final left = await db.query(
          'order_items',
          columns: ['id'],
          where: 'parent_id = ?',
          whereArgs: [parentId],
          limit: 1,
        );
        if (left.isEmpty) {
          await db.delete('order_items', where: 'id = ?', whereArgs: [parentId]);
        }
      }
    }
    if (orderId != null) await syncOrderFromItems(orderId);
  }

  Future<void> updateOrderItemMasters(int itemId, List<int> masterIds) async {
    final db = await database;
    await db.update('order_items', {'master_ids': masterIds.join(',')}, where: 'id = ?', whereArgs: [itemId]);
  }

  /// Общее время пакета оклейки — на шапку и всех детей.
  Future<void> updateWrapPackageSchedule(int headerId, String? startTime, String? endTime) async {
    final db = await database;
    final header = await db.query(
      'order_items',
      columns: ['workshop'],
      where: 'id = ?',
      whereArgs: [headerId],
      limit: 1,
    );
    final workshop = header.isNotEmpty ? header.first['workshop'] : 'Оклейка';
    final data = <String, dynamic>{
      'start_time': startTime,
      'end_time': endTime,
      'workshop': workshop ?? 'Оклейка',
    };
    await db.update('order_items', data, where: 'id = ?', whereArgs: [headerId]);
    await db.update('order_items', data, where: 'parent_id = ?', whereArgs: [headerId]);
  }

  /// Общие мастера пакета оклейки — на шапку и всех детей.
  Future<void> updateWrapPackageMasters(int headerId, List<int> masterIds) async {
    final db = await database;
    final csv = masterIds.join(',');
    await db.update('order_items', {'master_ids': csv}, where: 'id = ?', whereArgs: [headerId]);
    await db.update('order_items', {'master_ids': csv}, where: 'parent_id = ?', whereArgs: [headerId]);
  }

  /// Отметка выполнения пакета — шапка и все зоны (списание склада по зонам).
  Future<void> updateWrapPackageDone(int headerId, bool isDone) async {
    final db = await database;
    final children = await db.query(
      'order_items',
      columns: ['id'],
      where: 'parent_id = ?',
      whereArgs: [headerId],
    );
    await updateOrderItemDone(headerId, isDone);
    for (final c in children) {
      await updateOrderItemDone((c['id'] as num).toInt(), isDone);
    }
  }

  /// Сохраняет время и цех одной услуги (сразу в базу).
  Future<void> updateOrderItemSchedule(int itemId, String? startTime, String? endTime, String? workshop) async {
    final db = await database;
    await db.update('order_items', {
      'start_time': startTime,
      'end_time': endTime,
      'workshop': workshop,
    }, where: 'id = ?', whereArgs: [itemId]);
  }

  Future<void> updateOrderPrice(int orderId, double price) async {
    final db = await database;
    await db.update('orders', {'price': price}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateOrderNotes(int orderId, String notes) async {
    final db = await database;
    await db.update('orders', {'notes': notes}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateOrderSchedule(int orderId, String dueDate, String startTime, String endTime, String endDate) async {
    final db = await database;
    await db.update('orders', {'due_date': dueDate, 'start_time': startTime, 'end_time': endTime, 'end_date': endDate}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> setTechWash(int orderId, String? startDate, String? endDate) async {
    final db = await database;
    await db.update('orders', {
      'tech_wash_start': startDate,
      'tech_wash_end': endDate
    }, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateOrderMasters(int orderId, String masterIds) async {
    final db = await database;
    await db.update('orders', {'master_ids': masterIds}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateDoneTasks(int orderId, String doneTasks) async {
    final db = await database;
    await db.update('orders', {'done_tasks': doneTasks}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateTaskPrices(int orderId, String prices) async {
    final db = await database;
    await db.update('orders', {'task_prices': prices}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> addOrderEvent(int orderId, String text) async {
    final db = await database;
    final now = DateTime.now().toIso8601String().substring(0, 16);
    await db.insert('order_events', {'order_id': orderId, 'event_text': text, 'created_at': now});
  }

  Future<List<Map<String, dynamic>>> getOrderEvents(int orderId) async {
    final db = await database;
    return await db.query('order_events', where: 'order_id = ?', whereArgs: [orderId], orderBy: 'id DESC');
  }

  Future<void> addTaskToOrder(int orderId, String taskName, double price) async {
    final db = await database;
    List<Map> res = await db.query('orders', columns: ['notes', 'task_prices'], where: 'id = ?', whereArgs: [orderId]);
    if (res.isNotEmpty) {
      String currentNotes = res.first['notes'] ?? "";
      String currentPrices = res.first['task_prices'] ?? "";
      String newNotes = currentNotes.isEmpty ? taskName : "$currentNotes, $taskName";
      String newPrices = currentPrices.isEmpty ? "$taskName:$price|" : "$currentPrices$taskName:$price|";
      await db.update('orders', {'notes': newNotes, 'task_prices': newPrices}, where: 'id = ?', whereArgs: [orderId]);
    }
  }

  Future<void> addPayment(int orderId, double amount, String method, {int? shiftId}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String().substring(0, 16);
    final sid = shiftId ?? (await getCurrentShift())?['id'] as int?;
    await db.insert('payments', {
      'order_id': orderId,
      'amount': amount,
      'method': method,
      'created_at': now,
      'shift_id': sid,
    });
    await db.rawQuery('UPDATE orders SET paid_amount = paid_amount + ? WHERE id = ?', [amount, orderId]);
  }

  // --- КЛИЕНТЫ И АВТО ---
  Future<List<Map<String, dynamic>>> getClientsList() async {
    final db = await database;
    return await db.query('clients', orderBy: 'id DESC');
  }

  Future<List<Map<String, dynamic>>> searchClients(String query) async {
    final db = await database;
    String q = "%$query%";
    return await db.rawQuery('''
      SELECT DISTINCT clients.id, clients.name, clients.phone, clients.is_vip 
      FROM clients
      LEFT JOIN cars ON clients.id = cars.client_id
      WHERE clients.name LIKE ? OR clients.phone LIKE ? OR cars.make_model LIKE ? OR cars.plate LIKE ? OR cars.vin LIKE ?
      ORDER BY clients.id DESC
    ''', [q, q, q, q, q]);
  }

  Future<Map<String, List<Map<String, dynamic>>>> searchGlobal(String query) async {
    final db = await database;
    String q = "%$query%";
    
    List<Map> clientsRes = await db.rawQuery('''
      SELECT DISTINCT clients.id, clients.name, clients.phone 
      FROM clients
      LEFT JOIN cars ON clients.id = cars.client_id
      WHERE clients.name LIKE ? OR clients.phone LIKE ? OR cars.make_model LIKE ? OR cars.plate LIKE ?
      ORDER BY clients.id DESC
    ''', [q, q, q, q]);
    
    List<Map> ordersRes = await db.rawQuery('''
      SELECT orders.id, clients.name, cars.make_model, orders.status, orders.is_completed
      FROM orders 
      JOIN clients ON orders.client_id = clients.id 
      JOIN cars ON orders.car_id = cars.id
      WHERE (
        clients.name LIKE ? OR clients.phone LIKE ? OR cars.make_model LIKE ?
        OR cars.plate LIKE ? OR orders.notes LIKE ? OR CAST(orders.id AS TEXT) LIKE ?
      )
      ORDER BY orders.id DESC
    ''', [q, q, q, q, q, q]);
    
    return {
      "clients": clientsRes.map((m) => Map<String, dynamic>.from(m)).toList(),
      "orders": ordersRes.map((m) => Map<String, dynamic>.from(m)).toList(),
    };
  }

  Future<List<Map<String, dynamic>>> getClientCars(int clientId) async {
    final db = await database;
    return await db.query('cars', where: 'client_id = ?', whereArgs: [clientId]);
  }

  Future<List<Map<String, dynamic>>> getClientHistory(int clientId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT orders.id, orders.created_at, orders.notes, orders.price, orders.status, orders.is_completed,
             cars.make_model, cars.plate
      FROM orders
      JOIN cars ON orders.car_id = cars.id
      WHERE orders.client_id = ?
      ORDER BY orders.id DESC
    ''', [clientId]);
  }

  Future<void> updateClientVip(int clientId, int isVip) async {
    final db = await database;
    await db.update('clients', {'is_vip': isVip}, where: 'id = ?', whereArgs: [clientId]);
  }

  Future<void> deleteClient(int clientId) async {
    final db = await database;
    await db.delete('clients', where: 'id = ?', whereArgs: [clientId]);
  }

  Future<void> deleteCar(int carId) async {
    final db = await database;
    await db.delete('cars', where: 'id = ?', whereArgs: [carId]);
  }

  // --- МАСТЕРА И РОЛИ ---
  Future<List<Map<String, dynamic>>> getAllMastersFull() async {
    final db = await database;
    return await db.query('masters', orderBy: 'id ASC');
  }

  Future<List<String>> getMastersList({String? roleFilter}) async {
    final db = await database;
    List<Map> res;
    if (roleFilter != null) {
      res = await db.query('masters', columns: ['name'], where: 'role = ?', whereArgs: [roleFilter], orderBy: 'id ASC');
    } else {
      res = await db.query('masters', columns: ['name'], orderBy: 'id ASC');
    }
    return ["Не назначен"] + res.map((m) => m['name'] as String).toList();
  }

  Future<void> addMaster(String name, String role) async {
    final db = await database;
    await db.insert('masters', {'name': name, 'role': role});
  }

  Future<void> updateMaster(int id, {String? name, String? role}) async {
    final db = await database;
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (role != null) data['role'] = role;
    if (data.isEmpty) return;
    await db.update('masters', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMaster(String name) async {
    final db = await database;
    await db.delete('masters', where: 'name = ?', whereArgs: [name]);
  }

  Future<void> deleteMasterById(int id) async {
    final db = await database;
    await db.delete('masters', where: 'id = ?', whereArgs: [id]);
  }

  /// Назначает мастеров на все работы заказа в данном цехе.
  /// Учитывает пустой `workshop`, если имя услуги резолвится в этот цех.
  Future<int> assignMastersToWorkshop(
    int orderId,
    String workshop,
    List<int> masterIds,
  ) async {
    final db = await database;
    final items = await db.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );
    final csv = masterIds.join(',');
    var updated = 0;
    for (final item in items) {
      if (isWrapPackageHeader(item['name']?.toString())) continue;
      final raw = (item['workshop'] as String?)?.trim() ?? '';
      String resolved = raw;
      if (resolved.isEmpty || !WORKSHOPS.contains(resolved)) {
        resolved = workshopForService(name: item['name']?.toString()) ?? '';
      }
      if (resolved != workshop) continue;
      await db.update(
        'order_items',
        {'master_ids': csv},
        where: 'id = ?',
        whereArgs: [item['id']],
      );
      updated++;
    }
    return updated;
  }

  /// Имена мастеров, назначенных на работы данного цеха в заказе.
  Future<String> getWorkshopMasterNames(int orderId, String workshop) async {
    final db = await database;
    final items = await db.query(
      'order_items',
      columns: ['name', 'workshop', 'master_ids'],
      where: 'order_id = ?',
      whereArgs: [orderId],
    );
    final idSet = <int>{};
    for (final item in items) {
      final raw = (item['workshop'] as String?)?.trim() ?? '';
      String resolved = raw;
      if (resolved.isEmpty || !WORKSHOPS.contains(resolved)) {
        resolved = workshopForService(name: item['name']?.toString()) ?? '';
      }
      if (resolved != workshop) continue;
      final idsRaw = item['master_ids']?.toString() ?? '';
      if (idsRaw.isEmpty) continue;
      for (final part in idsRaw.split(',')) {
        final id = int.tryParse(part.trim());
        if (id != null) idSet.add(id);
      }
    }
    if (idSet.isEmpty) return '';
    final masters = await db.query('masters', columns: ['id', 'name']);
    final byId = {
      for (final m in masters) (m['id'] as num).toInt(): m['name']?.toString() ?? '',
    };
    return idSet
        .map((id) => byId[id] ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');
  }

  Future<List<String>> getRolesList() async {
    final db = await database;
    List<Map> res = await db.query('roles', orderBy: 'id ASC');
    return res.map((r) => r['name'] as String).toList();
  }

  Future<void> addRole(String name) async {
    final db = await database;
    await db.insert('roles', {'name': name}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> deleteRole(String name) async {
    final db = await database;
    await db.delete('roles', where: 'name = ?', whereArgs: [name]);
  }

  // --- КАССА И СТАТИСТИКА ---

  Future<Map<String, dynamic>?> getCurrentShift() async {
    final db = await database;
    final rows = await db.query(
      'cash_shifts',
      where: "status = 'open'",
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> openCashShift(double openingCash, {String note = ''}) async {
    final existing = await getCurrentShift();
    if (existing != null) return (existing['id'] as num).toInt();
    final db = await database;
    final now = DateTime.now().toIso8601String().substring(0, 16);
    return await db.insert('cash_shifts', {
      'opened_at': now,
      'opening_cash': openingCash,
      'note': note,
      'status': 'open',
    });
  }

  /// Ожидаемый нал в ящике: opening + нал приходы − нал расходы (включая инкассацию).
  Future<double> getShiftExpectedCash(int shiftId) async {
    final db = await database;
    final shiftRows = await db.query('cash_shifts', where: 'id = ?', whereArgs: [shiftId]);
    if (shiftRows.isEmpty) return 0;
    final opening = (shiftRows.first['opening_cash'] as num?)?.toDouble() ?? 0;

    final payRows = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total FROM payments
      WHERE shift_id = ? AND method = 'Наличные'
    ''', [shiftId]);
    final cashPayments = (payRows.first['total'] as num?)?.toDouble() ?? 0;

    final flowRows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'Приход' THEN amount ELSE 0 END), 0) as income,
        COALESCE(SUM(CASE WHEN type = 'Расход' THEN amount ELSE 0 END), 0) as expense
      FROM cash_flow
      WHERE shift_id = ? AND method = 'Наличные'
    ''', [shiftId]);
    final income = (flowRows.first['income'] as num?)?.toDouble() ?? 0;
    final expense = (flowRows.first['expense'] as num?)?.toDouble() ?? 0;

    return opening + cashPayments + income - expense;
  }

  Future<void> closeCashShift(int shiftId, double factCash, {String note = ''}) async {
    final db = await database;
    final expected = await getShiftExpectedCash(shiftId);
    final now = DateTime.now().toIso8601String().substring(0, 16);
    await db.update(
      'cash_shifts',
      {
        'closed_at': now,
        'closing_cash': factCash,
        'expected_cash': expected,
        'fact_cash': factCash,
        'difference': factCash - expected,
        'note': note,
        'status': 'closed',
      },
      where: 'id = ?',
      whereArgs: [shiftId],
    );
  }

  Future<List<Map<String, dynamic>>> getRecentShifts({int limit = 20}) async {
    final db = await database;
    return await db.query('cash_shifts', orderBy: 'id DESC', limit: limit);
  }

  Future<int> addCashFlow(
    String type,
    double amount,
    String description, {
    String category = 'Прочее',
    String method = 'Наличные',
    int? shiftId,
    String counterparty = '',
    int? masterId,
    int? inventoryId,
    double inventoryQty = 0,
    int? orderId,
    String templateKey = '',
    String note = '',
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String().substring(0, 16);
    final sid = shiftId ?? (await getCurrentShift())?['id'] as int?;
    final id = await db.insert('cash_flow', {
      'type': type,
      'amount': amount,
      'description': description,
      'created_at': now,
      'category': category,
      'method': method,
      'shift_id': sid,
      'counterparty': counterparty,
      'master_id': masterId,
      'inventory_id': inventoryId,
      'inventory_qty': inventoryQty,
      'order_id': orderId,
      'template_key': templateKey,
      'note': note,
    });
    // Закупка на склад: приход количества
    if (inventoryId != null && inventoryQty > 0 && type == 'Расход') {
      await adjustInventoryQuantity(inventoryId, inventoryQty);
    }
    return id;
  }

  Future<List<Map<String, dynamic>>> getCashFlow(String startDate, String endDate) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT cash_flow.*, masters.name as master_name, inventory.name as inventory_name
      FROM cash_flow
      LEFT JOIN masters ON masters.id = cash_flow.master_id
      LEFT JOIN inventory ON inventory.id = cash_flow.inventory_id
      WHERE date(cash_flow.created_at) >= date(?) AND date(cash_flow.created_at) <= date(?)
      ORDER BY cash_flow.created_at DESC
    ''', [startDate, endDate]);
  }

  Future<List<Map<String, dynamic>>> getPaymentsByPeriod(String startDate, String endDate) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT payments.id, payments.amount, payments.method, payments.created_at, payments.shift_id,
             clients.name, orders.id as order_id
      FROM payments
      JOIN orders ON payments.order_id = orders.id
      JOIN clients ON orders.client_id = clients.id
      WHERE date(payments.created_at) >= date(?) AND date(payments.created_at) <= date(?)
      ORDER BY payments.created_at DESC
    ''', [startDate, endDate]);
  }

  /// Единый журнал: оплаты заказов + сторонние операции.
  Future<List<Map<String, dynamic>>> getCashJournal(String startDate, String endDate) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT
        'payment' as source,
        payments.id as id,
        payments.created_at as created_at,
        payments.amount as amount,
        'Приход' as type,
        'Оплата заказа' as category,
        COALESCE(payments.method, '') as method,
        ('Оплата заказа #' || orders.id || ' (' || clients.name || ')') as title,
        payments.shift_id as shift_id,
        orders.id as order_id,
        NULL as master_id,
        NULL as inventory_id,
        '' as template_key,
        '' as note
      FROM payments
      JOIN orders ON payments.order_id = orders.id
      JOIN clients ON orders.client_id = clients.id
      WHERE date(payments.created_at) >= date(?) AND date(payments.created_at) <= date(?)

      UNION ALL

      SELECT
        'flow' as source,
        cash_flow.id as id,
        cash_flow.created_at as created_at,
        cash_flow.amount as amount,
        cash_flow.type as type,
        COALESCE(cash_flow.category, 'Прочее') as category,
        COALESCE(cash_flow.method, '') as method,
        COALESCE(cash_flow.description, '') as title,
        cash_flow.shift_id as shift_id,
        cash_flow.order_id as order_id,
        cash_flow.master_id as master_id,
        cash_flow.inventory_id as inventory_id,
        COALESCE(cash_flow.template_key, '') as template_key,
        COALESCE(cash_flow.note, '') as note
      FROM cash_flow
      WHERE date(cash_flow.created_at) >= date(?) AND date(cash_flow.created_at) <= date(?)

      ORDER BY created_at DESC
    ''', [startDate, endDate, startDate, endDate]);
  }

  Future<List<Map<String, dynamic>>> getOrderDebts({int limit = 50}) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT orders.id, orders.price, orders.paid_amount, orders.status,
             (orders.price - orders.paid_amount) as debt,
             clients.name as client_name, cars.make_model, cars.plate
      FROM orders
      JOIN clients ON clients.id = orders.client_id
      JOIN cars ON cars.id = orders.car_id
      WHERE orders.is_completed = 0
        AND (orders.price - orders.paid_amount) > 0.01
      ORDER BY debt DESC
      LIMIT ?
    ''', [limit]);
  }

  Future<double> getTotalDebt() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN price - paid_amount > 0.01 THEN price - paid_amount ELSE 0 END), 0) as debt
      FROM orders WHERE is_completed = 0
    ''');
    return (rows.first['debt'] as num?)?.toDouble() ?? 0;
  }

  /// Подсказка: сумма работ мастера за период (по master_ids в order_items).
  Future<double> suggestMasterPayroll(int masterId, String startDate, String endDate) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(price), 0) as total
      FROM order_items
      WHERE (master_ids = ? OR master_ids LIKE ? OR master_ids LIKE ? OR master_ids LIKE ?)
        AND (
          (start_time IS NOT NULL AND start_time != '' AND date(replace(start_time, 'T', ' ')) >= date(?) AND date(replace(start_time, 'T', ' ')) <= date(?))
          OR
          ((start_time IS NULL OR start_time = '') AND order_id IN (
            SELECT id FROM orders WHERE date(created_at) >= date(?) AND date(created_at) <= date(?)
          ))
        )
    ''', [
      '$masterId',
      '$masterId,%',
      '%,$masterId',
      '%,$masterId,%',
      startDate,
      endDate,
      startDate,
      endDate,
    ]);
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<double> getRevenueToday() async {
    final db = await database;
    String today = DateTime.now().toIso8601String().substring(0, 10) + "%";
    List<Map> res = await db.rawQuery('SELECT COALESCE(SUM(paid_amount), 0) as total FROM orders WHERE is_completed = 1 AND created_at LIKE ?', [today]);
    return (res.first['total'] as num).toDouble();
  }

  Future<double> getRevenueMonth() async {
    final db = await database;
    String month = DateTime.now().toIso8601String().substring(0, 7) + "%";
    List<Map> res = await db.rawQuery('SELECT COALESCE(SUM(paid_amount), 0) as total FROM orders WHERE is_completed = 1 AND created_at LIKE ?', [month]);
    return (res.first['total'] as num).toDouble();
  }

  /// KPI статистики: средний чек / число завершённых / долг по активным.
  Future<Map<String, double>> getStatsKpis() async {
    final db = await database;
    final completed = await db.rawQuery('''
      SELECT COUNT(*) as cnt, COALESCE(AVG(paid_amount), 0) as avg_check,
             COALESCE(SUM(paid_amount), 0) as revenue
      FROM orders WHERE is_completed = 1
    ''');
    final debt = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN price - paid_amount > 0.01 THEN price - paid_amount ELSE 0 END), 0) as debt
      FROM orders WHERE is_completed = 0
    ''');
    final c = completed.first;
    return {
      'orders_count': (c['cnt'] as num?)?.toDouble() ?? 0,
      'avg_check': (c['avg_check'] as num?)?.toDouble() ?? 0,
      'revenue_all': (c['revenue'] as num?)?.toDouble() ?? 0,
      'open_debt': (debt.first['debt'] as num?)?.toDouble() ?? 0,
    };
  }

  /// Выручка по дням за последние [days] дней (завершённые заказы).
  Future<List<Map<String, dynamic>>> getRevenueByDay(int days) async {
    final db = await database;
    final offset = days - 1;
    final rows = await db.rawQuery('''
      SELECT date(created_at) as day, COALESCE(SUM(paid_amount), 0) as total
      FROM orders
      WHERE is_completed = 1
        AND date(created_at) >= date('now', ?)
      GROUP BY date(created_at)
      ORDER BY day ASC
    ''', ['-$offset days']);
    return rows.map((r) => {
      'day': r['day']?.toString() ?? '',
      'total': (r['total'] as num?)?.toDouble() ?? 0.0,
    }).toList();
  }

  // --- СКЛАД И УСЛУГИ ---
  Future<List<Map<String, dynamic>>> getInventory() async {
    final db = await database;
    return await db.query('inventory', orderBy: 'name ASC');
  }

  Future<int> addInventoryItem(String name, double quantity, String unit) async {
    final db = await database;
    return await db.insert('inventory', {
      'name': name.trim(),
      'quantity': quantity,
      'unit': unit.trim().isEmpty ? 'шт' : unit.trim(),
    });
  }

  Future<void> updateInventoryItem(int id, {String? name, double? quantity, String? unit}) async {
    final db = await database;
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name.trim();
    if (quantity != null) data['quantity'] = quantity;
    if (unit != null) data['unit'] = unit.trim().isEmpty ? 'шт' : unit.trim();
    if (data.isEmpty) return;
    await db.update('inventory', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteInventoryItem(int id) async {
    final db = await database;
    await db.delete('service_recipes', where: 'inventory_id = ?', whereArgs: [id]);
    await db.delete('inventory', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> adjustInventoryQuantity(int id, double delta) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE inventory SET quantity = quantity + ? WHERE id = ?',
      [delta, id],
    );
  }

  Future<void> deductInventory(String itemName, double amount) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE inventory SET quantity = quantity - ? WHERE name = ?',
      [amount, itemName],
    );
  }

  Future<List<Map<String, dynamic>>> getRecipesForService(String serviceName) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT r.id, r.service_name, r.inventory_id, r.qty, i.name as inventory_name, i.unit, i.quantity as stock
      FROM service_recipes r
      LEFT JOIN inventory i ON i.id = r.inventory_id
      WHERE r.service_name = ?
      ORDER BY r.id ASC
    ''', [serviceName]);
  }

  Future<void> setRecipeLine(String serviceName, int inventoryId, double qty) async {
    final db = await database;
    final existing = await db.query(
      'service_recipes',
      where: 'service_name = ? AND inventory_id = ?',
      whereArgs: [serviceName, inventoryId],
    );
    if (qty <= 0) {
      await db.delete(
        'service_recipes',
        where: 'service_name = ? AND inventory_id = ?',
        whereArgs: [serviceName, inventoryId],
      );
      return;
    }
    if (existing.isEmpty) {
      await db.insert('service_recipes', {
        'service_name': serviceName,
        'inventory_id': inventoryId,
        'qty': qty,
      });
    } else {
      await db.update(
        'service_recipes',
        {'qty': qty},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  Future<void> deleteRecipeLine(int recipeId) async {
    final db = await database;
    await db.delete('service_recipes', where: 'id = ?', whereArgs: [recipeId]);
  }

  /// Списать материалы по рецепту услуги (точное совпадение имени).
  Future<void> deductRecipeForService(String serviceName) async {
    final name = serviceName.trim();
    if (name.isEmpty) return;
    final recipes = await getRecipesForService(name);
    for (final r in recipes) {
      final invId = (r['inventory_id'] as num?)?.toInt();
      final qty = (r['qty'] as num?)?.toDouble() ?? 0;
      if (invId == null || qty <= 0) continue;
      await adjustInventoryQuantity(invId, -qty);
    }
  }

  Future<List<Map<String, dynamic>>> getAllServices() async {
    final db = await database;
    return await db.query('services', orderBy: 'id ASC');
  }

  Future<void> updateServicePrice(String name, String field, double price) async {
    final db = await database;
    await db.update('services', {field: price}, where: 'name = ?', whereArgs: [name]);
  }

  Future<List<Map<String, dynamic>>> getCustomWorks() async {
    final db = await database;
    return await db.query('custom_works', orderBy: 'name ASC');
  }

  Future<void> addCustomWork(String name, String category, double price) async {
    final db = await database;
    await db.insert('custom_works', {'name': name, 'category': category, 'price': price}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> updateOrderFullDetails(int orderId, String status, String clientNotes, String clientVisibleNotes, String masterNotes, String paymentMethod) async {
    final db = await database;
    await db.update('orders', {
      'status': status, 
      'client_notes': clientNotes, 
      'client_visible_notes': clientVisibleNotes, 
      'master_notes': masterNotes, 
      'payment_method': paymentMethod
    }, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateOrderClientNotes(int orderId, String clientNotes) async {
    final db = await database;
    await db.update('orders', {'client_notes': clientNotes}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateOrderClientVisibleNotes(int orderId, String notes) async {
    final db = await database;
    await db.update('orders', {'client_visible_notes': notes}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateOrderMasterNotes(int orderId, String notes) async {
    final db = await database;
    await db.update('orders', {'master_notes': notes}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateOrderPaymentMethod(int orderId, String method) async {
    final db = await database;
    await db.update('orders', {'payment_method': method}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> reassignOrderCar(int orderId, int carId) async {
    final db = await database;
    await db.update('orders', {'car_id': carId}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateOrderMaster(int orderId, int? masterId) async {
    final db = await database;
    await db.update('orders', {'master_id': masterId}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<List<Map<String, dynamic>>> getClientCarsForDropdown(String phone) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT cars.id, cars.make_model, cars.plate, cars.vin, cars.category FROM cars 
      JOIN clients ON cars.client_id = clients.id 
      WHERE clients.phone = ? ORDER BY cars.id DESC
    ''', [phone]);
  }

  Future<List<Map<String, dynamic>>> getServicesStats() async {
    final db = await database;
    List<Map> items = await db.query('order_items', columns: ['name']);
    Map<String, int> stats = {};
    for (var item in items) {
      String name = (item['name'] ?? "").toString().trim();
      if (name.isEmpty) continue;
      stats[name] = (stats[name] ?? 0) + 1;
    }
    var sortedKeys = stats.keys.toList()..sort((k1, k2) => stats[k2]!.compareTo(stats[k1]!));
    return sortedKeys.take(5).map((k) => {"name": k, "count": stats[k]}).toList();
  }

  /// Топ услуг по сумме выручки (price в order_items).
  Future<List<Map<String, dynamic>>> getTopServicesByRevenue({int limit = 5}) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT name, COUNT(*) as count, COALESCE(SUM(price), 0) as revenue
      FROM order_items
      WHERE name IS NOT NULL AND TRIM(name) != ''
      GROUP BY name
      ORDER BY revenue DESC
      LIMIT ?
    ''', [limit]);
  }

  // --- БАГ-РЕПОРТЫ ---
  Future<int> addBugReport({
    required String place,
    required String situation,
    required String details,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String().substring(0, 19);
    return await db.insert('bug_reports', {
      'place': place,
      'situation': situation,
      'details': details,
      'status': 'open',
      'fix_note': '',
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<List<Map<String, dynamic>>> getBugReports() async {
    final db = await database;
    return await db.query('bug_reports', orderBy: "CASE status WHEN 'open' THEN 0 ELSE 1 END, id DESC");
  }

  Future<int> countOpenBugReports() async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM bug_reports WHERE status = 'open'",
    );
    return (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<void> updateBugReport(
    int id, {
    String? status,
    String? fixNote,
  }) async {
    final db = await database;
    final data = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String().substring(0, 19),
    };
    if (status != null) data['status'] = status;
    if (fixNote != null) data['fix_note'] = fixNote;
    await db.update('bug_reports', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteBugReport(int id) async {
    final db = await database;
    await db.delete('bug_reports', where: 'id = ?', whereArgs: [id]);
  }
}