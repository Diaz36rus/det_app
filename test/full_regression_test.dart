import 'package:flutter_test/flutter_test.dart';

import 'package:det_app/database.dart';
import 'package:det_app/inventory_catalog.dart';

import 'support/isolated_db.dart';

/// Полный регрессионный прогон бизнес-логики (без UI).
/// БД — во временной папке; боевой detailing.db не затрагивается.
void main() {
  setUpAll(() async {
    await bindIsolatedTestDb();
  });

  tearDownAll(() async {
    await disposeIsolatedTestDb();
  });

  setUp(() async {
    await resetIsolatedDb();
  });

  group('Утилиты', () {
    test('phoneDigits10 нормализует +7/8', () {
      expect(DatabaseHelper.phoneDigits10('+7 (999) 123-45-67'), '9991234567');
      expect(DatabaseHelper.phoneDigits10('89991234567'), '9991234567');
      expect(DatabaseHelper.phoneDigits10('9991234567'), '9991234567');
    });

    test('priceAfterDiscount', () {
      expect(DatabaseHelper.priceAfterDiscount(1000, 10, 0), 900);
      expect(DatabaseHelper.priceAfterDiscount(1000, 0, 150), 850);
      expect(DatabaseHelper.priceAfterDiscount(100, 0, 200), 0);
    });

    test('resolveInitialOrderStatus', () {
      final future = DateTime.now().add(const Duration(days: 2)).toIso8601String().substring(0, 16);
      final past = DateTime.now().subtract(const Duration(hours: 1)).toIso8601String().substring(0, 16);
      expect(resolveInitialOrderStatus(future), 'Предварительная запись');
      expect(resolveInitialOrderStatus(past), 'Принят в работу');
      expect(resolveInitialOrderStatus(null), 'Предварительная запись');
    });

    test('InventoryUnits normalize / defaultFor', () {
      expect(InventoryUnits.normalize('литры'), InventoryUnits.liter);
      expect(InventoryUnits.normalize('канистра'), InventoryUnits.canister);
      expect(InventoryUnits.normalize('фл'), InventoryUnits.bottle);
      expect(InventoryUnits.normalize('рулон', category: InventoryCategories.filmWrap), FilmUnits.rolls);
      expect(InventoryUnits.defaultFor(category: InventoryCategories.wash, name: 'Шампунь'), InventoryUnits.liter);
      expect(InventoryUnits.defaultFor(category: InventoryCategories.toolsConsumables, name: 'Перчатки'), InventoryUnits.pack);
      expect(InventoryUnits.defaultFor(category: InventoryCategories.polishProtect, name: 'Полироль'), InventoryUnits.bottle);
      expect(InventoryUnits.defaultFor(category: InventoryCategories.filmTint, name: 'Тонировка'), InventoryUnits.meters);
    });

    test('workshopForService', () {
      expect(workshopForService(category: 'Мойка', name: 'Комплекс'), 'Мойка');
      expect(workshopForService(name: 'Полировка кузова'), 'Полировка');
      expect(workshopForService(category: 'Оклейка (Пленка)', name: 'Оклейка · капот'), 'Оклейка');
    });
  });

  group('Склад: сид и единицы', () {
    test('seed один раз + units fix', () async {
      final db = DatabaseHelper();
      final n1 = await db.seedStandardInventoryIfNeeded();
      expect(n1, greaterThan(0));
      final n2 = await db.seedStandardInventoryIfNeeded();
      expect(n2, 0);
      await db.applyInventoryUnitDefaultsIfNeeded();
      final items = await db.getInventory();
      final shampoo = items.firstWhere((i) => i['name'] == 'Шампунь бесконтактный');
      expect(shampoo['unit'], InventoryUnits.liter);
      final polish = items.firstWhere((i) => i['name'] == 'Полироль крупноабразивная');
      expect(polish['unit'], InventoryUnits.bottle);
      final gloves = items.firstWhere((i) => i['name'] == 'Перчатки нитриловые M');
      expect(gloves['unit'], InventoryUnits.pack);
    });

    test('addInventoryItem нормализует unit', () async {
      final db = DatabaseHelper();
      final id = await db.addInventoryItem('Тест шампунь', 10, 'литры', category: InventoryCategories.wash);
      final row = await invById(id);
      expect(row['unit'], InventoryUnits.liter);
      expect(await invQty(id), 10);
    });
  });

  group('Заказ: жизненный цикл до выдачи', () {
    test('полный happy-path: работы → рецепт → оплата → handover → Выдан', () async {
      final db = DatabaseHelper();
      final invId = await db.addInventoryItem('Тест химия', 10, 'л', category: InventoryCategories.wash);
      await db.setRecipeLine('Комплексная мойка', invId, 2);

      final clientId = await db.addClient('Иван Тестов', '+79991112233');
      final carId = await db.addCar(clientId, 'Toyota Camry', 'А123ВС777');
      final orderId = await db.addOrderWithItems(
        clientId,
        carId,
        [
          {'name': 'Комплексная мойка', 'price': 3000.0, 'category': 'Мойка'},
        ],
        startTime: DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String().substring(0, 16),
      );

      final order = await db.getOrderById(orderId);
      expect(order?['status'], 'Принят в работу');
      expect((order?['price'] as num?)?.toDouble(), 3000);

      final items = await db.getOrderItems(orderId);
      expect(items.length, 1);
      final itemId = (items.first['id'] as num).toInt();

      // Выдача заблокирована: долг + работы + handover
      var reasons = await db.validateIssueOrder(orderId);
      expect(reasons, isNotEmpty);
      expect(await db.updateStatus(orderId, 'Выдан'), isFalse);

      final warnings = await db.updateOrderItemDone(itemId, true);
      expect(warnings, isEmpty);
      expect(await invQty(invId), 8);

      // Идемпотентность: повторное done не списывает ещё раз
      await db.updateOrderItemDone(itemId, true);
      expect(await invQty(invId), 8);

      // Undo восстанавливает
      await db.updateOrderItemDone(itemId, false);
      expect(await invQty(invId), 10);
      await db.updateOrderItemDone(itemId, true);
      expect(await invQty(invId), 8);

      await db.openCashShift(1000);
      await db.addPayment(orderId, 3000, 'Наличные');

      await db.saveOrderHandover(orderId, {
        'handover_notified': 1,
        'handover_works': 1,
        'handover_inspect': 1,
        'handover_payment': 1,
        'handover_keys': 1,
      });

      reasons = await db.validateIssueOrder(orderId);
      expect(reasons, isEmpty, reason: reasons.join(' | '));
      expect(await db.updateStatus(orderId, 'Выдан'), isTrue);
      final done = await db.getOrderById(orderId);
      expect(done?['status'], 'Выдан');
      expect((done?['is_completed'] as num?)?.toInt(), 1);
    });

    test('оплата без смены бросает', () async {
      final db = DatabaseHelper();
      final clientId = await db.addClient('Клиент', '9001112233');
      final carId = await db.addCar(clientId, 'Kia Rio', 'В111АА111');
      final orderId = await db.addOrder(clientId, carId, 1000, 'тест');
      expect(() => db.addPayment(orderId, 1000, 'Наличные'), throwsStateError);
    });

    test('скидка пересчитывает price заказа', () async {
      final db = DatabaseHelper();
      final clientId = await db.addClient('Клиент', '9001112234');
      final carId = await db.addCar(clientId, 'Kia', 'В222АА111');
      final orderId = await db.addOrderWithItems(clientId, carId, [
        {'name': 'Мойка', 'price': 2000.0, 'category': 'Мойка'},
      ]);
      await db.updateOrderDiscount(orderId, discountPercent: 10);
      final o = await db.getOrderById(orderId);
      expect((o?['price'] as num?)?.toDouble(), 1800);
    });

    test('нехватка по рецепту — warning, списание в минус', () async {
      final db = DatabaseHelper();
      final invId = await db.addInventoryItem('Мало химии', 1, 'л', category: InventoryCategories.wash);
      await db.setRecipeLine('Услуга X', invId, 5);
      final clientId = await db.addClient('Клиент', '9001112235');
      final carId = await db.addCar(clientId, 'Lada', 'С333СС33');
      final orderId = await db.addOrderWithItems(clientId, carId, [
        {'name': 'Услуга X', 'price': 500.0, 'category': 'Мойка'},
      ]);
      final itemId = ((await db.getOrderItems(orderId)).first['id'] as num).toInt();
      final warnings = await db.updateOrderItemDone(itemId, true);
      expect(warnings, isNotEmpty);
      expect(await invQty(invId), -4);
    });
  });

  group('Пакеты оклейка / тонировка', () {
    test('зоны собираются в шапку, выдача смотрит зоны', () async {
      final db = DatabaseHelper();
      final clientId = await db.addClient('Клиент', '9001112240');
      final carId = await db.addCar(clientId, 'BMW', 'Е444ЕЕ44');
      final orderId = await db.addOrderWithItems(clientId, carId, [
        {
          'name': 'Оклейка · капот',
          'price': 15000.0,
          'category': 'Оклейка (Пленка)',
        },
        {
          'name': 'Оклейка · крыша',
          'price': 10000.0,
          'category': 'Оклейка (Пленка)',
        },
      ]);

      final items = await db.getOrderItems(orderId);
      final header = items.where((i) => i['name'] == 'Оклейка' && i['parent_id'] == null).toList();
      final zones = items.where((i) => (i['parent_id'] as num?) != null).toList();
      expect(header.length, 1);
      expect(zones.length, 2);
      expect((zones.first['price'] as num?)?.toDouble(), 0);
      final headerPrice = (header.first['price'] as num?)?.toDouble() ?? 0;
      expect(headerPrice, 25000);

      // Без выполнения зон — блок
      var reasons = await db.validateIssueOrder(orderId);
      expect(reasons.any((r) => r.contains('Не выполнены')), isTrue);

      final headerId = (header.first['id'] as num).toInt();
      await db.updateWrapPackageDone(headerId, true);

      // Зоны done, шапка синхронизирована
      final after = await db.getOrderItems(orderId);
      expect(after.every((i) => ((i['is_done'] as num?)?.toInt() ?? 0) == 1), isTrue);

      await db.openCashShift(0);
      await db.addPayment(orderId, 25000, 'Наличные');
      await db.saveOrderHandover(orderId, {
        'handover_notified': 1,
        'handover_works': 1,
        'handover_inspect': 1,
        'handover_payment': 1,
        'handover_keys': 1,
      });
      reasons = await db.validateIssueOrder(orderId);
      expect(reasons, isEmpty, reason: reasons.join(' | '));
      expect(await db.updateStatus(orderId, 'Выдан'), isTrue);
    });

    test('тонировка: пакет и зоны', () async {
      final db = DatabaseHelper();
      final clientId = await db.addClient('Клиент', '9001112241');
      final carId = await db.addCar(clientId, 'Audi', 'Т555ТТ55');
      final orderId = await db.addOrderWithItems(clientId, carId, [
        {
          'name': 'Тонировка · задняя полусфера · 5%',
          'price': 8000.0,
          'category': 'Тонировка',
        },
      ]);
      final items = await db.getOrderItems(orderId);
      expect(items.any((i) => i['name'] == 'Тонировка' && i['parent_id'] == null), isTrue);
      expect(items.any((i) => (i['parent_id'] as num?) != null), isTrue);
    });
  });

  group('Плёнка: рулоны и расход по заказу', () {
    test('delta setOrderWrapFilms списывает и возвращает метры', () async {
      final db = DatabaseHelper();
      final invId = await db.addInventoryItem(
        'PPF тест',
        0,
        FilmUnits.meters,
        category: InventoryCategories.filmWrap,
        metersPerRoll: 15,
      );
      final rollId = await db.addFilmRoll(inventoryId: invId, rollNumber: 'R-001');
      expect(await invQty(invId), 15);

      final films = await db.listWrapFilms();
      final film = films.firstWhere((f) => f['name'] == 'PPF тест');
      final filmId = (film['id'] as num).toInt();

      final clientId = await db.addClient('Клиент', '9001112250');
      final carId = await db.addCar(clientId, 'Ford', 'Ф666ФФ66');
      final orderId = await db.addOrder(clientId, carId, 0, 'плёнка');

      var warnings = await db.setOrderWrapFilms(orderId, [
        {'filmId': filmId, 'rollId': rollId, 'meters': 3.5},
      ]);
      expect(warnings, isEmpty);
      expect(await invQty(invId), closeTo(11.5, 0.001));

      // Увеличили расход
      warnings = await db.setOrderWrapFilms(orderId, [
        {'filmId': filmId, 'rollId': rollId, 'meters': 5},
      ]);
      expect(warnings, isEmpty);
      expect(await invQty(invId), closeTo(10, 0.001));

      // Очистили — полный возврат
      warnings = await db.setOrderWrapFilms(orderId, []);
      expect(warnings, isEmpty);
      expect(await invQty(invId), closeTo(15, 0.001));
    });

    test('учёт в рулонах: quantity = число рулонов с остатком', () async {
      final db = DatabaseHelper();
      final invId = await db.addInventoryItem(
        'Винил рулоны',
        0,
        FilmUnits.rolls,
        category: InventoryCategories.filmWrap,
        metersPerRoll: 18,
      );
      await db.addFilmRoll(inventoryId: invId, rollNumber: 'A1');
      await db.addFilmRoll(inventoryId: invId, rollNumber: 'A2');
      expect(await invQty(invId), 2);

      final rolls = await db.listFilmRolls(invId);
      final rollId = (rolls.first['id'] as num).toInt();
      await db.adjustFilmRollMeters(rollId, -18, reason: InventoryMoveReasons.manual, logMove: false);
      expect(await invQty(invId), 1);
    });

    test('дубликат номера рулона запрещён', () async {
      final db = DatabaseHelper();
      final invId = await db.addInventoryItem(
        'Плёнка dup',
        0,
        FilmUnits.meters,
        category: InventoryCategories.filmTint,
        metersPerRoll: 30,
      );
      await db.addFilmRoll(inventoryId: invId, rollNumber: 'dup-1');
      expect(
        () => db.addFilmRoll(inventoryId: invId, rollNumber: 'DUP-1'),
        throwsA(anything),
      );
    });
  });

  group('Касса ↔ склад', () {
    test('закупка расходника увеличивает остаток', () async {
      final db = DatabaseHelper();
      final invId = await db.addInventoryItem('Салфетки', 2, 'уп', category: InventoryCategories.toolsConsumables);
      await db.openCashShift(5000);
      await db.addCashFlow(
        'Расход',
        1000,
        'Закупка салфеток',
        inventoryId: invId,
        inventoryQty: 5,
        inventoryBrand: 'TestBrand',
      );
      expect(await invQty(invId), 7);
    });

    test('закупка плёнки создаёт рулон', () async {
      final db = DatabaseHelper();
      final invId = await db.addInventoryItem(
        'Тонировка cash',
        0,
        FilmUnits.meters,
        category: InventoryCategories.filmTint,
        metersPerRoll: 30,
      );
      await db.openCashShift(5000);
      await db.addCashFlow(
        'Расход',
        5000,
        'Рулон тонировки',
        inventoryId: invId,
        inventoryQty: 30,
      );
      final rolls = await db.listFilmRolls(invId);
      expect(rolls.length, 1);
      expect(await invQty(invId), closeTo(30, 0.001));
    });

    test('удаление кассовой закупки плёнки не должно ломать остаток/рулоны', () async {
      final db = DatabaseHelper();
      final invId = await db.addInventoryItem(
        'Плёнка rollback',
        0,
        FilmUnits.meters,
        category: InventoryCategories.filmWrap,
        metersPerRoll: 15,
      );
      await db.openCashShift(5000);
      final flowId = await db.addCashFlow(
        'Расход',
        3000,
        'Рулон',
        inventoryId: invId,
        inventoryQty: 15,
      );
      expect((await db.listFilmRolls(invId)).length, 1);
      expect(await invQty(invId), closeTo(15, 0.001));

      await db.deleteCashFlow(flowId);

      // Ожидаемое корректное поведение: рулон убран ИЛИ qty согласован с рулонами.
      final rolls = await db.listFilmRolls(invId);
      final qty = await invQty(invId);
      final metersSum = rolls.fold<double>(
        0,
        (s, r) => s + ((r['meters_left'] as num?)?.toDouble() ?? 0),
      );
      expect(
        qty,
        closeTo(metersSum, 0.01),
        reason: 'После удаления кассовой закупки плёнки inventory.quantity ($qty) '
            'должен совпадать с суммой meters_left рулонов ($metersSum). '
            'Рулонов осталось: ${rolls.length}',
      );
      expect(rolls, isEmpty, reason: 'Рулон от удалённой закупки должен быть снят');
    });
  });

  group('Каскады и целостность', () {
    test('deleteOrder должен возвращать метры плёнки или чистить order_wrap_films', () async {
      final db = DatabaseHelper();
      final invId = await db.addInventoryItem(
        'PPF cascade',
        0,
        FilmUnits.meters,
        category: InventoryCategories.filmWrap,
        metersPerRoll: 15,
      );
      final rollId = await db.addFilmRoll(inventoryId: invId, rollNumber: 'C-1');
      final filmId = ((await db.listWrapFilms()).firstWhere((f) => f['name'] == 'PPF cascade')['id'] as num)
          .toInt();

      final clientId = await db.addClient('Клиент', '9001112260');
      final carId = await db.addCar(clientId, 'VW', 'У777УУ77');
      final orderId = await db.addOrder(clientId, carId, 0, 'плёнка');
      await db.setOrderWrapFilms(orderId, [
        {'filmId': filmId, 'rollId': rollId, 'meters': 4},
      ]);
      expect(await invQty(invId), closeTo(11, 0.001));

      await db.deleteOrder(orderId);

      final qtyAfter = await invQty(invId);
      final wrapLeft = await db.getOrderWrapFilms(orderId);
      // Корректно: либо метры вернулись, либо хотя бы строки расхода удалены + qty восстановлен.
      expect(
        qtyAfter,
        closeTo(15, 0.01),
        reason: 'Удаление заказа должно вернуть 4 м.п. на рулон (было 11, ожидаем 15). Сейчас: $qtyAfter',
      );
      expect(wrapLeft, isEmpty, reason: 'order_wrap_films не должны оставаться после deleteOrder');
    });

    test('клиент находится по телефону в разных форматах', () async {
      final db = DatabaseHelper();
      await db.addClient('Мария', '+7 900 111-22-60');
      final found = await db.getClientByPhone('89001112260');
      expect(found, isNotNull);
      expect(found?['name'], 'Мария');
    });

    test('voidPayment уменьшает paid_amount', () async {
      final db = DatabaseHelper();
      final clientId = await db.addClient('Клиент', '9001112261');
      final carId = await db.addCar(clientId, 'Skoda', 'Х888ХХ88');
      final orderId = await db.addOrder(clientId, carId, 2000, 'оплата');
      await db.openCashShift(0);
      await db.addPayment(orderId, 2000, 'Наличные');
      final pays = await db.getOrderPayments(orderId);
      expect(pays.length, 1);
      await db.voidPayment((pays.first['id'] as num).toInt());
      final o = await db.getOrderById(orderId);
      expect((o?['paid_amount'] as num?)?.toDouble() ?? -1, 0);
    });

    test('syncZonePackage пустой список удаляет шапку', () async {
      final db = DatabaseHelper();
      final clientId = await db.addClient('Клиент', '9001112262');
      final carId = await db.addCar(clientId, 'Mazda', 'М999ММ99');
      final orderId = await db.addOrderWithItems(clientId, carId, [
        {
          'name': 'Оклейка · капот',
          'price': 5000.0,
          'category': 'Оклейка (Пленка)',
        },
      ]);
      expect((await db.getOrderItems(orderId)).any((i) => i['name'] == 'Оклейка'), isTrue);
      await db.syncZonePackage(orderId: orderId, kind: 'wrap', zoneNames: [], packagePrice: 0);
      final left = await db.getOrderItems(orderId);
      expect(left.where((i) => i['name'] == 'Оклейка' || (i['name']?.toString() ?? '').startsWith('Оклейка ·')), isEmpty);
    });

    test('handover_ready не блокирует выдачу', () async {
      final db = DatabaseHelper();
      final clientId = await db.addClient('Клиент', '9001112263');
      final carId = await db.addCar(clientId, 'Opel', 'О101ОО01');
      final orderId = await db.addOrderWithItems(clientId, carId, [
        {'name': 'Мойка экспресс', 'price': 1000.0, 'category': 'Мойка'},
      ]);
      final itemId = ((await db.getOrderItems(orderId)).first['id'] as num).toInt();
      await db.updateOrderItemDone(itemId, true);
      await db.openCashShift(0);
      await db.addPayment(orderId, 1000, 'Наличные');
      await db.saveOrderHandover(orderId, {
        'handover_notified': 1,
        'handover_works': 1,
        'handover_inspect': 1,
        'handover_payment': 1,
        'handover_keys': 1,
        'handover_ready': 0,
      });
      expect(await db.validateIssueOrder(orderId), isEmpty);
      expect(await db.updateStatus(orderId, 'Выдан'), isTrue);
    });

    test('правка кассовой закупки плёнки не должна рассогласовать qty и рулоны', () async {
      final db = DatabaseHelper();
      final invId = await db.addInventoryItem(
        'Плёнка edit',
        0,
        FilmUnits.meters,
        category: InventoryCategories.filmTint,
        metersPerRoll: 30,
      );
      await db.openCashShift(10000);
      final flowId = await db.addCashFlow(
        'Расход',
        4000,
        'Рулон 1',
        inventoryId: invId,
        inventoryQty: 30,
      );
      expect(await invQty(invId), closeTo(30, 0.01));

      await db.updateCashFlow(
        flowId,
        type: 'Расход',
        amount: 4000,
        description: 'Рулон правка',
        inventoryId: invId,
        inventoryQty: 30,
      );

      final rolls = await db.listFilmRolls(invId);
      final metersSum = rolls.fold<double>(
        0,
        (s, r) => s + ((r['meters_left'] as num?)?.toDouble() ?? 0),
      );
      final qty = await invQty(invId);
      expect(
        qty,
        closeTo(metersSum, 0.01),
        reason: 'После updateCashFlow плёнки qty=$qty, sum meters_left=$metersSum, rolls=${rolls.length}',
      );
    });

    test('рецепт на зону пакета списывается через updateWrapPackageDone', () async {
      final db = DatabaseHelper();
      final invId = await db.addInventoryItem('Праймер тест', 10, 'фл.', category: InventoryCategories.toolsConsumables);
      await db.setRecipeLine('Оклейка · капот', invId, 1);
      final clientId = await db.addClient('Клиент', '9001112264');
      final carId = await db.addCar(clientId, 'Volvo', 'В202ВВ02');
      final orderId = await db.addOrderWithItems(clientId, carId, [
        {
          'name': 'Оклейка · капот',
          'price': 7000.0,
          'category': 'Оклейка (Пленка)',
        },
      ]);
      final headerId = ((await db.getOrderItems(orderId)).firstWhere((i) => i['name'] == 'Оклейка')['id'] as num)
          .toInt();
      await db.updateWrapPackageDone(headerId, true);
      expect(await invQty(invId), 9);
      await db.updateWrapPackageDone(headerId, false);
      expect(await invQty(invId), 10);
    });
  });

  group('Касса: смена', () {
    test('openCashShift повторно возвращает ту же открытую смену', () async {
      final db = DatabaseHelper();
      final a = await db.openCashShift(1000);
      final b = await db.openCashShift(9999);
      expect(b, a);
      final cur = await db.getCurrentShift();
      expect(cur, isNotNull);
      expect((cur!['opening_cash'] as num?)?.toDouble(), 1000);
      expect(cur['status'], 'open');
    });

    test('closeCashShift закрывает смену и учитывает оплату', () async {
      final db = DatabaseHelper();
      final shiftId = await db.openCashShift(500);
      final clientId = await db.addClient('Смена', '9001112270');
      final carId = await db.addCar(clientId, 'Lada', 'А111АА11');
      final orderId = await db.addOrder(clientId, carId, 1500, 'смена');
      await db.addPayment(orderId, 1500, 'Наличные');

      final expected = await db.getShiftExpectedCash(shiftId);
      // 500 opening + 1500 payment
      expect(expected, closeTo(2000, 0.01));

      await db.closeCashShift(shiftId, 2000, note: 'z');
      expect(await db.getCurrentShift(), isNull);
      final closed = await db.getCashShiftById(shiftId);
      expect(closed?['status'], 'closed');
      expect((closed?['fact_cash'] as num?)?.toDouble(), closeTo(2000, 0.01));
    });

    test('после закрытия можно открыть новую смену', () async {
      final db = DatabaseHelper();
      final first = await db.openCashShift(100);
      await db.closeCashShift(first, 100);
      final second = await db.openCashShift(200);
      expect(second, isNot(first));
      expect(await db.getCurrentShift(), isNotNull);
    });
  });

  group('Клиент: как в прошлый раз', () {
    test('getLastOrderCartLines копирует позиции последнего заказа', () async {
      final db = DatabaseHelper();
      final clientId = await db.addClient('Повтор', '9001112271');
      final carId = await db.addCar(clientId, 'Kia', 'К222КК22');
      await db.addOrderWithItems(clientId, carId, [
        {'name': 'Мойка комплекс', 'price': 2500.0, 'category': 'Мойка'},
        {'name': 'Химчистка салона', 'price': 8000.0, 'category': 'Химчистка'},
      ]);
      final lines = await db.getLastOrderCartLines(clientId: clientId, carId: carId);
      expect(lines.length, greaterThanOrEqualTo(2));
      final names = lines.map((e) => e['name']?.toString()).toSet();
      expect(names.contains('Мойка комплекс'), isTrue);
      expect(names.contains('Химчистка салона'), isTrue);
    });
  });
}
