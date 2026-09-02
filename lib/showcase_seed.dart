import 'database.dart';
import 'inventory_catalog.dart';

/// Фейковые данные для скринов магазина (без реальных ФИО/номеров).
class ShowcaseSeed {
  ShowcaseSeed._();

  static const settingKey = 'rustore_showcase_seed_v1';

  /// Телефоны витрины — по ним чистим/не дублируем.
  static const phonePrefix = '900111';

  static const _masterNames = ['Сергей Морозов', 'Анна Белова'];

  static bool _isShowcasePhone(String? phone) {
    final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    return digits.contains(phonePrefix);
  }

  /// Удаляет клиентов/заказы/кассу/лишних мастеров витрины.
  static Future<String> clear() async {
    final db = DatabaseHelper();

    final orders = await db.getAllOrders();
    final clients = await db.getClientsList();
    final showcaseClientIds = clients
        .where((c) => _isShowcasePhone(c['phone']?.toString()))
        .map((c) => (c['id'] as num).toInt())
        .toSet();

    var deletedOrders = 0;
    for (final o in orders) {
      final cid = (o['client_id'] as num?)?.toInt();
      if (cid != null && showcaseClientIds.contains(cid)) {
        await db.deleteOrder((o['id'] as num).toInt());
        deletedOrders++;
      }
    }

    var deletedClients = 0;
    for (final id in showcaseClientIds) {
      await db.deleteClient(id);
      deletedClients++;
    }

    // Касса с пометкой «витрина»
    final today = DateTime.now();
    final start = today.subtract(const Duration(days: 14));
    String fmt(DateTime x) =>
        '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    final journal = await db.getCashJournal(fmt(start), fmt(today.add(const Duration(days: 1))));
    var deletedCash = 0;
    for (final row in journal) {
      final title = row['title']?.toString() ?? row['description']?.toString() ?? '';
      final kind = row['kind']?.toString() ?? row['source']?.toString() ?? '';
      if (title.contains('витрина') && kind != 'payment') {
        final id = (row['id'] as num?)?.toInt();
        if (id != null) {
          await db.deleteCashFlow(id);
          deletedCash++;
        }
      }
    }

    // Мастера витрины: оставляем по одному
    final masters = await db.getAllMastersFull();
    for (final name in _masterNames) {
      final same = masters.where((m) => m['name']?.toString() == name).toList();
      for (var i = 1; i < same.length; i++) {
        final id = (same[i]['id'] as num?)?.toInt();
        if (id != null) await db.deleteMasterById(id);
      }
    }

    await db.setAppSetting(settingKey, '');
    DatabaseHelper.bumpDataRevision();
    return 'Сброшено: клиентов $deletedClients, заказов $deletedOrders, касса $deletedCash';
  }

  /// Сброс дублей + одна чистая витрина.
  static Future<String> resetAndFill() async {
    final cleared = await clear();
    final filled = await fill(force: true);
    return '$cleared\n$filled';
  }

