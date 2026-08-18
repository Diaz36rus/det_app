import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'app_version.dart';
import 'package:sqflite/sqflite.dart';

import 'sync/remote_database.dart';
import 'sync/sync_config.dart';
import 'cash_catalog.dart';
import 'crm/cloud_db_bridge.dart';
import 'inventory_catalog.dart';
import 'wrap_catalog.dart';

// --- НАЧАЛО БЛОКА: КОНСТАНТЫ ---
List<String> STATUSES = [
  "Предварительная запись", "Принят в работу", "Мойка", "Химчистка", "Полировка",
  "Оклейка", "Интерьер", "Оборудование", "Подготовка к выдаче", "Выдан"
];

/// Статус при создании заказа: если начало в будущем — предварительная запись.
String resolveInitialOrderStatus(String? startTime) {
  if (startTime == null || startTime.trim().isEmpty) {
    return "Предварительная запись";
  }
  try {
    final n = startTime.replaceFirst('T', ' ').split('.').first.trim();
    final iso = n.contains(' ') ? n.replaceFirst(' ', 'T') : n;
    final dt = DateTime.parse(iso);
    if (dt.isAfter(DateTime.now())) return "Предварительная запись";
  } catch (_) {
    return "Предварительная запись";
  }
  return "Принят в работу";
}

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

/// Шапка пакета тонировки.
bool isTintPackageHeader(String? name) => (name ?? '').trim() == 'Тонировка';

/// Шапка зонального пакета (оклейка или тонировка).
bool isZonePackageHeader(String? name) =>
    isWrapPackageHeader(name) || isTintPackageHeader(name);

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

/// Позиция состава пакета тонировки (в т.ч. из калькулятора: «Тонировка · зона · плёнка»).
bool isTintPackageLine({String? category, String? name}) {
  final n = (name ?? '').trim();
  if (n.isEmpty || isTintPackageHeader(n)) return false;
  if (n.startsWith('Тонировка ·') || n.startsWith('Тонировка ')) return true;
  if ((category ?? '').trim() == 'Тонировка') return true;
  return false;
}

bool isZonePackageLine({String? category, String? name}) =>
    isWrapPackageLine(category: category, name: name) ||
    isTintPackageLine(category: category, name: name);

/// Категория прайса → тип пакета.
String? zonePackageKindForCategory(String? category) {
  final c = (category ?? '').trim();
  if (c == 'Оклейка (Пленка)') return 'wrap';
  if (c == 'Тонировка') return 'tint';
  return null;
}

String zonePackageHeaderName(String kind) => kind == 'tint' ? 'Тонировка' : 'Оклейка';
String zonePackageWorkshop(String kind) => 'Оклейка';
String zonePackageCategory(String kind) =>
    kind == 'tint' ? 'Тонировка' : 'Оклейка (Пленка)';
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
  // Оклейка: популярные + Перед / Борт / Зад (см. wrap_catalog.dart)
  ...wrapServicesTreeEntries(),
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

  /// Ревизия данных: +1 после мутаций (локально или с LAN-клиента).
  /// Экраны слушают через [DbRefreshMixin] / addListener.
  static final ValueNotifier<int> dataRevision = ValueNotifier<int>(0);

  static void bumpDataRevision() {
    void bump() {
      dataRevision.value = dataRevision.value + 1;
    }

    // Сразу — чтобы лист дефектов / карточка услышали LAN-insert без ожидания кадра.
    bump();
    // И через кадр — подстраховка, если слушатель был в середине build.
    final binding = SchedulerBinding.instance;
    binding.scheduleFrameCallback((_) => bump());
    binding.ensureVisualUpdate();
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<void> _closeDb() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// Локальный файл detailing.db (режим хост / обычный).
  Future<void> reopenAsLocal() async {
    await _closeDb();
    _database = await _openLocal();
  }

  /// Клиент: все запросы на хост по LAN.
  Future<void> reopenAsClient({required String url, required String token}) async {
    await _closeDb();
    _database = await RemoteDatabase.connect(baseUrl: url, token: token);
  }

  /// Полный сброс: закрыть соединение, удалить файл БД, создать заново + дефолтные данные.
  /// Бэкапы в det_app_backups не трогает. Только для локального режима.
  Future<void> resetDatabase() async {
    final cfg = await SyncConfig.load();
    if (cfg.isClient) {
      throw StateError('Сброс БД недоступен в режиме клиента (данные на хосте).');
    }
    await _closeDb();
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, "detailing.db");
    await deleteDatabase(path);
    await initDefaultData();
  }

  Future<Database> _initDatabase() async {
    final cfg = await SyncConfig.load();
    if (cfg.isClient && cfg.normalizedBaseUrl.isNotEmpty) {
      try {
        return await RemoteDatabase.connect(
          baseUrl: cfg.normalizedBaseUrl,
          token: cfg.token,
        );
      } catch (e) {
        // Старт без хоста — локальная копия, чтобы UI открылся.
        debugPrint('Client connect failed, fallback local: $e');
      }
    }
    return _openLocal();
  }

  Future<Database> _openLocal() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, "detailing.db");
    return await openDatabase(
      path,
      version: AppVersion.dbSchema,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onDowngrade: (db, oldVersion, newVersion) async {
        throw StateError(
          'База данных новее приложения (схема $oldVersion, приложение $newVersion). '
          'Установите обновление или восстановите бэкап из Documents\\det_app_backups.',
        );
      },
    );
  }

  Future<void> _ensureColumn(Database db, String table, String column, String typeSql) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final names = info.map((r) => r['name']?.toString()).toSet();
    if (!names.contains(column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $typeSql;');
    }
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
      tech_wash_start TEXT,
      tech_wash_end TEXT,
      discount_percent REAL DEFAULT 0,
      discount_fixed REAL DEFAULT 0,
      promo_code TEXT DEFAULT '',
      handover_ready INTEGER DEFAULT 0,
      handover_works INTEGER DEFAULT 0,
      handover_payment INTEGER DEFAULT 0,
      handover_keys INTEGER DEFAULT 0,
      handover_inspect INTEGER DEFAULT 0,
      handover_notified INTEGER DEFAULT 0
    )''');
    await db.execute('''CREATE TABLE masters (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, role TEXT DEFAULT 'Универсал')''');
    await db.execute('''CREATE TABLE order_events (id INTEGER PRIMARY KEY AUTOINCREMENT, order_id INTEGER NOT NULL, event_text TEXT, created_at TEXT)''');
    await db.execute('''CREATE TABLE order_defects (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL,
      workshop TEXT DEFAULT '',
      description TEXT DEFAULT '',
      created_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE order_defect_photos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      defect_id INTEGER NOT NULL,
      photo_b64 TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE wrap_films (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      inventory_id INTEGER
    )''');
    await db.execute('''CREATE TABLE order_wrap_films (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL,
      film_id INTEGER NOT NULL,
      roll_id INTEGER,
      meters REAL DEFAULT 0
    )''');
    await db.execute('''CREATE TABLE payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL,
      amount REAL,
      method TEXT,
      created_at TEXT,
      shift_id INTEGER,
      register_id INTEGER
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
      register_id INTEGER,
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
    await db.execute('''CREATE TABLE cash_registers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      money_type TEXT NOT NULL DEFAULT 'Наличные',
      is_active INTEGER DEFAULT 1,
      sort_order INTEGER DEFAULT 0,
      created_at TEXT DEFAULT ''
    )''');
    await db.execute('''CREATE TABLE cash_shift_balances (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      shift_id INTEGER NOT NULL,
      register_id INTEGER NOT NULL,
      opening REAL DEFAULT 0,
      expected REAL,
      fact REAL,
      difference REAL,
      UNIQUE(shift_id, register_id)
    )''');
    await _seedCashRegisters(db);
    await db.execute('''CREATE TABLE custom_works (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, category TEXT DEFAULT 'Прочее', price REAL DEFAULT 0)''');
    await db.execute('''CREATE TABLE services (id INTEGER PRIMARY KEY AUTOINCREMENT, category TEXT NOT NULL, name TEXT NOT NULL UNIQUE, price1 REAL DEFAULT 0, price2 REAL DEFAULT 0, price3 REAL DEFAULT 0, price4 REAL DEFAULT 0, fixed_price REAL DEFAULT 0)''');
    await db.execute('''CREATE TABLE inventory (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      quantity REAL DEFAULT 0,
      unit TEXT DEFAULT 'шт',
      min_qty REAL DEFAULT 0,
      category TEXT DEFAULT 'Прочее',
      meters_per_roll REAL DEFAULT 0,
      last_brand TEXT DEFAULT ''
    )''');
    await db.execute('''CREATE TABLE service_recipes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      service_name TEXT NOT NULL,
      inventory_id INTEGER NOT NULL,
      qty REAL NOT NULL DEFAULT 1
    )''');
    await db.execute('''CREATE TABLE inventory_brands (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE
    )''');
    await db.execute('''CREATE TABLE inventory_moves (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      inventory_id INTEGER NOT NULL,
      roll_id INTEGER,
      delta REAL NOT NULL,
      balance_after REAL,
      reason TEXT NOT NULL,
      order_id INTEGER,
      order_item_id INTEGER,
      cash_flow_id INTEGER,
      note TEXT DEFAULT '',
      brand TEXT DEFAULT '',
      created_at TEXT NOT NULL
    )''');
    for (final b in InventoryBrands.popular) {
      await db.insert('inventory_brands', {'name': b}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await db.execute('''CREATE TABLE film_rolls (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      inventory_id INTEGER NOT NULL,
      roll_number TEXT NOT NULL,
      meters_initial REAL NOT NULL DEFAULT 0,
      meters_left REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      UNIQUE(inventory_id, roll_number)
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
      parent_id INTEGER,
      comment TEXT DEFAULT '',
      work_started_at TEXT,
      work_ended_at TEXT
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
    await db.execute('''CREATE TABLE app_settings (
      key TEXT PRIMARY KEY,
      value TEXT DEFAULT ''
    )''');
    await db.execute('''CREATE TABLE app_error_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      level TEXT DEFAULT 'error',
      source TEXT DEFAULT '',
      message TEXT NOT NULL,
      stack TEXT DEFAULT '',
      created_at TEXT NOT NULL
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
    // --- Версия 16: tech_wash на orders (раньше был только в upgrade v6, не в onCreate) ---
    if (oldVersion < 16) {
      await _ensureColumn(db, 'orders', 'tech_wash_start', 'TEXT');
      await _ensureColumn(db, 'orders', 'tech_wash_end', 'TEXT');
    }
    // --- Версия 17: настройки sync + лог ошибок для диагностики ---
    if (oldVersion < 17) {
      await db.execute('''CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT DEFAULT ''
      )''');
      await db.execute('''CREATE TABLE IF NOT EXISTS app_error_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        level TEXT DEFAULT 'error',
        source TEXT DEFAULT '',
        message TEXT NOT NULL,
        stack TEXT DEFAULT '',
        created_at TEXT NOT NULL
      )''');
    }
    // --- Версия 18: комментарий к каждой работе ---
    if (oldVersion < 18) {
      await _ensureColumn(db, 'order_items', 'comment', "TEXT DEFAULT ''");
    }
    // --- Версия 19: оклейка Перед/Борт/Зад вместо зон риска ---
    if (oldVersion < 19) {
      await _migrateWrapCatalogV19(db);
    }
    // --- Версия 20: несколько касс в смене ---
    if (oldVersion < 20) {
      await _migrateCashRegistersV20(db);
    }
    // --- Версия 21: дефекты с фото, материалы оклейки и чек-лист выдачи ---
    if (oldVersion < 21) {
      await db.execute('''CREATE TABLE IF NOT EXISTS order_defects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        workshop TEXT DEFAULT '',
        description TEXT DEFAULT '',
        created_at TEXT NOT NULL
      )''');
      await db.execute('''CREATE TABLE IF NOT EXISTS order_defect_photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        defect_id INTEGER NOT NULL,
        photo_b64 TEXT NOT NULL,
        created_at TEXT NOT NULL
      )''');
      await db.execute('''CREATE TABLE IF NOT EXISTS wrap_films (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )''');
      await db.execute('''CREATE TABLE IF NOT EXISTS order_wrap_films (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        film_id INTEGER NOT NULL,
        meters REAL DEFAULT 0
      )''');
      for (final column in const [
        'handover_ready',
        'handover_works',
        'handover_payment',
        'handover_keys',
        'handover_inspect',
        'handover_notified',
      ]) {
        await _ensureColumn(db, 'orders', column, 'INTEGER DEFAULT 0');
      }
    }
    // --- Версия 22: мин. остаток на складе ---
    if (oldVersion < 22) {
      await _ensureColumn(db, 'inventory', 'min_qty', 'REAL DEFAULT 0');
    }
    // --- Версия 23: резерв колонок на order_items (UI таймера снят) ---
    if (oldVersion < 23) {
      await _ensureColumn(db, 'order_items', 'work_started_at', 'TEXT');
      await _ensureColumn(db, 'order_items', 'work_ended_at', 'TEXT');
    }
    // --- Версия 24: склад — категории, журнал, рулоны плёнки ---
    if (oldVersion < 24) {
      await _ensureColumn(db, 'inventory', 'category', "TEXT DEFAULT 'Прочее'");
      await _ensureColumn(db, 'inventory', 'meters_per_roll', 'REAL DEFAULT 0');
      await _ensureColumn(db, 'wrap_films', 'inventory_id', 'INTEGER');
      await _ensureColumn(db, 'order_wrap_films', 'roll_id', 'INTEGER');
      await db.execute('''CREATE TABLE IF NOT EXISTS inventory_moves (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        inventory_id INTEGER NOT NULL,
        roll_id INTEGER,
        delta REAL NOT NULL,
        balance_after REAL,
        reason TEXT NOT NULL,
        order_id INTEGER,
        order_item_id INTEGER,
        cash_flow_id INTEGER,
        note TEXT DEFAULT '',
        created_at TEXT NOT NULL
      )''');
      await db.execute('''CREATE TABLE IF NOT EXISTS film_rolls (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        inventory_id INTEGER NOT NULL,
        roll_number TEXT NOT NULL,
        meters_initial REAL NOT NULL DEFAULT 0,
        meters_left REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        UNIQUE(inventory_id, roll_number)
      )''');
      // Старые wrap_films → позиции склада «Плёнка оклейка».
      final films = await db.query('wrap_films');
      for (final f in films) {
        final filmId = (f['id'] as num).toInt();
        final name = f['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        final existingInv = (f['inventory_id'] as num?)?.toInt();
        if (existingInv != null && existingInv > 0) continue;
        final invId = await db.insert('inventory', {
          'name': name,
          'quantity': 0,
          'unit': FilmUnits.meters,
          'min_qty': 0,
          'category': InventoryCategories.filmWrap,
          'meters_per_roll': 0,
        });
        await db.update('wrap_films', {'inventory_id': invId}, where: 'id = ?', whereArgs: [filmId]);
      }
    }
    // --- Версия 25: единица плёнки м.п. / рул. ---
    if (oldVersion < 25) {
      await db.execute('''
        UPDATE inventory
        SET unit = '${FilmUnits.meters}'
        WHERE category IN ('${InventoryCategories.filmWrap}', '${InventoryCategories.filmTint}')
          AND (
            unit IS NULL OR trim(unit) = '' OR lower(trim(unit)) IN ('м', 'м.', 'мп', 'м.п', 'м.п.', 'meter', 'meters')
          )
      ''');
      await db.execute('''
        UPDATE inventory
        SET unit = '${FilmUnits.rolls}'
        WHERE category IN ('${InventoryCategories.filmWrap}', '${InventoryCategories.filmTint}')
          AND lower(replace(trim(unit), ' ', '')) IN ('рул', 'рул.', 'рулон', 'рулоны', 'roll', 'rolls')
      ''');
      // Пересчитать quantity по выбранной единице.
      final films = await db.query(
        'inventory',
        columns: ['id'],
        where: "category IN (?, ?)",
        whereArgs: [InventoryCategories.filmWrap, InventoryCategories.filmTint],
      );
      for (final f in films) {
        final invId = (f['id'] as num).toInt();
        final unitRows = await db.query(
          'inventory',
          columns: ['unit'],
          where: 'id = ?',
          whereArgs: [invId],
          limit: 1,
        );
        final unit = FilmUnits.normalize(unitRows.first['unit']?.toString());
        final double total;
        if (FilmUnits.isRolls(unit)) {
          final cnt = await db.rawQuery(
            'SELECT COUNT(*) AS c FROM film_rolls WHERE inventory_id = ? AND meters_left > 0.001',
            [invId],
          );
          total = ((cnt.first['c'] as num?)?.toInt() ?? 0).toDouble();
        } else {
          final sum = await db.rawQuery(
            'SELECT COALESCE(SUM(meters_left), 0) AS s FROM film_rolls WHERE inventory_id = ?',
            [invId],
          );
          total = (sum.first['s'] as num?)?.toDouble() ?? 0;
        }
        await db.update(
          'inventory',
          {'quantity': total, 'unit': unit},
          where: 'id = ?',
          whereArgs: [invId],
        );
      }
    }
    // --- Версия 26: бренды расходников (остаток по типу; плёнки без бренда) ---
    if (oldVersion < 26) {
      await db.execute('''CREATE TABLE IF NOT EXISTS inventory_brands (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )''');
      await _ensureColumn(db, 'inventory', 'last_brand', "TEXT DEFAULT ''");
      await _ensureColumn(db, 'inventory_moves', 'brand', "TEXT DEFAULT ''");
      for (final b in InventoryBrands.popular) {
        await db.insert(
          'inventory_brands',
          {'name': b},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  static Future<void> _seedCashRegisters(Database db) async {
    final now = DateTime.now().toIso8601String().substring(0, 16);
    for (final r in CashRegisterSeeds.defaults) {
      await db.insert('cash_registers', {
        'name': r['name'],
        'money_type': r['money_type'],
        'is_active': 1,
        'sort_order': r['sort_order'],
        'created_at': now,
      });
    }
  }

  Future<void> _migrateCashRegistersV20(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS cash_registers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      money_type TEXT NOT NULL DEFAULT 'Наличные',
      is_active INTEGER DEFAULT 1,
      sort_order INTEGER DEFAULT 0,
      created_at TEXT DEFAULT ''
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS cash_shift_balances (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      shift_id INTEGER NOT NULL,
      register_id INTEGER NOT NULL,
      opening REAL DEFAULT 0,
      expected REAL,
      fact REAL,
      difference REAL,
      UNIQUE(shift_id, register_id)
    )''');
    await _ensureColumn(db, 'cash_flow', 'register_id', 'INTEGER');
    await _ensureColumn(db, 'payments', 'register_id', 'INTEGER');

    final existing = await db.query('cash_registers', limit: 1);
    if (existing.isEmpty) {
      await _seedCashRegisters(db);
    }

    // Проставляем register_id по money_type / method для старых строк.
    final regs = await db.query('cash_registers', where: 'is_active = 1');
    final byType = <String, int>{};
    for (final r in regs) {
      final t = r['money_type']?.toString() ?? '';
      byType.putIfAbsent(t, () => (r['id'] as num).toInt());
    }
    for (final entry in byType.entries) {
      await db.rawUpdate(
        'UPDATE cash_flow SET register_id = ? WHERE register_id IS NULL AND method = ?',
        [entry.value, entry.key],
      );
      await db.rawUpdate(
        'UPDATE payments SET register_id = ? WHERE register_id IS NULL AND method = ?',
        [entry.value, entry.key],
      );
    }

    // Открытая смена: стартовые балансы (нал → opening_cash смены).
    final open = await db.query('cash_shifts', where: "status = 'open'", limit: 1);
    if (open.isNotEmpty) {
      final shiftId = (open.first['id'] as num).toInt();
      final openingCash = (open.first['opening_cash'] as num?)?.toDouble() ?? 0;
      for (final r in regs) {
        final rid = (r['id'] as num).toInt();
        final isCash = r['money_type']?.toString() == CashMethods.cash;
        await db.insert(
          'cash_shift_balances',
          {
            'shift_id': shiftId,
            'register_id': rid,
            'opening': isCash ? openingCash : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  /// Удаляет устаревшие «ЗР» и добивает новый каталог оклейки.
  static Future<void> _migrateWrapCatalogV19(Database db) async {
    await db.delete(
      'services',
      where: "category = ? AND name LIKE ?",
      whereArgs: ['Оклейка (Пленка)', '% · ЗР · %'],
    );
    // Старые «частые» без зоны — тоже пересоздаём из каталога (ignore dup).
    for (final s in wrapServicesTreeEntries()) {
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
          'comment': '',
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
        where: "category = ? AND name LIKE ?",
        whereArgs: ['Оклейка (Пленка)', '% · ЗР · %'],
      );
      await db.delete(
        'services',
        where: 'name = ?',
        whereArgs: ['Оклейка · Борт · Накладка / молдинг двери'],
      );
      for (final name in [
        'Оклейка · Перед · Кожух дворников',
        'Оклейка · Борт · Зеркало (нижняя крышка)',
      ]) {
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
    if (CloudDbBridge.active) return CloudDbBridge.instance.getAllOrders();
    final db = await database;
    return await db.rawQuery('''
      SELECT orders.*, clients.name as client_name, clients.phone as client_phone, cars.make_model, cars.plate, m.name as master_name,
        (SELECT COUNT(*) FROM order_items WHERE order_items.order_id = orders.id AND NOT (order_items.parent_id IS NULL AND order_items.name IN ('Оклейка', 'Тонировка'))) as works_total,
        (SELECT COUNT(*) FROM order_items WHERE order_items.order_id = orders.id AND order_items.is_done = 1 AND NOT (order_items.parent_id IS NULL AND order_items.name IN ('Оклейка', 'Тонировка'))) as works_done
      FROM orders JOIN clients ON orders.client_id = clients.id JOIN cars ON orders.car_id = cars.id
      LEFT JOIN masters m ON orders.master_id = m.id
      WHERE orders.is_completed = 0 ORDER BY orders.id DESC
    ''');
  }

  Future<Map<String, dynamic>?> getOrderById(int orderId) async {
    if (CloudDbBridge.active) return CloudDbBridge.instance.getOrderById(orderId);
    final db = await database;
    List<Map> res = await db.rawQuery('''
      SELECT orders.*, clients.name as client_name, clients.phone as client_phone, clients.is_vip,
             cars.make_model, cars.plate, cars.vin, cars.category,
             m.name as master_name,
             (SELECT COUNT(*) FROM order_items WHERE order_items.order_id = orders.id AND NOT (order_items.parent_id IS NULL AND order_items.name IN ('Оклейка', 'Тонировка'))) as works_total,
             (SELECT COUNT(*) FROM order_items WHERE order_items.order_id = orders.id AND order_items.is_done = 1 AND NOT (order_items.parent_id IS NULL AND order_items.name IN ('Оклейка', 'Тонировка'))) as works_done
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
    if (CloudDbBridge.active) return CloudDbBridge.instance.getCompletedOrders(query);
    final db = await database;
    final q = query.trim();
    if (q.isEmpty) {
      return await db.rawQuery('''
        SELECT orders.*, clients.name as client_name, clients.phone as client_phone,
               cars.make_model, cars.plate, cars.vin, m.name as master_name,
               (SELECT COUNT(*) FROM order_items WHERE order_items.order_id = orders.id AND NOT (order_items.parent_id IS NULL AND order_items.name IN ('Оклейка', 'Тонировка'))) as works_total,
               (SELECT COUNT(*) FROM order_items WHERE order_items.order_id = orders.id AND order_items.is_done = 1 AND NOT (order_items.parent_id IS NULL AND order_items.name IN ('Оклейка', 'Тонировка'))) as works_done
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
             (SELECT COUNT(*) FROM order_items WHERE order_items.order_id = orders.id AND NOT (order_items.parent_id IS NULL AND order_items.name IN ('Оклейка', 'Тонировка'))) as works_total,
             (SELECT COUNT(*) FROM order_items WHERE order_items.order_id = orders.id AND order_items.is_done = 1 AND NOT (order_items.parent_id IS NULL AND order_items.name IN ('Оклейка', 'Тонировка'))) as works_done
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
    if (CloudDbBridge.active) return CloudDbBridge.instance.getOrdersForCalendar(dateStr);
    final db = await database;
    // День через substr после T→пробел. Длинные заказы: start_day ≤ день ≤ end_day.
    return await db.rawQuery('''
      SELECT orders.id, orders.status, orders.price, orders.paid_amount,
             orders.start_time, orders.end_time, orders.due_date, orders.tech_wash_start, orders.tech_wash_end,
             clients.name as client_name, cars.make_model, cars.plate
      FROM orders
      JOIN clients ON orders.client_id = clients.id
      JOIN cars ON orders.car_id = cars.id
      WHERE orders.is_completed = 0 AND (
        (
          orders.start_time IS NOT NULL AND trim(orders.start_time) != ''
          AND substr(replace(orders.start_time, 'T', ' '), 1, 10) <= ?
          AND substr(replace(coalesce(nullif(trim(orders.end_time), ''), orders.start_time), 'T', ' '), 1, 10) >= ?
        )
        OR (
          orders.due_date IS NOT NULL AND trim(orders.due_date) != ''
          AND substr(replace(orders.due_date, 'T', ' '), 1, 10) = ?
        )
        OR (
          orders.end_date IS NOT NULL AND trim(orders.end_date) != ''
          AND substr(replace(orders.end_date, 'T', ' '), 1, 10) = ?
        )
        OR (
          orders.tech_wash_start IS NOT NULL AND trim(orders.tech_wash_start) != ''
          AND substr(replace(orders.tech_wash_start, 'T', ' '), 1, 10) <= ?
          AND substr(replace(coalesce(nullif(trim(orders.tech_wash_end), ''), orders.tech_wash_start), 'T', ' '), 1, 10) >= ?
        )
      )
      ORDER BY orders.start_time ASC
    ''', [dateStr, dateStr, dateStr, dateStr, dateStr, dateStr]);
  }

  /// Работы с заданным временем на выбранный день (для режима «Детальное время»).
  /// Если у позиции нет своего времени — берём график заказа (start_time/end_time).
  /// Пустой workshop → [workshopForService] по имени (иначе позиция пропадала из колонок).
  /// Длинные слоты показываются во все дни пересечения.
  Future<List<Map<String, dynamic>>> getOrderItemsForCalendar(String dateStr) async {
    if (CloudDbBridge.active) return CloudDbBridge.instance.getOrderItemsForCalendar(dateStr);
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT order_items.id as item_id, order_items.order_id, order_items.name as work_name,
             coalesce(nullif(trim(order_items.start_time), ''), orders.start_time) as start_time,
             coalesce(nullif(trim(order_items.end_time), ''), orders.end_time) as end_time,
             order_items.workshop,
             order_items.is_done, order_items.parent_id,
             orders.status, orders.price, orders.paid_amount,
             clients.name as client_name, cars.make_model, cars.plate
      FROM order_items
      JOIN orders ON order_items.order_id = orders.id
      JOIN clients ON orders.client_id = clients.id
      JOIN cars ON orders.car_id = cars.id
      WHERE orders.is_completed = 0
        AND coalesce(nullif(trim(order_items.start_time), ''), orders.start_time) IS NOT NULL
        AND trim(coalesce(nullif(trim(order_items.start_time), ''), orders.start_time)) != ''
        AND substr(replace(coalesce(nullif(trim(order_items.start_time), ''), orders.start_time), 'T', ' '), 1, 10) <= ?
        AND substr(replace(
              coalesce(
                nullif(trim(coalesce(nullif(trim(order_items.end_time), ''), orders.end_time)), ''),
                coalesce(nullif(trim(order_items.start_time), ''), orders.start_time)
              ), 'T', ' '), 1, 10) >= ?
      ORDER BY start_time ASC
    ''', [dateStr, dateStr]);
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      final m = Map<String, dynamic>.from(r);
      final ws = m['workshop']?.toString().trim() ?? '';
      if (ws.isEmpty) {
        m['workshop'] = workshopForService(name: m['work_name']?.toString()) ?? '';
      }
      if ((m['workshop']?.toString() ?? '').trim().isEmpty) continue;
      out.add(m);
    }
    return out;
  }

  Future<int> addClient(String name, String phone, {int isVip = 0}) async {
    if (CloudDbBridge.active) {
      final id = await CloudDbBridge.instance.addClient(name, phone, isVip: isVip);
      bumpDataRevision();
      return id;
    }
    final db = await database;
    return await db.insert('clients', {'name': name, 'phone': phone, 'is_vip': isVip});
  }

  Future<int> addCar(int clientId, String makeModel, String plate, {String vin = "", String category = "1"}) async {
    if (CloudDbBridge.active) {
      final id = await CloudDbBridge.instance.addCar(clientId, makeModel, plate, vin: vin, category: category);
      bumpDataRevision();
      return id;
    }
    final db = await database;
    return await db.insert('cars', {'client_id': clientId, 'make_model': makeModel, 'plate': plate, 'vin': vin, 'category': category});
  }

  Future<void> updateCar(int carId, {String? makeModel, String? plate, String? vin, String? category}) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.updateCar(carId, makeModel: makeModel, plate: plate, vin: vin, category: category);
      return;
    }
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
      {String? status, String dueDate = "", String startTime = ""}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String().substring(0, 16);
    final resolved = status ?? resolveInitialOrderStatus(startTime);
    return await db.insert('orders', {
      'client_id': clientId, 'car_id': carId, 'status': resolved, 'price': price, 
      'notes': notes, 'created_at': now, 'due_date': dueDate, 'start_time': startTime
    });
  }

  /// Создаёт заказ и сразу строки order_items, затем синхронизирует notes/price.
  /// [status] null → автоматически: будущее start_time → «Предварительная запись».
  Future<int> addOrderWithItems(
    int clientId,
    int carId,
    List<Map<String, dynamic>> items, {
    String? status,
    String dueDate = "",
    String startTime = "",
    String endTime = "",
    String endDate = "",
  }) async {
    if (CloudDbBridge.active) {
      final id = await CloudDbBridge.instance.addOrderWithItems(
        clientId,
        carId,
        items,
        status: status,
        dueDate: dueDate,
        startTime: startTime,
        endTime: endTime,
        endDate: endDate,
      );
      bumpDataRevision();
      return id;
    }
    final db = await database;
    final now = DateTime.now().toIso8601String().substring(0, 16);
    String notes = items.map((i) => i['name'] as String).join(", ");
    double price = items.fold(0.0, (sum, i) => sum + ((i['price'] as num?)?.toDouble() ?? 0));
    final resolvedStatus = status ?? resolveInitialOrderStatus(startTime);
    int orderId = await db.insert('orders', {
      'client_id': clientId,
      'car_id': carId,
      'status': resolvedStatus,
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
      // Копируем график заказа на позиции — иначе «Детальное время» в календаре пустое.
      await addOrderItem(
        orderId,
        name,
        price,
        sync: false,
        workshop: ws,
        category: cat,
        startTime: startTime.isNotEmpty ? startTime : null,
        endTime: endTime.isNotEmpty ? endTime : null,
      );
    }
    await syncOrderFromItems(orderId);
    bumpDataRevision();
    return orderId;
  }

  /// Денормализует notes и price заказа из order_items (+ скидка заказа).
  Future<void> syncOrderFromItems(int orderId) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.syncOrderFromItems(orderId);
      bumpDataRevision();
      return;
    }
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
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.updateOrderDiscount(
        orderId,
        discountPercent: discountPercent,
        discountFixed: discountFixed,
        promoCode: promoCode,
      );
      return;
    }
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

  /// 10 цифр номера без кода страны (7/8).
  static String phoneDigits10(String phone) {
    var digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('7')) digits = digits.substring(1);
    if (digits.startsWith('8') && digits.length >= 10) digits = digits.substring(1);
    if (digits.length > 10) digits = digits.substring(0, 10);
    return digits;
  }

  /// Совпадение по `+7…` или по 10 цифрам (разные форматы в БД / mobile-ввод).
  Future<Map<String, dynamic>?> getClientByPhone(String phone) async {
    if (CloudDbBridge.active) return CloudDbBridge.instance.getClientByPhone(phone);
    final db = await database;
    final digits = phoneDigits10(phone);
    final canon = digits.isEmpty ? phone.trim() : '+7$digits';

    var res = await db.query('clients', where: 'phone = ?', whereArgs: [canon]);
    if (res.isNotEmpty) return Map<String, dynamic>.from(res.first);

    final raw = phone.trim();
    if (raw.isNotEmpty && raw != canon) {
      res = await db.query('clients', where: 'phone = ?', whereArgs: [raw]);
      if (res.isNotEmpty) return Map<String, dynamic>.from(res.first);
    }

    if (digits.length < 10) return null;
    final all = await db.query('clients');
    for (final row in all) {
      if (phoneDigits10(row['phone']?.toString() ?? '') == digits) {
        return Map<String, dynamic>.from(row);
      }
    }
    return null;
  }

  Future<int?> getCarId(int clientId, String plate) async {
    if (CloudDbBridge.active) return CloudDbBridge.instance.getCarId(clientId, plate);
    final db = await database;
    List<Map> res = await db.query('cars', where: 'client_id = ? AND plate = ?', whereArgs: [clientId, plate]);
    return res.isNotEmpty ? res.first['id'] as int? : null;
  }

  /// Причины, почему нельзя поставить «Выдан». Пустой список = можно.
  Future<List<String>> validateIssueOrder(int orderId) async {
    if (CloudDbBridge.active) return [];
    final db = await database;
    // Подтянуть шапки пакетов по зонам (старые заказы могли «висеть» незакрытыми).
    final packageHeaders = await db.query(
      'order_items',
      columns: ['id'],
      where: "order_id = ? AND parent_id IS NULL AND name IN ('Оклейка', 'Тонировка')",
      whereArgs: [orderId],
    );
    for (final h in packageHeaders) {
      await syncZonePackageHeaderDone((h['id'] as num).toInt());
    }

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

    // Как в UI: шапки пакетов «Оклейка»/«Тонировка» не работы — смотрим зоны.
    // Шапка часто остаётся is_done=0, даже когда все зоны отмечены.
    final openWorks = await db.query(
      'order_items',
      columns: ['id', 'name', 'workshop', 'parent_id', 'is_done'],
      where: 'order_id = ? AND COALESCE(is_done, 0) = 0',
      whereArgs: [orderId],
      orderBy: 'id',
    );
    final incomplete = openWorks.where((w) {
      final name = w['name']?.toString();
      if (isZonePackageHeader(name) && w['parent_id'] == null) return false;
      return true;
    }).toList();
    if (incomplete.isNotEmpty) {
      final labels = incomplete.map((w) {
        final name = (w['name'] as String?)?.trim();
        final ws = (w['workshop'] as String?)?.trim();
        final base = (name == null || name.isEmpty) ? 'Без названия' : name;
        if (ws != null && ws.isNotEmpty) return '$base ($ws)';
        return base;
      }).toList();
      reasons.add(
        'Не выполнены работы (${labels.length}):\n'
        '${labels.map((n) => '— $n').join('\n')}',
      );
    }

    // Чек-лист выдачи обязателен целиком.
    const handoverLabels = <String, String>{
      'handover_notified': 'Клиент уведомлён о готовности',
      'handover_works': 'Работы проверены (QC)',
      'handover_inspect': 'Авто осмотрено с клиентом',
      'handover_payment': 'Оплата проверена / закрыта',
      'handover_keys': 'Ключи и документы переданы',
    };
    final handover = await getOrderHandover(orderId);
    final missingHandover = handoverLabels.entries
        .where((e) => (handover[e.key] as num?)?.toInt() != 1)
        .map((e) => e.value)
        .toList();
    if (missingHandover.isNotEmpty) {
      reasons.add(
        'Чек-лист выдачи не заполнен (${missingHandover.length}):\n'
        '${missingHandover.map((n) => '— $n').join('\n')}',
      );
    }

    return reasons;
  }

  /// Обновляет статус. Для «Выдан» сначала проверка долга и незакрытых работ.
  /// Возвращает `false`, если выдача запрещена (БД не менялась).
  Future<bool> updateStatus(int orderId, String newStatus) async {
    if (CloudDbBridge.active) {
      final ok = await CloudDbBridge.instance.updateStatus(orderId, newStatus);
      if (ok) bumpDataRevision();
      return ok;
    }
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
    bumpDataRevision();
    return true;
  }

    // --- УДАЛЕНИЕ ЗАКАЗА ---
  Future<void> deleteOrder(int orderId) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.deleteOrder(orderId);
      bumpDataRevision();
      return;
    }
    // Вернуть метры на рулоны и очистить order_wrap_films (дельта-учёт).
    await setOrderWrapFilms(orderId, const []);
    final db = await database;
    await db.delete('order_items', where: 'order_id = ?', whereArgs: [orderId]);
    await db.delete('order_events', where: 'order_id = ?', whereArgs: [orderId]);
    await db.delete('payments', where: 'order_id = ?', whereArgs: [orderId]);
    await db.delete('orders', where: 'id = ?', whereArgs: [orderId]);
    bumpDataRevision();
  }

  Future<void> setWorkshopTaskCompleted(int orderId, int isCompleted) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.setWorkshopTaskCompleted(orderId, isCompleted);
      bumpDataRevision();
      return;
    }
    final db = await database;
    await db.update('orders', {'is_workshop_completed': isCompleted}, where: 'id = ?', whereArgs: [orderId]);
  }

  // --- РАБОТЫ ЗАКАЗА (ORDER ITEMS) ---
  Future<List<Map<String, dynamic>>> getOrderItems(int orderId) async {
    if (CloudDbBridge.active) return CloudDbBridge.instance.getOrderItems(orderId);
    final db = await database;
    await _reattachOrphanZoneLines(db, orderId);
    final headers = await db.query(
      'order_items',
      columns: ['id'],
      where: "order_id = ? AND parent_id IS NULL AND name IN ('Оклейка', 'Тонировка')",
      whereArgs: [orderId],
    );
    for (final h in headers) {
      await syncZonePackageHeaderDone((h['id'] as num).toInt());
    }
    return await db.query('order_items', where: 'order_id = ?', whereArgs: [orderId]);
  }

  /// Сиротские зоны тонировки/оклейки без parent_id → в пакет.
  Future<void> _reattachOrphanZoneLines(Database db, int orderId) async {
    final items = await db.query('order_items', where: 'order_id = ?', whereArgs: [orderId]);
    Future<void> attach(String kind, bool Function(Map<String, dynamic>) isLine) async {
      final orphans = items.where((i) {
        if (!isLine(i)) return false;
        return i['parent_id'] == null && !isZonePackageHeader(i['name']?.toString());
      }).toList();
      if (orphans.isEmpty) return;
      final headerName = zonePackageHeaderName(kind);
      Map<String, dynamic>? header;
      for (final i in items) {
        if ((i['name']?.toString() ?? '') == headerName && i['parent_id'] == null) {
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
          await db.update('order_items', {'price': orphanSum}, where: 'id = ?', whereArgs: [headerId]);
        }
      } else {
        headerId = await db.insert('order_items', {
          'order_id': orderId,
          'name': headerName,
          'price': orphanSum,
          'master_ids': '',
          'is_done': 0,
          'workshop': zonePackageWorkshop(kind),
          'parent_id': null,
          'comment': '',
        });
      }
      for (final child in orphans) {
        await db.update(
          'order_items',
          {'parent_id': headerId, 'price': 0, 'workshop': zonePackageWorkshop(kind)},
          where: 'id = ?',
          whereArgs: [(child['id'] as num).toInt()],
        );
      }
      await syncZonePackageHeaderDone(headerId);
    }

    await attach('wrap', (i) => isWrapPackageLine(name: i['name']?.toString()));
    await attach('tint', (i) => isTintPackageLine(name: i['name']?.toString()));
  }

  /// Id шапки зонального пакета (создаёт при отсутствии). [kind]: wrap | tint
  Future<int> ensureZonePackage(int orderId, String kind) async {
    final db = await database;
    final headerName = zonePackageHeaderName(kind);
    final workshop = zonePackageWorkshop(kind);
    final existing = await db.query(
      'order_items',
      where: "order_id = ? AND name = ? AND parent_id IS NULL",
      whereArgs: [orderId, headerName],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return (existing.first['id'] as num).toInt();
    }
    return await db.insert('order_items', {
      'order_id': orderId,
      'name': headerName,
      'price': 0,
      'master_ids': '',
      'is_done': 0,
      'workshop': workshop,
      'parent_id': null,
      'comment': '',
    });
  }

  Future<int> ensureWrapPackage(int orderId) => ensureZonePackage(orderId, 'wrap');

  Future<int> ensureTintPackage(int orderId) => ensureZonePackage(orderId, 'tint');

  /// Синхронизирует состав пакета: зоны (имена) + сумма на шапке. Лишние зоны удаляет.
  Future<void> syncZonePackage({
    required int orderId,
    required String kind,
    required List<String> zoneNames,
    required double packagePrice,
  }) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.syncZonePackage(
        orderId: orderId,
        kind: kind,
        zoneNames: zoneNames,
        packagePrice: packagePrice,
      );
      bumpDataRevision();
      return;
    }
    final db = await database;
    final headerId = await ensureZonePackage(orderId, kind);
    final workshop = zonePackageWorkshop(kind);

    await db.update(
      'order_items',
      {'price': packagePrice, 'workshop': workshop},
      where: 'id = ?',
      whereArgs: [headerId],
    );

    final existing = await db.query(
      'order_items',
      where: 'parent_id = ?',
      whereArgs: [headerId],
    );
    final byName = <String, Map<String, dynamic>>{};
    for (final row in existing) {
      byName[(row['name'] ?? '').toString()] = row;
    }

    final wanted = zoneNames.map((n) => n.trim()).where((n) => n.isNotEmpty).toSet();

    for (final name in wanted) {
      if (byName.containsKey(name)) continue;
      await db.insert('order_items', {
        'order_id': orderId,
        'name': name,
        'price': 0,
        'master_ids': '',
        'is_done': 0,
        'workshop': workshop,
        'parent_id': headerId,
        'comment': '',
      });
    }

    for (final entry in byName.entries) {
      if (wanted.contains(entry.key)) continue;
      await db.delete('order_items', where: 'id = ?', whereArgs: [entry.value['id']]);
    }

    // Пустой состав — удаляем шапку.
    if (wanted.isEmpty) {
      await db.delete('order_items', where: 'id = ?', whereArgs: [headerId]);
    }

    await syncOrderFromItems(orderId);
  }

  Future<int> addOrderItem(
    int orderId,
    String name,
    double price, {
    bool sync = true,
    String? workshop,
    String? category,
    String? startTime,
    String? endTime,
  }) async {
    if (CloudDbBridge.active) {
      final id = await CloudDbBridge.instance.addOrderItem(
        orderId, name, price,
        sync: sync, workshop: workshop, category: category,
        startTime: startTime, endTime: endTime,
      );
      bumpDataRevision();
      return id;
    }
    final db = await database;
    final ws = workshop ?? workshopForService(category: category, name: name);

    // Зоны оклейки/тонировки → состав пакета (цена только на шапке).
    final asWrap = isWrapPackageLine(category: category, name: name);
    final asTint = isTintPackageLine(category: category, name: name);
    if (asWrap || asTint) {
      final kind = asTint ? 'tint' : 'wrap';
      final parentId = await ensureZonePackage(orderId, kind);
      final headerRows = await db.query(
        'order_items',
        columns: ['start_time', 'end_time', 'master_ids'],
        where: 'id = ?',
        whereArgs: [parentId],
        limit: 1,
      );
      final header = headerRows.isNotEmpty ? headerRows.first : null;
      // Не дублируем уже существующую зону с тем же именем.
      final dup = await db.query(
        'order_items',
        columns: ['id'],
        where: 'parent_id = ? AND name = ?',
        whereArgs: [parentId, name],
        limit: 1,
      );
      if (dup.isNotEmpty) {
        if (sync) await syncOrderFromItems(orderId);
        return (dup.first['id'] as num).toInt();
      }
      final id = await db.insert('order_items', {
        'order_id': orderId,
        'name': name,
        'price': 0,
        'master_ids': header?['master_ids'] ?? '',
        'is_done': 0,
        'workshop': ws ?? zonePackageWorkshop(kind),
        'parent_id': parentId,
        'start_time': header?['start_time'] ?? startTime,
        'end_time': header?['end_time'] ?? endTime,
        'comment': '',
      });
      // Если передали цену при добавлении зоны (калькулятор) — копим на шапку только
      // когда у шапки ещё 0; иначе цену пакета задают явно через syncZonePackage.
      if (price > 0) {
        final hPrice = await db.query(
          'order_items',
          columns: ['price'],
          where: 'id = ?',
          whereArgs: [parentId],
          limit: 1,
        );
        final cur = hPrice.isEmpty ? 0.0 : ((hPrice.first['price'] as num?)?.toDouble() ?? 0);
        if (cur <= 0) {
          await db.update('order_items', {'price': price}, where: 'id = ?', whereArgs: [parentId]);
        } else {
          await db.update(
            'order_items',
            {'price': cur + price},
            where: 'id = ?',
            whereArgs: [parentId],
          );
        }
      }
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
      'comment': '',
      if (startTime != null && startTime.isNotEmpty) 'start_time': startTime,
      if (endTime != null && endTime.isNotEmpty) 'end_time': endTime,
    });
    if (sync) await syncOrderFromItems(orderId);
    return id;
  }

  Future<void> updateOrderItemComment(int itemId, String comment) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.updateOrderItemComment(itemId, comment);
      return;
    }
    final db = await database;
    await db.update(
      'order_items',
      {'comment': comment},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> updateOrderItemPrice(int itemId, double price) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.updateOrderItemPrice(itemId, price);
      bumpDataRevision();
      return;
    }
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

  /// Возвращает предупреждения о нехватке склада (списание не блокируется).
  Future<List<String>> updateOrderItemDone(int itemId, bool isDone) async {
    if (CloudDbBridge.active) {
      final w = await CloudDbBridge.instance.updateOrderItemDone(itemId, isDone);
      bumpDataRevision();
      return w;
    }
    final db = await database;
    final rows = await db.query(
      'order_items',
      columns: ['name', 'is_done', 'parent_id', 'order_id'],
      where: 'id = ?',
      whereArgs: [itemId],
    );
    final wasDone = rows.isNotEmpty && ((rows.first['is_done'] as num?)?.toInt() ?? 0) == 1;
    await db.update('order_items', {'is_done': isDone ? 1 : 0}, where: 'id = ?', whereArgs: [itemId]);
    final warnings = <String>[];
    if (rows.isNotEmpty) {
      final name = rows.first['name']?.toString() ?? '';
      final orderId = (rows.first['order_id'] as num?)?.toInt();
      // Списание / возврат склада при смене «выполнено».
      if (isDone && !wasDone) {
        warnings.addAll(
          await deductRecipeForService(name, orderId: orderId, orderItemId: itemId),
        );
      } else if (!isDone && wasDone) {
        await restoreRecipeForService(name, orderId: orderId, orderItemId: itemId);
      }
      final parentId = (rows.first['parent_id'] as num?)?.toInt();
      if (parentId != null) {
        await syncZonePackageHeaderDone(parentId);
      }
    }
    return warnings;
  }

  /// Шапка пакета выполнена ⇔ все зоны выполнены.
  Future<void> syncZonePackageHeaderDone(int headerId) async {
    final db = await database;
    final headerRows = await db.query(
      'order_items',
      columns: ['name', 'parent_id'],
      where: 'id = ?',
      whereArgs: [headerId],
      limit: 1,
    );
    if (headerRows.isEmpty) return;
    final header = headerRows.first;
    if (header['parent_id'] != null) return;
    if (!isZonePackageHeader(header['name']?.toString())) return;

    final children = await db.query(
      'order_items',
      columns: ['is_done'],
      where: 'parent_id = ?',
      whereArgs: [headerId],
    );
    if (children.isEmpty) return;
    final allDone = children.every((c) => ((c['is_done'] as num?)?.toInt() ?? 0) == 1);
    await db.update(
      'order_items',
      {'is_done': allDone ? 1 : 0},
      where: 'id = ?',
      whereArgs: [headerId],
    );
  }

  Future<void> deleteOrderItem(int itemId) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.deleteOrderItem(itemId);
      bumpDataRevision();
      return;
    }
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

    if (isZonePackageHeader(name)) {
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
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.updateOrderItemMasters(itemId, masterIds);
      return;
    }
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
  Future<List<String>> updateWrapPackageDone(int headerId, bool isDone) async {
    final db = await database;
    final children = await db.query(
      'order_items',
      columns: ['id'],
      where: 'parent_id = ?',
      whereArgs: [headerId],
    );
    final warnings = <String>[];
    warnings.addAll(await updateOrderItemDone(headerId, isDone));
    for (final c in children) {
      warnings.addAll(await updateOrderItemDone((c['id'] as num).toInt(), isDone));
    }
    return warnings;
  }

  /// Сохраняет время и цех одной услуги (сразу в базу).
  Future<void> updateOrderItemSchedule(int itemId, String? startTime, String? endTime, String? workshop) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.updateOrderItemSchedule(itemId, startTime, endTime, workshop);
      bumpDataRevision();
      return;
    }
    final db = await database;
    await db.update('order_items', {
      'start_time': startTime,
      'end_time': endTime,
      'workshop': workshop,
    }, where: 'id = ?', whereArgs: [itemId]);
  }

  Future<void> updateOrderPrice(int orderId, double price) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.updateOrderPrice(orderId, price);
      bumpDataRevision();
      return;
    }
    final db = await database;
    await db.update('orders', {'price': price}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateOrderNotes(int orderId, String notes) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.updateOrderNotes(orderId, notes);
      bumpDataRevision();
      return;
    }
    final db = await database;
    await db.update('orders', {'notes': notes}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateOrderSchedule(int orderId, String dueDate, String startTime, String endTime, String endDate) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.updateOrderSchedule(orderId, dueDate, startTime, endTime, endDate);
      bumpDataRevision();
      return;
    }
    final db = await database;
    final prev = await db.query(
      'orders',
      columns: ['start_time', 'end_time'],
      where: 'id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    final oldStart = prev.isEmpty ? '' : (prev.first['start_time']?.toString() ?? '');
    await db.update(
      'orders',
      {'due_date': dueDate, 'start_time': startTime, 'end_time': endTime, 'end_date': endDate},
      where: 'id = ?',
      whereArgs: [orderId],
    );
    // Позиции без своего графика или с тем же, что был у заказа — едут вместе.
    if (oldStart.trim().isNotEmpty) {
      final alt = oldStart.contains('T') ? oldStart.replaceFirst('T', ' ') : oldStart.replaceFirst(' ', 'T');
      await db.rawUpdate(
        '''
        UPDATE order_items
        SET start_time = ?, end_time = ?
        WHERE order_id = ?
          AND (
            trim(coalesce(start_time, '')) = ''
            OR start_time = ?
            OR start_time = ?
          )
        ''',
        [startTime, endTime, orderId, oldStart, alt],
      );
    } else {
      await db.rawUpdate(
        '''
        UPDATE order_items
        SET start_time = ?, end_time = ?
        WHERE order_id = ? AND trim(coalesce(start_time, '')) = ''
        ''',
        [startTime, endTime, orderId],
      );
    }
    bumpDataRevision();
  }

  Future<void> setTechWash(int orderId, String? startDate, String? endDate) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.setTechWash(orderId, startDate, endDate);
      bumpDataRevision();
      return;
    }
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
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.addOrderEvent(orderId, text);
      return;
    }
    final db = await database;
    final now = DateTime.now().toIso8601String().substring(0, 16);
    await db.insert('order_events', {'order_id': orderId, 'event_text': text, 'created_at': now});
  }

  Future<List<Map<String, dynamic>>> getOrderEvents(int orderId) async {
    if (CloudDbBridge.active) return CloudDbBridge.instance.getOrderEvents(orderId);
    final db = await database;
    return await db.query('order_events', where: 'order_id = ?', whereArgs: [orderId], orderBy: 'id DESC');
  }

  Future<void> _ensureDefectTables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS order_defects (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL,
      workshop TEXT DEFAULT '',
      description TEXT DEFAULT '',
      created_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS order_defect_photos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      defect_id INTEGER NOT NULL,
      photo_b64 TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''');
  }

  Future<int> addOrderDefect({
    required int orderId,
    String workshop = '',
    String description = '',
    required List<String> photosB64,
  }) async {
    final db = await database;
    await _ensureDefectTables(db);
    final now = DateTime.now().toIso8601String();
    // Без одной большой транзакции по LAN: фото уходят отдельными insert
    // (RemoteDatabase.transaction — просто последовательные вызовы).
    final id = await db.insert('order_defects', {
      'order_id': orderId,
      'workshop': workshop.trim(),
      'description': description.trim(),
      'created_at': now,
    });
    for (final photo in photosB64.where((p) => p.isNotEmpty)) {
      await db.insert('order_defect_photos', {
        'defect_id': id,
        'photo_b64': photo,
        'created_at': now,
      });
    }
    final where = workshop.trim().isEmpty ? '' : ' · цех «${workshop.trim()}»';
    final details = description.trim().isEmpty ? 'без описания' : description.trim();
    final photoNote = photosB64.isEmpty ? '' : ' (${photosB64.length} фото)';
    await addOrderEvent(orderId, 'Дефект$where: $details$photoNote');
    bumpDataRevision();
    return id;
  }

  Future<List<Map<String, dynamic>>> getOrderDefects(int orderId) async {
    final db = await database;
    await _ensureDefectTables(db);
    final defects = await db.query(
      'order_defects',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'id DESC',
    );
    final result = <Map<String, dynamic>>[];
    for (final defect in defects) {
      final row = Map<String, dynamic>.from(defect);
      row['photos'] = await getDefectPhotos((row['id'] as num).toInt());
      result.add(row);
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getDefectPhotos(int defectId) async {
    final db = await database;
    return db.query(
      'order_defect_photos',
      where: 'defect_id = ?',
      whereArgs: [defectId],
      orderBy: 'id ASC',
    );
  }

  Future<void> deleteOrderDefect(int defectId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('order_defect_photos', where: 'defect_id = ?', whereArgs: [defectId]);
      await txn.delete('order_defects', where: 'id = ?', whereArgs: [defectId]);
    });
    bumpDataRevision();
  }

  Future<Map<String, dynamic>> getOrderHandover(int orderId) async {
    if (CloudDbBridge.active) return CloudDbBridge.instance.getOrderHandover(orderId);
    final db = await database;
    final rows = await db.query(
      'orders',
      columns: const [
        'handover_ready', 'handover_works', 'handover_payment',
        'handover_keys', 'handover_inspect', 'handover_notified',
      ],
      where: 'id = ?',
      whereArgs: [orderId],
    );
    return rows.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(rows.first);
  }

  Future<void> saveOrderHandover(int orderId, Map<String, dynamic> values) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.saveOrderHandover(orderId, values);
      bumpDataRevision();
      return;
    }
    final allowed = {
      'handover_ready', 'handover_works', 'handover_payment',
      'handover_keys', 'handover_inspect', 'handover_notified',
    };
    final data = Map<String, dynamic>.fromEntries(
      values.entries.where((entry) => allowed.contains(entry.key)),
    );
    if (data.isEmpty) return;
    final db = await database;
    await db.update('orders', data, where: 'id = ?', whereArgs: [orderId]);
    bumpDataRevision();
  }

  /// Складские позиции плёнки → записи каталога цеха (wrap_films).
  Future<void> syncWrapFilmsFromInventory() async {
    final db = await database;
    final films = await db.query(
      'inventory',
      where: 'category IN (?, ?)',
      whereArgs: [InventoryCategories.filmWrap, InventoryCategories.filmTint],
    );
    var changed = false;
    for (final inv in films) {
      final invId = (inv['id'] as num).toInt();
      final name = inv['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final byInv = await db.query(
        'wrap_films',
        where: 'inventory_id = ?',
        whereArgs: [invId],
        limit: 1,
      );
      if (byInv.isNotEmpty) continue;
      final byName = await db.rawQuery(
        'SELECT id, inventory_id FROM wrap_films WHERE lower(trim(name)) = lower(trim(?)) LIMIT 1',
        [name],
      );
      if (byName.isNotEmpty) {
        final filmId = (byName.first['id'] as num).toInt();
        final linked = (byName.first['inventory_id'] as num?)?.toInt();
        if (linked == null || linked <= 0) {
          await db.update('wrap_films', {'inventory_id': invId}, where: 'id = ?', whereArgs: [filmId]);
          changed = true;
        }
      } else {
        await db.insert('wrap_films', {'name': name, 'inventory_id': invId});
        changed = true;
      }
    }
    if (changed) bumpDataRevision();
  }

  /// Каталог плёнок для цеха. [categories] — фильтр склада («Плёнка оклейка» / «Плёнка тонировка»).
  Future<List<Map<String, dynamic>>> listWrapFilms({List<String>? categories}) async {
    await syncWrapFilmsFromInventory();
    final db = await database;
    final cats = (categories ?? const <String>[])
        .where((c) => InventoryCategories.isFilm(c))
        .toList();
    if (cats.isEmpty) {
      return db.rawQuery('''
        SELECT wrap_films.*, inventory.quantity AS stock_meters, inventory.meters_per_roll,
               inventory.category AS inventory_category
        FROM wrap_films
        LEFT JOIN inventory ON inventory.id = wrap_films.inventory_id
        ORDER BY inventory.category COLLATE NOCASE, wrap_films.name COLLATE NOCASE
      ''');
    }
    final placeholders = List.filled(cats.length, '?').join(', ');
    return db.rawQuery('''
      SELECT wrap_films.*, inventory.quantity AS stock_meters, inventory.meters_per_roll,
             inventory.category AS inventory_category
      FROM wrap_films
      INNER JOIN inventory ON inventory.id = wrap_films.inventory_id
      WHERE inventory.category IN ($placeholders)
      ORDER BY inventory.category COLLATE NOCASE, wrap_films.name COLLATE NOCASE
    ''', cats);
  }

  /// Новая плёнка в каталоге цеха + позиция на складе.
  Future<int> addWrapFilm(
    String name, {
    String category = InventoryCategories.filmWrap,
    double metersPerRoll = 0,
    String unit = FilmUnits.meters,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', 'Название плёнки не может быть пустым');
    final filmUnit = FilmUnits.normalize(unit);
    final db = await database;
    final existing = await db.query('wrap_films', where: 'name = ?', whereArgs: [trimmed], limit: 1);
    if (existing.isNotEmpty) {
      final filmId = (existing.first['id'] as num).toInt();
      final invId = (existing.first['inventory_id'] as num?)?.toInt();
      if (invId == null || invId <= 0) {
        final newInv = await addInventoryItem(
          trimmed,
          0,
          filmUnit,
          category: category,
          metersPerRoll: metersPerRoll,
        );
        await db.update('wrap_films', {'inventory_id': newInv}, where: 'id = ?', whereArgs: [filmId]);
        bumpDataRevision();
      }
      return filmId;
    }
    final invId = await addInventoryItem(
      trimmed,
      0,
      filmUnit,
      category: category,
      metersPerRoll: metersPerRoll,
    );
    final id = await db.insert('wrap_films', {'name': trimmed, 'inventory_id': invId});
    bumpDataRevision();
    return id;
  }

  Future<List<Map<String, dynamic>>> getOrderWrapFilms(int orderId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT order_wrap_films.*, wrap_films.name AS film_name,
             film_rolls.roll_number AS roll_number,
             film_rolls.meters_left AS roll_meters_left,
             wrap_films.inventory_id AS inventory_id
      FROM order_wrap_films
      JOIN wrap_films ON wrap_films.id = order_wrap_films.film_id
      LEFT JOIN film_rolls ON film_rolls.id = order_wrap_films.roll_id
      WHERE order_wrap_films.order_id = ?
      ORDER BY order_wrap_films.id ASC
    ''', [orderId]);
  }

  Map<int, double> _usageByRoll(Iterable<Map<String, dynamic>> rows) {
    final map = <int, double>{};
    for (final r in rows) {
      final rollId = (r['roll_id'] as num?)?.toInt() ??
          (r['rollId'] is num ? (r['rollId'] as num).toInt() : int.tryParse('${r['rollId']}'));
      final metersRaw = r['meters'];
      final meters = metersRaw is num
          ? metersRaw.toDouble()
          : double.tryParse('$metersRaw'.replaceAll(',', '.')) ?? 0;
      if (rollId == null || meters <= 0) continue;
      map[rollId] = (map[rollId] ?? 0) + meters;
    }
    return map;
  }

  /// Сохранить расход плёнок: на склад уходит только дельта по рулонам (без спама в журнале).
  Future<List<String>> setOrderWrapFilms(int orderId, List<Map<String, dynamic>> films) async {
    final db = await database;
    final warnings = <String>[];
    final oldRows = await db.query('order_wrap_films', where: 'order_id = ?', whereArgs: [orderId]);
    final oldUsage = _usageByRoll(oldRows);
    final newUsage = _usageByRoll(films);

    final rollIds = {...oldUsage.keys, ...newUsage.keys};
    for (final rollId in rollIds) {
      final before = oldUsage[rollId] ?? 0;
      final after = newUsage[rollId] ?? 0;
      final stockDelta = before - after; // расход вырос → остаток рулона падает
      if (stockDelta.abs() < 0.0001) continue;
      final w = await adjustFilmRollMeters(
        rollId,
        stockDelta,
        reason: stockDelta > 0 ? InventoryMoveReasons.filmRestore : InventoryMoveReasons.filmDeduct,
        orderId: orderId,
        note: 'Заказ #$orderId',
        logMove: false,
      );
      if (w != null) warnings.add(w);
    }

    await db.delete('order_wrap_films', where: 'order_id = ?', whereArgs: [orderId]);
    for (final film in films) {
      final rawId = film['filmId'] ?? film['film_id'];
      final id = (rawId is num) ? rawId.toInt() : int.tryParse('$rawId');
      if (id == null) continue;
      final metersRaw = film['meters'];
      final meters = metersRaw is num
          ? metersRaw.toDouble()
          : double.tryParse('$metersRaw'.replaceAll(',', '.')) ?? 0;
      final rawRoll = film['rollId'] ?? film['roll_id'];
      final rollId = (rawRoll is num) ? rawRoll.toInt() : int.tryParse('$rawRoll');
      await db.insert('order_wrap_films', {
        'order_id': orderId,
        'film_id': id,
        'roll_id': rollId,
        'meters': meters,
      });
    }
    bumpDataRevision();
    return warnings;
  }

  Future<List<Map<String, dynamic>>> getOrdersByPlate(String plate) async {
    final db = await database;
    final normalized = plate.trim();
    if (normalized.isEmpty) return [];
    return db.rawQuery('''
      SELECT orders.*, clients.name AS client_name, cars.make_model, cars.plate
      FROM orders
      JOIN cars ON cars.id = orders.car_id
      JOIN clients ON clients.id = orders.client_id
      WHERE upper(replace(cars.plate, ' ', '')) = upper(replace(?, ' ', ''))
      ORDER BY coalesce(nullif(orders.start_time, ''), orders.created_at) DESC, orders.id DESC
      LIMIT 20
    ''', [normalized]);
  }

  Future<List<Map<String, dynamic>>> findOverlappingOrders({
    required String startTime,
    required String endTime,
    int? excludeOrderId,
  }) async {
    final db = await database;
    if (startTime.trim().isEmpty || endTime.trim().isEmpty) return [];
    final exclusion = excludeOrderId == null ? '' : ' AND orders.id != ?';
    final args = <Object>[endTime.replaceFirst('T', ' '), startTime.replaceFirst('T', ' ')];
    if (excludeOrderId != null) args.add(excludeOrderId);
    return db.rawQuery('''
      SELECT orders.*, clients.name AS client_name, cars.make_model, cars.plate
      FROM orders
      JOIN clients ON clients.id = orders.client_id
      JOIN cars ON cars.id = orders.car_id
      WHERE trim(coalesce(orders.start_time, '')) != ''
        AND trim(coalesce(orders.end_time, '')) != ''
        AND replace(orders.start_time, 'T', ' ') < ?
        AND replace(orders.end_time, 'T', ' ') > ?
        $exclusion
      ORDER BY orders.start_time ASC
    ''', args);
  }

  Future<List<Map<String, dynamic>>> getMasterDayStats(String dayYyyyMmDd) async {
    final db = await database;
    return db.rawQuery('''
      SELECT m.id, m.name, COUNT(DISTINCT o.id) AS orders_count
      FROM masters m
      LEFT JOIN orders o ON (
        o.status IN ('Мойка', 'Химчистка', 'Полировка', 'Оклейка', 'Интерьер', 'Оборудование', 'Кузовные работы', 'Выдан')
        AND substr(replace(coalesce(nullif(o.end_time, ''), o.start_time), 'T', ' '), 1, 10) = ?
        AND instr(',' || replace(coalesce(o.master_ids, ''), ' ', '') || ',', ',' || m.id || ',') > 0
      )
      GROUP BY m.id, m.name
      ORDER BY orders_count DESC, m.name COLLATE NOCASE
    ''', [dayYyyyMmDd]);
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

  /// Новая оплата только в открытую смену (иначе касса «теряет» проводки).
  Future<void> addPayment(int orderId, double amount, String method, {int? shiftId, int? registerId}) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.addPayment(orderId, amount, method, shiftId: shiftId, registerId: registerId);
      bumpDataRevision();
      return;
    }
    final db = await database;
    final now = DateTime.now().toIso8601String().substring(0, 16);
    final sid = shiftId ?? (await getCurrentShift())?['id'] as int?;
    if (sid == null) {
      throw StateError('Смена не открыта — оплату провести нельзя');
    }
    final rid = registerId ?? await resolveRegisterIdForMethod(method);
    await db.insert('payments', {
      'order_id': orderId,
      'amount': amount,
      'method': method,
      'created_at': now,
      'shift_id': sid,
      'register_id': rid,
    });
    await db.rawQuery('UPDATE orders SET paid_amount = paid_amount + ? WHERE id = ?', [amount, orderId]);
    bumpDataRevision();
  }

  Future<List<Map<String, dynamic>>> getOrderPayments(int orderId) async {
    if (CloudDbBridge.active) return CloudDbBridge.instance.getOrderPayments(orderId);
    final db = await database;
    return db.query(
      'payments',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'id DESC',
    );
  }

  /// Отмена оплаты: удаляет платёж и уменьшает paid_amount (не ниже 0).
  /// Возвращает данные платежа или null, если не найден.
  Future<Map<String, dynamic>?> voidPayment(int paymentId) async {
    if (CloudDbBridge.active) return CloudDbBridge.instance.voidPayment(paymentId);
    final db = await database;
    final rows = await db.query('payments', where: 'id = ?', whereArgs: [paymentId], limit: 1);
    if (rows.isEmpty) return null;
    final pay = Map<String, dynamic>.from(rows.first);
    final orderId = (pay['order_id'] as num).toInt();
    final amount = (pay['amount'] as num?)?.toDouble() ?? 0;
    await db.delete('payments', where: 'id = ?', whereArgs: [paymentId]);
    final orderRows = await db.query(
      'orders',
      columns: ['paid_amount'],
      where: 'id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    if (orderRows.isNotEmpty) {
      final paid = (orderRows.first['paid_amount'] as num?)?.toDouble() ?? 0;
      final next = paid - amount;
      await db.update(
        'orders',
        {'paid_amount': next < 0 ? 0.0 : next},
        where: 'id = ?',
        whereArgs: [orderId],
      );
    }
    bumpDataRevision();
    return pay;
  }

  /// Правка оплаты: сумма / метод / касса + пересчёт paid_amount заказа.
  Future<bool> updatePayment(
    int paymentId, {
    required double amount,
    required String method,
    int? registerId,
  }) async {
    if (amount <= 0) return false;
    final db = await database;
    final rows = await db.query('payments', where: 'id = ?', whereArgs: [paymentId], limit: 1);
    if (rows.isEmpty) return false;
    final pay = rows.first;
    final orderId = (pay['order_id'] as num).toInt();
    final oldAmount = (pay['amount'] as num?)?.toDouble() ?? 0;
    final rid = registerId ?? await resolveRegisterIdForMethod(method);
    await db.update(
      'payments',
      {
        'amount': amount,
        'method': method,
        'register_id': rid,
      },
      where: 'id = ?',
      whereArgs: [paymentId],
    );
    final orderRows = await db.query(
      'orders',
      columns: ['paid_amount'],
      where: 'id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    if (orderRows.isNotEmpty) {
      final paid = (orderRows.first['paid_amount'] as num?)?.toDouble() ?? 0;
      var next = paid - oldAmount + amount;
      if (next < 0) next = 0;
      await db.update(
        'orders',
        {'paid_amount': next},
        where: 'id = ?',
        whereArgs: [orderId],
      );
    }
    bumpDataRevision();
    return true;
  }

  // --- КЛИЕНТЫ И АВТО ---
  Future<List<Map<String, dynamic>>> getClientsList() async {
    if (CloudDbBridge.active) return CloudDbBridge.instance.getClientsList();
    final db = await database;
    return await db.query('clients', orderBy: 'id DESC');
  }

  Future<List<Map<String, dynamic>>> searchClients(String query) async {
    if (CloudDbBridge.active) return CloudDbBridge.instance.searchClients(query);
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
    if (CloudDbBridge.active) return CloudDbBridge.instance.searchGlobal(query);
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
    if (CloudDbBridge.active) return CloudDbBridge.instance.getClientCars(clientId);
    final db = await database;
    return await db.query('cars', where: 'client_id = ?', whereArgs: [clientId]);
  }

  Future<List<Map<String, dynamic>>> getClientHistory(int clientId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT orders.id, orders.created_at, orders.notes, orders.price, orders.paid_amount,
             orders.status, orders.is_completed,
             (orders.price - orders.paid_amount) as debt,
             cars.make_model, cars.plate
      FROM orders
      JOIN cars ON orders.car_id = cars.id
      WHERE orders.client_id = ?
      ORDER BY orders.id DESC
    ''', [clientId]);
  }

  /// Позиции последнего заказа клиента/авто в форме корзины «Новый заказ».
  /// Дети пакетов сворачиваются в wrapZones; график/мастера не копируются.
  Future<List<Map<String, dynamic>>> getLastOrderCartLines({
    required int clientId,
    int? carId,
  }) async {
    final db = await database;
    final where = carId != null ? 'client_id = ? AND car_id = ?' : 'client_id = ?';
    final args = carId != null ? <Object>[clientId, carId] : <Object>[clientId];
    final orders = await db.query(
      'orders',
      columns: ['id'],
      where: where,
      whereArgs: args,
      orderBy: 'id DESC',
      limit: 1,
    );
    if (orders.isEmpty) return [];
    final orderId = (orders.first['id'] as num).toInt();
    final items = await getOrderItems(orderId);
    final result = <Map<String, dynamic>>[];
    for (final item in items) {
      if (item['parent_id'] != null) continue;
      final name = item['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final price = (item['price'] as num?)?.toDouble() ?? 0;
      var ws = item['workshop']?.toString().trim() ?? '';
      if (ws.isEmpty) ws = workshopForService(name: name) ?? '';

      if (isWrapPackageHeader(name) || isTintPackageHeader(name)) {
        final headerId = (item['id'] as num?)?.toInt();
        final kids = items
            .where((x) => (x['parent_id'] as num?)?.toInt() == headerId)
            .toList();
        if (kids.isNotEmpty) {
          final zones = kids.map((k) => k['name'].toString()).toList();
          final kidSum = kids.fold<double>(
            0,
            (s, k) => s + ((k['price'] as num?)?.toDouble() ?? 0),
          );
          result.add({
            'name': zones.length == 1 ? zones.first : '$name · ${zones.length} поз.',
            'price': price > 0 ? price : kidSum,
            'category': isWrapPackageHeader(name) ? 'Оклейка (Пленка)' : 'Тонировка',
            'workshop': ws.isNotEmpty
                ? ws
                : (isWrapPackageHeader(name) ? 'Оклейка' : 'Тонировка'),
            'wrapZones': zones,
          });
          continue;
        }
      }

      result.add({
        'name': name,
        'price': price,
        'category': '',
        'workshop': ws,
      });
    }
    return result;
  }

  Future<void> updateClientVip(int clientId, int isVip) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.updateClientVip(clientId, isVip);
      bumpDataRevision();
      return;
    }
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
    if (CloudDbBridge.active) return CloudDbBridge.instance.getAllMastersFull();
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
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.addMaster(name, role);
      bumpDataRevision();
      return;
    }
    final db = await database;
    await db.insert('masters', {'name': name, 'role': role});
  }

  Future<void> updateMaster(int id, {String? name, String? role}) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.updateMaster(id, name: name, role: role);
      bumpDataRevision();
      return;
    }
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
    if (CloudDbBridge.active) {
      final n = await CloudDbBridge.instance.assignMastersToWorkshop(orderId, workshop, masterIds);
      bumpDataRevision();
      return n;
    }
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
    if (CloudDbBridge.active) {
      return CloudDbBridge.instance.getWorkshopMasterNames(orderId, workshop);
    }
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
    if (CloudDbBridge.active) return CloudDbBridge.instance.getRolesList();
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
    if (CloudDbBridge.active) return CloudDbBridge.instance.getCurrentShift();
    final db = await database;
    final rows = await db.query(
      'cash_shifts',
      where: "status = 'open'",
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> getCashRegisters({bool activeOnly = true}) async {
    if (CloudDbBridge.active) return CloudDbBridge.instance.getCashRegisters();
    final db = await database;
    return await db.query(
      'cash_registers',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'sort_order ASC, id ASC',
    );
  }

  Future<int> addCashRegister(String name, String moneyType, {int sortOrder = 100}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String().substring(0, 16);
    final id = await db.insert('cash_registers', {
      'name': name.trim(),
      'money_type': moneyType,
      'is_active': 1,
      'sort_order': sortOrder,
      'created_at': now,
    });
    // Если смена открыта — сразу заводим нулевой остаток.
    final shift = await getCurrentShift();
    if (shift != null) {
      await db.insert(
        'cash_shift_balances',
        {
          'shift_id': (shift['id'] as num).toInt(),
          'register_id': id,
          'opening': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    return id;
  }

  Future<void> setCashRegisterActive(int registerId, bool active) async {
    final db = await database;
    await db.update(
      'cash_registers',
      {'is_active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: [registerId],
    );
  }

  Future<int?> resolveRegisterIdForMethod(String method) async {
    if (CloudDbBridge.active) return CloudDbBridge.instance.resolveRegisterIdForMethod(method);
    final db = await database;
    final rows = await db.query(
      'cash_registers',
      where: 'is_active = 1 AND money_type = ?',
      whereArgs: [method],
      orderBy: 'sort_order ASC, id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['id'] as num).toInt();
  }

  /// Открыть смену. [openings] — registerId → стартовый остаток.
  Future<int> openCashShift(double openingCash, {String note = '', Map<int, double>? openings}) async {
    if (CloudDbBridge.active) {
      final id = await CloudDbBridge.instance.openCashShift(openingCash, note: note, openings: openings);
      bumpDataRevision();
      return id;
    }
    final existing = await getCurrentShift();
    if (existing != null) return (existing['id'] as num).toInt();
    final db = await database;
    final now = DateTime.now().toIso8601String().substring(0, 16);
    final registers = await getCashRegisters();
    // openingCash — сумма по наличным кассам (передаёт UI). Не перезаписывать
    // первым registerId: при нескольких наличных кассах это ломало остаток смены.
    var cashOpening = openingCash;
    if (openings != null) {
      var sum = 0.0;
      var anyCash = false;
      for (final r in registers) {
        if (r['money_type']?.toString() != CashMethods.cash) continue;
        final rid = (r['id'] as num).toInt();
        if (!openings.containsKey(rid)) continue;
        sum += openings[rid]!;
        anyCash = true;
      }
      if (anyCash) cashOpening = sum;
    }
    final shiftId = await db.insert('cash_shifts', {
      'opened_at': now,
      'opening_cash': cashOpening,
      'note': note,
      'status': 'open',
    });
    for (final r in registers) {
      final rid = (r['id'] as num).toInt();
      final open = openings?[rid] ??
          (r['money_type']?.toString() == CashMethods.cash ? cashOpening : 0.0);
      await db.insert('cash_shift_balances', {
        'shift_id': shiftId,
        'register_id': rid,
        'opening': open,
      });
    }
    bumpDataRevision();
    return shiftId;
  }

  /// Ожидаемый остаток по кассе: opening + оплаты + приходы − расходы.
  Future<double> getRegisterExpected(int shiftId, int registerId) async {
    final db = await database;
    final bal = await db.query(
      'cash_shift_balances',
      where: 'shift_id = ? AND register_id = ?',
      whereArgs: [shiftId, registerId],
      limit: 1,
    );
    final opening = bal.isEmpty ? 0.0 : ((bal.first['opening'] as num?)?.toDouble() ?? 0);

    final payRows = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total FROM payments
      WHERE shift_id = ? AND register_id = ?
    ''', [shiftId, registerId]);
    final payments = (payRows.first['total'] as num?)?.toDouble() ?? 0;

    final flowRows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'Приход' THEN amount ELSE 0 END), 0) as income,
        COALESCE(SUM(CASE WHEN type = 'Расход' THEN amount ELSE 0 END), 0) as expense
      FROM cash_flow
      WHERE shift_id = ? AND register_id = ?
    ''', [shiftId, registerId]);
    final income = (flowRows.first['income'] as num?)?.toDouble() ?? 0;
    final expense = (flowRows.first['expense'] as num?)?.toDouble() ?? 0;

    return opening + payments + income - expense;
  }

  /// Карточки касс для смены: name, money_type, opening, expected (+ fact/Δ после закрытия).
  Future<List<Map<String, dynamic>>> getShiftRegisterSnapshots(int shiftId) async {
    if (CloudDbBridge.active) return CloudDbBridge.instance.getShiftRegisterSnapshots(shiftId);
    final registers = await getCashRegisters();
    final out = <Map<String, dynamic>>[];
    final db = await database;
    for (final r in registers) {
      final rid = (r['id'] as num).toInt();
      final expected = await getRegisterExpected(shiftId, rid);
      final bal = await db.query(
        'cash_shift_balances',
        where: 'shift_id = ? AND register_id = ?',
        whereArgs: [shiftId, rid],
        limit: 1,
      );
      final opening = bal.isEmpty ? 0.0 : ((bal.first['opening'] as num?)?.toDouble() ?? 0);
      final fact = bal.isEmpty ? null : (bal.first['fact'] as num?)?.toDouble();
      final diff = bal.isEmpty ? null : (bal.first['difference'] as num?)?.toDouble();
      final storedExpected = bal.isEmpty ? null : (bal.first['expected'] as num?)?.toDouble();
      out.add({
        ...r,
        'opening': opening,
        'expected': storedExpected ?? expected,
        if (fact != null) 'fact': fact,
        if (diff != null) 'difference': diff,
      });
    }
    return out;
  }

  /// Ожидаемый нал в ящике (касса с типом «Наличные», иначе legacy-формула).
  Future<double> getShiftExpectedCash(int shiftId) async {
    final snaps = await getShiftRegisterSnapshots(shiftId);
    double cashTotal = 0;
    var foundCash = false;
    for (final s in snaps) {
      if (s['money_type']?.toString() == CashMethods.cash) {
        cashTotal += (s['expected'] as num?)?.toDouble() ?? 0;
        foundCash = true;
      }
    }
    if (foundCash) return cashTotal;

    // Fallback без касс
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

  /// [facts] — registerId → фактический остаток при закрытии.
  Future<void> closeCashShift(
    int shiftId,
    double factCash, {
    String note = '',
    Map<int, double>? facts,
  }) async {
    final db = await database;
    final snaps = await getShiftRegisterSnapshots(shiftId);
    final now = DateTime.now().toIso8601String().substring(0, 16);

    double totalExpected = 0;
    double totalFact = 0;
    for (final s in snaps) {
      final rid = (s['id'] as num).toInt();
      final expected = (s['expected'] as num?)?.toDouble() ?? 0;
      final fact = facts?[rid] ??
          (s['money_type']?.toString() == CashMethods.cash ? factCash : expected);
      totalExpected += expected;
      totalFact += fact;
      await db.update(
        'cash_shift_balances',
        {
          'expected': expected,
          'fact': fact,
          'difference': fact - expected,
        },
        where: 'shift_id = ? AND register_id = ?',
        whereArgs: [shiftId, rid],
      );
    }

    final cashExpected = await getShiftExpectedCash(shiftId);
    await db.update(
      'cash_shifts',
      {
        'closed_at': now,
        'closing_cash': facts == null ? factCash : totalFact,
        'expected_cash': facts == null ? cashExpected : totalExpected,
        'fact_cash': facts == null ? factCash : totalFact,
        'difference': (facts == null ? factCash : totalFact) -
            (facts == null ? cashExpected : totalExpected),
        'note': note,
        'status': 'closed',
      },
      where: 'id = ?',
      whereArgs: [shiftId],
    );
    bumpDataRevision();
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
    int? registerId,
    String counterparty = '',
    int? masterId,
    int? inventoryId,
    double inventoryQty = 0,
    int? orderId,
    String templateKey = '',
    String note = '',
    String inventoryBrand = '',
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String().substring(0, 16);
    final sid = shiftId ?? (await getCurrentShift())?['id'] as int?;
    final rid = registerId ?? await resolveRegisterIdForMethod(method);
    final id = await db.insert('cash_flow', {
      'type': type,
      'amount': amount,
      'description': description,
      'created_at': now,
      'category': category,
      'method': method,
      'shift_id': sid,
      'register_id': rid,
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
      await _stockInFromCash(
        inventoryId,
        inventoryQty,
        cashFlowId: id,
        brand: inventoryBrand,
      );
    }
    bumpDataRevision();
    return id;
  }

  /// Приход из кассы: обычные позиции — +qty; плёнка — новый рулон.
  Future<void> _stockInFromCash(
    int inventoryId,
    double qty, {
    int? cashFlowId,
    String brand = '',
  }) async {
    final db = await database;
    final rows = await db.query('inventory', where: 'id = ?', whereArgs: [inventoryId], limit: 1);
    if (rows.isEmpty || qty <= 0) return;
    final cat = rows.first['category']?.toString() ?? '';
    if (InventoryCategories.isFilm(cat)) {
      // Уникальный суффикс: cashFlowId + микросекунды (правка операции не бьётся UNIQUE).
      final stamp =
          '${cashFlowId ?? 0}-${DateTime.now().microsecondsSinceEpoch}';
      final unit = FilmUnits.normalize(rows.first['unit']?.toString());
      final perRoll = (rows.first['meters_per_roll'] as num?)?.toDouble() ?? 0;
      if (FilmUnits.isRolls(unit)) {
        // qty = число рулонов; метры берём из «метров в рулоне».
        final n = qty.round().clamp(1, 50);
        final meters = perRoll > 0 ? perRoll : 0.0;
        for (var i = 0; i < n; i++) {
          final suffix = n == 1 ? stamp : '$stamp-${i + 1}';
          await addFilmRoll(
            inventoryId: inventoryId,
            rollNumber: 'КАССА-$suffix',
            metersInitial: meters > 0 ? meters : null,
            cashFlowId: cashFlowId,
          );
        }
      } else {
        await addFilmRoll(
          inventoryId: inventoryId,
          rollNumber: 'КАССА-$stamp',
          metersInitial: qty,
          cashFlowId: cashFlowId,
        );
      }
      return;
    }
    await adjustInventoryQuantity(
      inventoryId,
      qty,
      reason: InventoryMoveReasons.cashPurchase,
      cashFlowId: cashFlowId,
      note: 'Закупка из кассы',
      brand: brand,
    );
  }

  /// Откат прихода со склада по кассовой операции (плёнка — удаление связанных рулонов).
  Future<void> _rollbackStockInFromCash({
    required int cashFlowId,
    required int inventoryId,
    required double inventoryQty,
    String note = '',
  }) async {
    if (inventoryQty <= 0) return;
    final db = await database;
    final inv = await db.query('inventory', where: 'id = ?', whereArgs: [inventoryId], limit: 1);
    if (inv.isEmpty) return;
    final cat = inv.first['category']?.toString() ?? '';

    if (InventoryCategories.isFilm(cat)) {
      final moveRows = await db.query(
        'inventory_moves',
        columns: ['roll_id'],
        where: 'cash_flow_id = ? AND inventory_id = ? AND roll_id IS NOT NULL',
        whereArgs: [cashFlowId, inventoryId],
      );
      var rollIds = moveRows
          .map((r) => (r['roll_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet();

      // Старые операции без cash_flow_id на движении — ищем рулоны КАССА-*.
      if (rollIds.isEmpty) {
        final unit = FilmUnits.normalize(inv.first['unit']?.toString());
        if (FilmUnits.isRolls(unit)) {
          final n = inventoryQty.round().clamp(1, 50);
          final rolls = await db.query(
            'film_rolls',
            where: "inventory_id = ? AND roll_number LIKE 'КАССА-%'",
            whereArgs: [inventoryId],
            orderBy: 'id DESC',
            limit: n,
          );
          rollIds = rolls.map((r) => (r['id'] as num).toInt()).toSet();
        } else {
          final rolls = await db.query(
            'film_rolls',
            where:
                "inventory_id = ? AND roll_number LIKE 'КАССА-%' AND abs(meters_initial - ?) < 0.011",
            whereArgs: [inventoryId, inventoryQty],
            orderBy: 'id DESC',
            limit: 1,
          );
          rollIds = rolls.map((r) => (r['id'] as num).toInt()).toSet();
        }
      }

      for (final rollId in rollIds) {
        // Снимаем ссылки заказа (метры уже «сидели» на рулоне — рулон убираем целиком).
        await db.delete('order_wrap_films', where: 'roll_id = ?', whereArgs: [rollId]);
        await db.delete('film_rolls', where: 'id = ?', whereArgs: [rollId]);
      }
      if (rollIds.isNotEmpty) {
        await _syncFilmInventoryQuantity(inventoryId);
        await _insertInventoryMove(
          inventoryId: inventoryId,
          delta: FilmUnits.isRolls(FilmUnits.normalize(inv.first['unit']?.toString()))
              ? -rollIds.length.toDouble()
              : -inventoryQty,
          balanceAfter: await _inventoryQty(inventoryId),
          reason: InventoryMoveReasons.manual,
          cashFlowId: cashFlowId,
          note: note.isEmpty ? 'Откат закупки плёнки (касса #$cashFlowId)' : note,
        );
      }
      return;
    }

    await adjustInventoryQuantity(
      inventoryId,
      -inventoryQty,
      reason: InventoryMoveReasons.manual,
      cashFlowId: cashFlowId,
      note: note,
    );
  }

  Future<Map<String, dynamic>?> getCashFlowById(int id) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT cash_flow.*, masters.name as master_name, inventory.name as inventory_name
      FROM cash_flow
      LEFT JOIN masters ON masters.id = cash_flow.master_id
      LEFT JOIN inventory ON inventory.id = cash_flow.inventory_id
      WHERE cash_flow.id = ?
      LIMIT 1
    ''', [id]);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<bool> updateCashFlow(
    int id, {
    required String type,
    required double amount,
    required String description,
    String category = 'Прочее',
    String method = 'Наличные',
    int? registerId,
    String counterparty = '',
    int? masterId,
    int? inventoryId,
    double inventoryQty = 0,
    String templateKey = '',
    String note = '',
    String inventoryBrand = '',
  }) async {
    final db = await database;
    final existing = await db.query('cash_flow', where: 'id = ?', whereArgs: [id], limit: 1);
    if (existing.isEmpty) return false;
    final old = existing.first;
    final oldType = old['type']?.toString() ?? '';
    final oldInvId = (old['inventory_id'] as num?)?.toInt();
    final oldQty = (old['inventory_qty'] as num?)?.toDouble() ?? 0;

    if (oldInvId != null && oldQty > 0 && oldType == 'Расход') {
      await _rollbackStockInFromCash(
        cashFlowId: id,
        inventoryId: oldInvId,
        inventoryQty: oldQty,
        note: 'Откат правки кассы #$id',
      );
    }

    final rid = registerId ?? await resolveRegisterIdForMethod(method);
    await db.update(
      'cash_flow',
      {
        'type': type,
        'amount': amount,
        'description': description,
        'category': category,
        'method': method,
        'register_id': rid,
        'counterparty': counterparty,
        'master_id': masterId,
        'inventory_id': inventoryId,
        'inventory_qty': inventoryQty,
        'template_key': templateKey,
        'note': note,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    if (inventoryId != null && inventoryQty > 0 && type == 'Расход') {
      await _stockInFromCash(
        inventoryId,
        inventoryQty,
        cashFlowId: id,
        brand: inventoryBrand,
      );
    }
    bumpDataRevision();
    return true;
  }

  Future<bool> deleteCashFlow(int id) async {
    final db = await database;
    final existing = await db.query('cash_flow', where: 'id = ?', whereArgs: [id], limit: 1);
    if (existing.isEmpty) return false;
    final old = existing.first;
    final oldType = old['type']?.toString() ?? '';
    final oldInvId = (old['inventory_id'] as num?)?.toInt();
    final oldQty = (old['inventory_qty'] as num?)?.toDouble() ?? 0;
    if (oldInvId != null && oldQty > 0 && oldType == 'Расход') {
      await _rollbackStockInFromCash(
        cashFlowId: id,
        inventoryId: oldInvId,
        inventoryQty: oldQty,
        note: 'Удаление операции кассы #$id',
      );
    }
    await db.delete('cash_flow', where: 'id = ?', whereArgs: [id]);
    bumpDataRevision();
    return true;
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
    if (CloudDbBridge.active) return CloudDbBridge.instance.getCashJournal(startDate, endDate);
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
        payments.register_id as register_id,
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
        cash_flow.register_id as register_id,
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
    if (CloudDbBridge.active) return CloudDbBridge.instance.getOrderDebts(limit: limit);
    final db = await database;
    return await db.rawQuery('''
      SELECT orders.id, orders.price, orders.paid_amount, orders.status,
             (orders.price - orders.paid_amount) as debt,
             clients.name as client_name, clients.phone as client_phone,
             cars.make_model, cars.plate
      FROM orders
      JOIN clients ON clients.id = orders.client_id
      JOIN cars ON cars.id = orders.car_id
      WHERE orders.is_completed = 0
        AND (orders.price - orders.paid_amount) > 0.01
      ORDER BY debt DESC
      LIMIT ?
    ''', [limit]);
  }

  Future<double> getClientDebtTotal(int clientId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN price - paid_amount > 0.01 THEN price - paid_amount ELSE 0 END), 0) as debt
      FROM orders
      WHERE client_id = ? AND is_completed = 0
    ''', [clientId]);
    return (rows.first['debt'] as num?)?.toDouble() ?? 0;
  }

  Future<double> getTotalDebt() async {
    if (CloudDbBridge.active) return CloudDbBridge.instance.getTotalDebt();
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
    if (CloudDbBridge.active) return CloudDbBridge.instance.getInventory();
    final db = await database;
    return await db.rawQuery('''
      SELECT inventory.*,
        (SELECT COUNT(*) FROM film_rolls r
          WHERE r.inventory_id = inventory.id AND r.meters_left > 0.001) AS rolls_count,
        (SELECT COALESCE(SUM(r.meters_left), 0) FROM film_rolls r
          WHERE r.inventory_id = inventory.id) AS rolls_meters
      FROM inventory
      ORDER BY inventory.name ASC
    ''');
  }

  /// Один раз подставляет логичные единицы из сида (шт→фл. и т.п.) для известных позиций.
  Future<void> applyInventoryUnitDefaultsIfNeeded() async {
    final done = await getAppSetting(InventorySeedCatalog.unitsFixKey);
    if (done == '1') return;
    final db = await database;
    var changed = 0;
    for (final s in InventorySeedCatalog.items) {
      final unit = InventoryUnits.normalize(s.unit, category: s.category);
      final n = await db.rawUpdate(
        '''
        UPDATE inventory SET unit = ?
        WHERE category = ? AND lower(trim(name)) = lower(trim(?))
        ''',
        [unit, s.category, s.name],
      );
      changed += n;
    }
    await setAppSetting(InventorySeedCatalog.unitsFixKey, '1');
    if (changed > 0) bumpDataRevision();
  }

  /// Один раз наполняет склад стандартными позициями (без дублей по имени+категории).
  Future<int> seedStandardInventoryIfNeeded() async {
    final done = await getAppSetting(InventorySeedCatalog.settingKey);
    if (done == '1') return 0;
    final db = await database;
    var added = 0;
    for (final s in InventorySeedCatalog.items) {
      final rows = await db.rawQuery(
        '''
        SELECT id FROM inventory
        WHERE category = ? AND lower(trim(name)) = lower(trim(?))
        LIMIT 1
        ''',
        [s.category, s.name],
      );
      late final int invId;
      if (rows.isNotEmpty) {
        invId = (rows.first['id'] as num).toInt();
      } else {
        invId = await addInventoryItem(
          s.name,
          0,
          s.unit,
          minQty: s.minQty,
          category: s.category,
          metersPerRoll: s.metersPerRoll,
        );
        added++;
      }
      // Плёнки — сразу в каталог цеха оклейки/тонировки.
      if (InventoryCategories.isFilm(s.category)) {
        final films = await db.query(
          'wrap_films',
          where: 'lower(trim(name)) = lower(trim(?))',
          whereArgs: [s.name],
          limit: 1,
        );
        if (films.isEmpty) {
          await db.insert('wrap_films', {'name': s.name, 'inventory_id': invId});
        } else {
          final filmInv = (films.first['inventory_id'] as num?)?.toInt();
          if (filmInv == null || filmInv <= 0) {
            await db.update(
              'wrap_films',
              {'inventory_id': invId},
              where: 'id = ?',
              whereArgs: [(films.first['id'] as num).toInt()],
            );
          }
        }
      }
    }
    await setAppSetting(InventorySeedCatalog.settingKey, '1');
    if (added > 0) bumpDataRevision();
    return added;
  }

  Future<int> addInventoryItem(
    String name,
    double quantity,
    String unit, {
    double minQty = 0,
    String category = InventoryCategories.other,
    double metersPerRoll = 0,
  }) async {
    final db = await database;
    final cat = InventoryCategories.all.contains(category) ? category : InventoryCategories.other;
    final resolvedUnit = unit.trim().isEmpty
        ? InventoryUnits.defaultFor(category: cat, name: name)
        : InventoryUnits.normalize(unit, category: cat);
    final id = await db.insert('inventory', {
      'name': name.trim(),
      'quantity': quantity,
      'unit': resolvedUnit,
      'min_qty': minQty < 0 ? 0 : minQty,
      'category': cat,
      'meters_per_roll': metersPerRoll < 0 ? 0 : metersPerRoll,
    });
    if (quantity.abs() > 0.0001 && !InventoryCategories.isFilm(cat)) {
      await _insertInventoryMove(
        inventoryId: id,
        delta: quantity,
        balanceAfter: quantity,
        reason: InventoryMoveReasons.purchase,
        note: 'Начальный остаток',
      );
    }
    if (InventoryCategories.isFilm(cat)) {
      await syncWrapFilmsFromInventory();
    }
    bumpDataRevision();
    return id;
  }

  Future<void> updateInventoryItem(
    int id, {
    String? name,
    double? quantity,
    String? unit,
    double? minQty,
    String? category,
    double? metersPerRoll,
  }) async {
    final db = await database;
    final prev = await db.query('inventory', where: 'id = ?', whereArgs: [id], limit: 1);
    if (prev.isEmpty) return;
    final oldQty = (prev.first['quantity'] as num?)?.toDouble() ?? 0;
    final prevCat = prev.first['category']?.toString() ?? InventoryCategories.other;
    final nextCat = category ?? prevCat;
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name.trim();
    if (unit != null) {
      data['unit'] = unit.trim().isEmpty
          ? InventoryUnits.defaultFor(category: nextCat, name: name ?? prev.first['name']?.toString())
          : InventoryUnits.normalize(unit, category: nextCat);
    }
    if (minQty != null) data['min_qty'] = minQty < 0 ? 0 : minQty;
    if (category != null) {
      data['category'] = InventoryCategories.all.contains(category)
          ? category
          : InventoryCategories.other;
    }
    if (metersPerRoll != null) data['meters_per_roll'] = metersPerRoll < 0 ? 0 : metersPerRoll;
    if (quantity != null && !InventoryCategories.isFilm(nextCat)) {
      data['quantity'] = quantity;
      final delta = quantity - oldQty;
      if (delta.abs() > 0.0001) {
        await _insertInventoryMove(
          inventoryId: id,
          delta: delta,
          balanceAfter: quantity,
          reason: InventoryMoveReasons.inventoryCount,
          note: 'Инвентаризация / правка остатка',
        );
      }
    }
    if (data.isEmpty) return;
    await db.update('inventory', data, where: 'id = ?', whereArgs: [id]);
    if (InventoryCategories.isFilm(nextCat)) {
      await _syncFilmInventoryQuantity(id);
      await syncWrapFilmsFromInventory();
    }
    // Имя на складе → имя в каталоге цеха.
    if (name != null && InventoryCategories.isFilm(nextCat)) {
      await db.update(
        'wrap_films',
        {'name': name.trim()},
        where: 'inventory_id = ?',
        whereArgs: [id],
      );
    }
    bumpDataRevision();
  }

  /// Позиции с остатком ≤ мин. (или ≤ 0, если мин. не задан).
  Future<List<Map<String, dynamic>>> getLowStockInventory() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT * FROM inventory
      WHERE quantity <= CASE
        WHEN coalesce(min_qty, 0) > 0 THEN min_qty
        ELSE 0
      END
      ORDER BY quantity ASC, name ASC
    ''');
  }

  /// Журнал логистики склада (приход / закупка / ручные правки).
  /// Расход цеха и рецепты сюда не попадают ([logisticsOnly] = true по умолчанию).
  Future<List<Map<String, dynamic>>> getInventoryMoves({
    int limit = 100,
    int? inventoryId,
    bool logisticsOnly = true,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object>[];
    if (inventoryId != null) {
      where.add('m.inventory_id = ?');
      args.add(inventoryId);
    }
    if (logisticsOnly) {
      final placeholders = InventoryMoveReasons.logistics.map((_) => '?').join(', ');
      where.add('m.reason IN ($placeholders)');
      args.addAll(InventoryMoveReasons.logistics);
    }
    args.add(limit);
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    return db.rawQuery('''
      SELECT m.*, i.name AS inventory_name, i.unit,
             r.roll_number AS roll_number
      FROM inventory_moves m
      JOIN inventory i ON i.id = m.inventory_id
      LEFT JOIN film_rolls r ON r.id = m.roll_id
      $whereSql
      ORDER BY m.id DESC
      LIMIT ?
    ''', args);
  }

  Future<void> _insertInventoryMove({
    required int inventoryId,
    required double delta,
    double? balanceAfter,
    required String reason,
    int? rollId,
    int? orderId,
    int? orderItemId,
    int? cashFlowId,
    String note = '',
    String brand = '',
  }) async {
    final db = await database;
    await db.insert('inventory_moves', {
      'inventory_id': inventoryId,
      'roll_id': rollId,
      'delta': delta,
      'balance_after': balanceAfter,
      'reason': reason,
      'order_id': orderId,
      'order_item_id': orderItemId,
      'cash_flow_id': cashFlowId,
      'note': note,
      'brand': InventoryBrands.normalize(brand),
      'created_at': DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' '),
    });
  }

  Future<List<String>> listInventoryBrands({String query = ''}) async {
    final db = await database;
    final q = query.trim().toLowerCase();
    final rows = q.isEmpty
        ? await db.query('inventory_brands', orderBy: 'name COLLATE NOCASE ASC')
        : await db.query(
            'inventory_brands',
            where: 'lower(name) LIKE ?',
            whereArgs: ['%$q%'],
            orderBy: 'name COLLATE NOCASE ASC',
          );
    return rows.map((r) => r['name']?.toString() ?? '').where((n) => n.isNotEmpty).toList();
  }

  /// Сохраняет бренд в справочник (если новый). Возвращает нормализованное имя.
  Future<String> ensureInventoryBrand(String? raw) async {
    final name = InventoryBrands.normalize(raw);
    if (name.isEmpty) return '';
    final db = await database;
    final existing = await db.rawQuery(
      'SELECT id FROM inventory_brands WHERE lower(name) = lower(?) LIMIT 1',
      [name],
    );
    if (existing.isEmpty) {
      await db.insert('inventory_brands', {'name': name});
      bumpDataRevision();
    }
    return name;
  }

  Future<List<Map<String, dynamic>>> listFilmRolls(int inventoryId, {bool onlyWithStock = false}) async {
    final db = await database;
    final where = onlyWithStock
        ? 'inventory_id = ? AND meters_left > 0.001'
        : 'inventory_id = ?';
    return db.query(
      'film_rolls',
      where: where,
      whereArgs: [inventoryId],
      orderBy: 'roll_number ASC',
    );
  }

  Future<int> addFilmRoll({
    required int inventoryId,
    required String rollNumber,
    double? metersInitial,
    int? cashFlowId,
  }) async {
    final db = await database;
    final rollNo = normalizeRollNumber(rollNumber);
    if (rollNo.isEmpty) throw ArgumentError('Номер рулона пуст');
    final inv = await db.query('inventory', where: 'id = ?', whereArgs: [inventoryId], limit: 1);
    if (inv.isEmpty) throw StateError('Позиция склада не найдена');
    final perRoll = (inv.first['meters_per_roll'] as num?)?.toDouble() ?? 0;
    final initial = metersInitial ?? (perRoll > 0 ? perRoll : 0);
    final id = await db.insert('film_rolls', {
      'inventory_id': inventoryId,
      'roll_number': rollNo,
      'meters_initial': initial,
      'meters_left': initial,
      'created_at': DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' '),
    });
    await _syncFilmInventoryQuantity(inventoryId);
    final unit = FilmUnits.normalize(inv.first['unit']?.toString());
    final moveDelta = FilmUnits.isRolls(unit) ? 1.0 : initial;
    if (moveDelta > 0) {
      await _insertInventoryMove(
        inventoryId: inventoryId,
        rollId: id,
        delta: moveDelta,
        balanceAfter: await _inventoryQty(inventoryId),
        reason: cashFlowId != null
            ? InventoryMoveReasons.cashPurchase
            : InventoryMoveReasons.purchase,
        cashFlowId: cashFlowId,
        note: FilmUnits.isRolls(unit)
            ? '${initial.toStringAsFixed(1)} м.п.'
            : '',
      );
    }
    bumpDataRevision();
    return id;
  }

  Future<double> _inventoryQty(int inventoryId) async {
    final db = await database;
    final rows = await db.query('inventory', columns: ['quantity'], where: 'id = ?', whereArgs: [inventoryId]);
    return (rows.first['quantity'] as num?)?.toDouble() ?? 0;
  }

  Future<void> _syncFilmInventoryQuantity(int inventoryId) async {
    final db = await database;
    final inv = await db.query(
      'inventory',
      columns: ['unit'],
      where: 'id = ?',
      whereArgs: [inventoryId],
      limit: 1,
    );
    if (inv.isEmpty) return;
    final unit = FilmUnits.normalize(inv.first['unit']?.toString());
    final double total;
    if (FilmUnits.isRolls(unit)) {
      final cnt = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM film_rolls WHERE inventory_id = ? AND meters_left > 0.001',
        [inventoryId],
      );
      total = ((cnt.first['c'] as num?)?.toInt() ?? 0).toDouble();
    } else {
      final sum = await db.rawQuery(
        'SELECT COALESCE(SUM(meters_left), 0) AS s FROM film_rolls WHERE inventory_id = ?',
        [inventoryId],
      );
      total = (sum.first['s'] as num?)?.toDouble() ?? 0;
    }
    await db.update(
      'inventory',
      {'quantity': total, 'unit': unit},
      where: 'id = ?',
      whereArgs: [inventoryId],
    );
  }

  /// Изменить остаток рулона. Возвращает текст предупреждения при уходе в минус.
  /// [logMove] = false — не писать в журнал «Движения» (расход по заказу).
  Future<String?> adjustFilmRollMeters(
    int rollId,
    double delta, {
    required String reason,
    int? orderId,
    String note = '',
    bool logMove = true,
  }) async {
    final db = await database;
    final rows = await db.query('film_rolls', where: 'id = ?', whereArgs: [rollId], limit: 1);
    if (rows.isEmpty) return 'Рулон не найден';
    final invId = (rows.first['inventory_id'] as num).toInt();
    final rollNo = rows.first['roll_number']?.toString() ?? '';
    final left = (rows.first['meters_left'] as num?)?.toDouble() ?? 0;
    final next = left + delta;
    String? warn;
    if (next < -0.001) {
      warn = 'Рулон $rollNo: остаток ${left.toStringAsFixed(1)} м, списание ${(-delta).toStringAsFixed(1)} м — уходит в минус';
    }
    await db.update('film_rolls', {'meters_left': next}, where: 'id = ?', whereArgs: [rollId]);
    await _syncFilmInventoryQuantity(invId);
    if (logMove) {
      final bal = await _inventoryQty(invId);
      final invRows = await db.query(
        'inventory',
        columns: ['unit'],
        where: 'id = ?',
        whereArgs: [invId],
        limit: 1,
      );
      final unit = FilmUnits.normalize(invRows.isEmpty ? null : invRows.first['unit']?.toString());
      final metersNote =
          '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} м.п. · рул. $rollNo';
      final moveDelta = FilmUnits.isRolls(unit)
          ? ((next > 0.001 ? 1 : 0) - (left > 0.001 ? 1 : 0)).toDouble()
          : delta;
      final moveNote = note.trim().isEmpty ? metersNote : '${note.trim()} · $metersNote';
      await _insertInventoryMove(
        inventoryId: invId,
        rollId: rollId,
        delta: moveDelta,
        balanceAfter: bal,
        reason: reason,
        orderId: orderId,
        note: moveNote,
      );
    }
    bumpDataRevision();
    return warn;
  }

  Future<List<Map<String, dynamic>>> getCashJournalForShift(int shiftId) async {
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
        payments.register_id as register_id
      FROM payments
      JOIN orders ON payments.order_id = orders.id
      JOIN clients ON orders.client_id = clients.id
      WHERE payments.shift_id = ?

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
        cash_flow.register_id as register_id
      FROM cash_flow
      WHERE cash_flow.shift_id = ?

      ORDER BY created_at DESC
    ''', [shiftId, shiftId]);
  }

  Future<Map<String, dynamic>?> getCashShiftById(int shiftId) async {
    final db = await database;
    final rows = await db.query('cash_shifts', where: 'id = ?', whereArgs: [shiftId], limit: 1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<void> deleteInventoryItem(int id) async {
    final db = await database;
    await db.delete('service_recipes', where: 'inventory_id = ?', whereArgs: [id]);
    await db.delete('film_rolls', where: 'inventory_id = ?', whereArgs: [id]);
    await db.delete('inventory_moves', where: 'inventory_id = ?', whereArgs: [id]);
    await db.update('wrap_films', {'inventory_id': null}, where: 'inventory_id = ?', whereArgs: [id]);
    await db.delete('inventory', where: 'id = ?', whereArgs: [id]);
    bumpDataRevision();
  }

  Future<void> adjustInventoryQuantity(
    int id,
    double delta, {
    String reason = InventoryMoveReasons.manual,
    int? orderId,
    int? orderItemId,
    int? cashFlowId,
    String note = '',
    String brand = '',
    bool logMove = true,
  }) async {
    final db = await database;
    final brandName = delta > 0 ? await ensureInventoryBrand(brand) : InventoryBrands.normalize(brand);
    await db.rawUpdate(
      'UPDATE inventory SET quantity = quantity + ? WHERE id = ?',
      [delta, id],
    );
    // Приход расходника: запоминаем последний бренд на карточке (остаток всё равно по типу).
    if (delta > 0 && brandName.isNotEmpty) {
      final inv = await db.query('inventory', columns: ['category'], where: 'id = ?', whereArgs: [id], limit: 1);
      final cat = inv.isEmpty ? '' : inv.first['category']?.toString();
      if (!InventoryCategories.isFilm(cat)) {
        await db.update('inventory', {'last_brand': brandName}, where: 'id = ?', whereArgs: [id]);
      }
    }
    if (logMove) {
      final bal = await _inventoryQty(id);
      await _insertInventoryMove(
        inventoryId: id,
        delta: delta,
        balanceAfter: bal,
        reason: reason,
        orderId: orderId,
        orderItemId: orderItemId,
        cashFlowId: cashFlowId,
        note: note,
        brand: brandName,
      );
    }
    bumpDataRevision();
  }

  Future<void> deductInventory(String itemName, double amount) async {
    final db = await database;
    final rows = await db.query('inventory', columns: ['id'], where: 'name = ?', whereArgs: [itemName], limit: 1);
    if (rows.isEmpty) return;
    await adjustInventoryQuantity(
      (rows.first['id'] as num).toInt(),
      -amount,
      reason: InventoryMoveReasons.manual,
      note: 'Списание по имени',
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
      bumpDataRevision();
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
    bumpDataRevision();
  }

  Future<void> deleteRecipeLine(int recipeId) async {
    final db = await database;
    await db.delete('service_recipes', where: 'id = ?', whereArgs: [recipeId]);
    bumpDataRevision();
  }

  /// Списать материалы по рецепту. Возвращает предупреждения о нехватке.
  Future<List<String>> deductRecipeForService(
    String serviceName, {
    int? orderId,
    int? orderItemId,
  }) async {
    final name = serviceName.trim();
    if (name.isEmpty) return const [];
    final warnings = <String>[];
    final recipes = await getRecipesForService(name);
    for (final r in recipes) {
      final invId = (r['inventory_id'] as num?)?.toInt();
      final qty = (r['qty'] as num?)?.toDouble() ?? 0;
      if (invId == null || qty <= 0) continue;
      final stock = (r['stock'] as num?)?.toDouble() ?? 0;
      final invName = r['inventory_name']?.toString() ?? '#$invId';
      if (stock + 0.001 < qty) {
        warnings.add('$invName: нужно $qty, есть $stock');
      }
      await adjustInventoryQuantity(
        invId,
        -qty,
        reason: InventoryMoveReasons.recipeDeduct,
        orderId: orderId,
        orderItemId: orderItemId,
        note: 'Рецепт: $name',
        logMove: false,
      );
    }
    return warnings;
  }

  Future<void> restoreRecipeForService(
    String serviceName, {
    int? orderId,
    int? orderItemId,
  }) async {
    final name = serviceName.trim();
    if (name.isEmpty) return;
    final recipes = await getRecipesForService(name);
    for (final r in recipes) {
      final invId = (r['inventory_id'] as num?)?.toInt();
      final qty = (r['qty'] as num?)?.toDouble() ?? 0;
      if (invId == null || qty <= 0) continue;
      await adjustInventoryQuantity(
        invId,
        qty,
        reason: InventoryMoveReasons.recipeRestore,
        orderId: orderId,
        orderItemId: orderItemId,
        note: 'Возврат рецепта: $name',
        logMove: false,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getAllServices() async {
    if (CloudDbBridge.active) return CloudDbBridge.instance.getAllServices();
    final db = await database;
    return await db.query('services', orderBy: 'id ASC');
  }

  Future<void> updateServicePrice(String name, String field, double price) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.updateServicePrice(name, field, price);
      bumpDataRevision();
      return;
    }
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
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.updateOrderClientNotes(orderId, clientNotes);
      return;
    }
    final db = await database;
    await db.update('orders', {'client_notes': clientNotes}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateOrderClientVisibleNotes(int orderId, String notes) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.updateOrderClientVisibleNotes(orderId, notes);
      return;
    }
    final db = await database;
    await db.update('orders', {'client_visible_notes': notes}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateOrderMasterNotes(int orderId, String notes) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.updateOrderMasterNotes(orderId, notes);
      return;
    }
    final db = await database;
    await db.update('orders', {'master_notes': notes}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateOrderPaymentMethod(int orderId, String method) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.updateOrderPaymentMethod(orderId, method);
      return;
    }
    final db = await database;
    await db.update('orders', {'payment_method': method}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> reassignOrderCar(int orderId, int carId) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.reassignOrderCar(orderId, carId);
      return;
    }
    final db = await database;
    await db.update('orders', {'car_id': carId}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateOrderMaster(int orderId, int? masterId) async {
    if (CloudDbBridge.active) {
      await CloudDbBridge.instance.updateOrderMaster(orderId, masterId);
      bumpDataRevision();
      return;
    }
    final db = await database;
    await db.update('orders', {'master_id': masterId}, where: 'id = ?', whereArgs: [orderId]);
  }

  Future<List<Map<String, dynamic>>> getClientCarsForDropdown(String phone) async {
    if (CloudDbBridge.active) return CloudDbBridge.instance.getClientCarsForDropdown(phone);
    final client = await getClientByPhone(phone);
    if (client == null) return [];
    final db = await database;
    return await db.rawQuery('''
      SELECT cars.id, cars.make_model, cars.plate, cars.vin, cars.category FROM cars 
      WHERE cars.client_id = ? ORDER BY cars.id DESC
    ''', [client['id']]);
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

  // --- НАСТРОЙКИ / ДИАГНОСТИКА ---
  Future<String?> getAppSetting(String key) async {
    final db = await database;
    final rows = await db.query('app_settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final v = rows.first['value']?.toString();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> setAppSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> addAppErrorLog({
    required String level,
    required String source,
    required String message,
    String? stack,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String().substring(0, 19);
    await db.insert('app_error_log', {
      'level': level,
      'source': source,
      'message': message.length > 4000 ? message.substring(0, 4000) : message,
      'stack': (stack ?? '').length > 8000 ? stack!.substring(0, 8000) : (stack ?? ''),
      'created_at': now,
    });
    // Храним не больше ~500 последних
    await db.rawDelete('''
      DELETE FROM app_error_log WHERE id NOT IN (
        SELECT id FROM app_error_log ORDER BY id DESC LIMIT 500
      )
    ''');
  }

  Future<List<Map<String, dynamic>>> getAppErrorLogs({int limit = 50}) async {
    final db = await database;
    return await db.query('app_error_log', orderBy: 'id DESC', limit: limit);
  }
}