  static Future<String> fill({bool force = false}) async {
    final db = DatabaseHelper();
    if (!force) {
      final done = await db.getAppSetting(settingKey);
      if (done == '1' || done == 'pending') {
        return 'Витрина уже заполнена. Если есть дубли — «Сбросить и заполнить».';
      }
      final clients = await db.getClientsList();
      if (clients.any((c) => _isShowcasePhone(c['phone']?.toString()))) {
        await db.setAppSetting(settingKey, '1');
        return 'Витрина уже есть. Если дубли — «Сбросить и заполнить».';
      }
    }

    // Блокируем повторный тап, пока идёт запись.
    await db.setAppSetting(settingKey, 'pending');

    final today = DateTime.now();
    String d(int offset) {
      final x = today.add(Duration(days: offset));
      return '${x.year.toString().padLeft(4, '0')}-'
          '${x.month.toString().padLeft(2, '0')}-'
          '${x.day.toString().padLeft(2, '0')}';
    }

    final masters = await db.getAllMastersFull();
    for (final name in _masterNames) {
      if (!masters.any((m) => m['name']?.toString() == name)) {
        await db.addMaster(name, 'Мастер');
      }
    }

    final c1 = await db.addClient('Артём Ковалёв', '+7$phonePrefix' '2233');
    final car1 = await db.addCar(c1, 'Toyota Camry', 'А001АА77', category: '2');
    final o1 = await db.addOrderWithItems(
      c1,
      car1,
      [
        {'name': 'Комплексная мойка', 'price': 3500.0, 'workshop': 'Мойка', 'category': 'Мойка'},
        {'name': 'Химчистка салона', 'price': 12000.0, 'workshop': 'Химчистка', 'category': 'Химчистка'},
      ],
      status: 'Мойка',
      dueDate: d(0),
      startTime: '10:00',
      endTime: '14:00',
    );
    await db.updateStatus(o1, 'Мойка');

    final c2 = await db.addClient('Мария Орлова', '+7$phonePrefix' '4455');
    final car2 = await db.addCar(c2, 'BMW X5', 'В777ОР178', category: '3');
    final o2 = await db.addOrderWithItems(
      c2,
      car2,
      [
        {'name': 'Полировка кузова', 'price': 25000.0, 'workshop': 'Полировка', 'category': 'Полировка'},
        {'name': 'Керамика', 'price': 45000.0, 'workshop': 'Полировка', 'category': 'Полировка'},
      ],
      status: 'Полировка',
      dueDate: d(0),
      startTime: '11:30',
      endTime: '18:00',
    );
    await db.updateStatus(o2, 'Полировка');

    final c3 = await db.addClient('Игорь Савельев', '+7$phonePrefix' '6677');
    final car3 = await db.addCar(c3, 'Skoda Octavia', 'Е100КХ99', category: '1');
    final o3 = await db.addOrderWithItems(
      c3,
      car3,
      [
        {'name': 'Детейлинг интерьера', 'price': 18000.0, 'workshop': 'Интерьер', 'category': 'Интерьер'},
      ],
      status: 'Принят в работу',
      dueDate: d(0),
      startTime: '12:00',
      endTime: '16:00',
    );
    await db.updateStatus(o3, 'Принят в работу');

    final c4 = await db.addClient('Елена Новикова', '+7$phonePrefix' '8899');
    final car4 = await db.addCar(c4, 'Mercedes-Benz E-Class', 'К555МТ777', category: '3');
    final o4 = await db.addOrderWithItems(
      c4,
      car4,
      [
        {'name': 'Оклейка капота', 'price': 32000.0, 'workshop': 'Оклейка', 'category': 'Оклейка'},
      ],
      status: 'Предварительная запись',
      dueDate: d(1),
      startTime: '09:00',
      endTime: '13:00',
    );
    await db.updateStatus(o4, 'Предварительная запись');

    final c5 = await db.addClient('Павел Дмитриев', '+7$phonePrefix' '0011');
    final car5 = await db.addCar(c5, 'Hyundai Tucson', 'М321НС197', category: '2');
    final o5 = await db.addOrderWithItems(
      c5,
      car5,
      [
        {'name': 'Мойка с двухфазной пеной', 'price': 2800.0, 'workshop': 'Мойка', 'category': 'Мойка'},
        {'name': 'Химчистка ковров', 'price': 4500.0, 'workshop': 'Химчистка', 'category': 'Химчистка'},
      ],
      status: 'Подготовка к выдаче',
      dueDate: d(0),
      startTime: '09:00',
      endTime: '12:30',
    );
    await db.updateStatus(o5, 'Подготовка к выдаче');

    final c6 = await db.addClient('Ольга Крылова', '+7$phonePrefix' '3344');
    final car6 = await db.addCar(c6, 'Kia Sportage', 'Т888УК50', category: '2');
    await db.addOrderWithItems(
      c6,
      car6,
      [
        {'name': 'Комплексная мойка', 'price': 3500.0, 'workshop': 'Мойка', 'category': 'Мойка'},
      ],
      status: 'Предварительная запись',
      dueDate: d(2),
      startTime: '15:00',
      endTime: '16:30',
    );

    final inv = await db.getInventory();
    if (inv.isEmpty) {
      await db.addInventoryItem(
        'Шампунь активная пена',
        12,
        InventoryUnits.liter,
        minQty: 2,
        category: InventoryCategories.wash,
      );
      await db.addInventoryItem(
        'Полироль паста',
        6,
        InventoryUnits.piece,
        minQty: 1,
        category: InventoryCategories.polishProtect,
      );
      await db.addInventoryItem(
        'Микрофибра',
        40,
        InventoryUnits.piece,
        minQty: 10,
        category: InventoryCategories.textile,
      );
      await db.addInventoryItem(
        'Плёнка PPF рулон',
        3,
        InventoryUnits.roll,
        minQty: 1,
        category: InventoryCategories.filmWrap,
        metersPerRoll: 15,
      );
    }

    await db.addCashFlow(
      'Приход',
      15500,
      'Оплата заказа (витрина)',
      category: 'Услуги',
      method: 'Карта',
      counterparty: 'Артём Ковалёв',
    );
    await db.addCashFlow(
      'Приход',
      2800,
      'Предоплата мойки (витрина)',
      category: 'Услуги',
      method: 'Наличные',
      counterparty: 'Павел Дмитриев',
    );
    await db.addCashFlow(
      'Расход',
      4200,
      'Закуп расходников (витрина)',
      category: 'Закуп',
      method: 'Карта',
      counterparty: 'Склад поставщик',
    );

    await db.setAppSetting(settingKey, '1');
    DatabaseHelper.bumpDataRevision();
    return 'Готово: клиенты, заказы, склад и касса для скринов';
  }
}
