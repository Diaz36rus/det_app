import 'dart:convert';

import '../cash_cloud/cash_cloud_api.dart';
import '../cash_cloud/cash_cloud_models.dart';
import 'cloud_mode.dart';
import 'crm_api.dart';
import 'crm_models.dart';

/// Адаптер: старые экраны (Map/SQLite-форма) ↔ облачный REST.
class CloudDbBridge {
  CloudDbBridge._();
  static final CloudDbBridge instance = CloudDbBridge._();

  final _crm = CrmApi();
  final _cash = CashCloudApi();

  final Map<int, CrmOrder> _orders = {};
  final Map<int, CrmClient> _clients = {};
  final Map<int, CrmCar> _cars = {};
  List<CrmMaster> _masters = [];
  List<CrmService> _services = [];
  List<CrmInventoryItem> _inventory = [];

  static bool get active => CloudMode.enabled;

  Future<void> refreshAll() async {
    final results = await Future.wait([
      _crm.listOrders(),
      _crm.listClients(),
      _crm.listCars(),
      _crm.listMasters(),
      _crm.listServices(),
      _crm.listInventory(),
    ]);
    final orders = results[0] as List<CrmOrder>;
    final clients = results[1] as List<CrmClient>;
    final cars = results[2] as List<CrmCar>;
    _masters = results[3] as List<CrmMaster>;
    _services = results[4] as List<CrmService>;
    _inventory = results[5] as List<CrmInventoryItem>;
    _orders
      ..clear()
      ..addEntries(orders.map((o) => MapEntry(o.id, o)));
    _clients
      ..clear()
      ..addEntries(clients.map((c) => MapEntry(c.id, c)));
    _cars
      ..clear()
      ..addEntries(cars.map((c) => MapEntry(c.id, c)));
  }

  Future<void> _ensureOrders() async {
    if (_orders.isEmpty) {
      final list = await _crm.listOrders();
      _orders
        ..clear()
        ..addEntries(list.map((o) => MapEntry(o.id, o)));
    }
  }

  Future<void> _ensureClients() async {
    if (_clients.isEmpty) {
      final list = await _crm.listClients();
      _clients
        ..clear()
        ..addEntries(list.map((c) => MapEntry(c.id, c)));
    }
  }

  Future<void> _ensureCars() async {
    if (_cars.isEmpty) {
      final list = await _crm.listCars();
      _cars
        ..clear()
        ..addEntries(list.map((c) => MapEntry(c.id, c)));
    }
  }

  (String make, String plate) _splitCar(String? label) {
    final s = (label ?? '').trim();
    if (s.isEmpty) return ('', '');
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length == 1) return (parts.first, '');
    // последняя «слово» часто номер
    final plate = parts.last;
    final make = parts.sublist(0, parts.length - 1).join(' ');
    return (make, plate);
  }

  Map<String, dynamic> orderToMap(CrmOrder o) {
    final client = _clients[o.clientId];
    final car = _cars[o.carId];
    String make = car?.makeModel ?? '';
    String plate = car?.plate ?? '';
    if (make.isEmpty && (o.carLabel ?? '').isNotEmpty) {
      final split = _splitCar(o.carLabel);
      make = split.$1;
      plate = split.$2;
    }
    String? masterName;
    if (o.masterIds.isNotEmpty && _masters.isNotEmpty) {
      final m = _masters.where((e) => e.id == o.masterIds.first).toList();
      if (m.isNotEmpty) masterName = m.first.name;
    }
    final worksTotal = o.items.length;
    final worksDone = o.items.where((i) => i.isDone).length;
    return {
      'id': o.id,
      'client_id': o.clientId,
      'car_id': o.carId,
      'status': o.status,
      'price': o.price,
      'paid_amount': o.paidAmount,
      'notes': o.notes,
      'due_date': o.dueDate,
      'start_time': o.startTime,
      'end_time': o.endTime,
      'end_date': o.endDate.isNotEmpty ? o.endDate : o.dueDate,
      'client_name': o.clientName ?? client?.name ?? '',
      'client_phone': client?.phone ?? '',
      'is_vip': client?.isVip == true ? 1 : 0,
      'make_model': make,
      'plate': plate,
      'vin': car?.vin ?? '',
      'category': car?.category ?? '1',
      'master_name': masterName,
      'master_id': o.masterIds.isEmpty ? null : o.masterIds.first,
      'works_total': worksTotal,
      'works_done': worksDone,
      'is_completed': o.status == 'Выдан' ? 1 : 0,
      'discount_percent': o.discountPercent,
      'discount_fixed': o.discountFixed,
      'promo_code': o.promoCode,
      'client_notes': o.clientNotes,
      'client_visible_notes': o.clientVisibleNotes,
      'master_notes': o.masterNotes,
      'payment_method': o.paymentMethod,
      'handover_ready': o.handoverReady ? 1 : 0,
      'handover_works': o.handoverWorks ? 1 : 0,
      'handover_payment': o.handoverPayment ? 1 : 0,
      'handover_keys': o.handoverKeys ? 1 : 0,
      'handover_inspect': o.handoverInspect ? 1 : 0,
      'handover_notified': o.handoverNotified ? 1 : 0,
      'tech_wash_start': o.techWashStart.isEmpty ? null : o.techWashStart,
      'tech_wash_end': o.techWashEnd.isEmpty ? null : o.techWashEnd,
      'is_workshop_completed': o.isWorkshopCompleted ? 1 : 0,
    };
  }

  Future<List<Map<String, dynamic>>> getAllOrders() async {
    await refreshAll();
    return _orders.values.where((o) => o.status != 'Выдан').map(orderToMap).toList()
      ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
  }

  Future<List<Map<String, dynamic>>> getCompletedOrders([String query = '']) async {
    await refreshAll();
    var list = _orders.values.where((o) => o.status == 'Выдан').map(orderToMap).toList();
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((o) {
        final hay = [
          o['id'],
          o['client_name'],
          o['client_phone'],
          o['make_model'],
          o['plate'],
        ].join(' ').toLowerCase();
        return hay.contains(q);
      }).toList();
    }
    list.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    return list;
  }

  Future<Map<String, dynamic>?> getOrderById(int id) async {
    await _ensureClients();
    await _ensureCars();
    if (!_orders.containsKey(id)) {
      await _ensureOrders();
      // force refresh one order set
      final list = await _crm.listOrders();
      _orders
        ..clear()
        ..addEntries(list.map((o) => MapEntry(o.id, o)));
    }
    final o = _orders[id];
    return o == null ? null : orderToMap(o);
  }

  Future<List<Map<String, dynamic>>> getOrderItems(int orderId) async {
    if (!_orders.containsKey(orderId)) {
      final list = await _crm.listOrders();
      _orders
        ..clear()
        ..addEntries(list.map((o) => MapEntry(o.id, o)));
    }
    final o = _orders[orderId];
    if (o == null) return [];
    return o.items
        .map(
          (it) => {
            'id': it.id ?? 0,
            'order_id': orderId,
            'name': it.name,
            'price': it.price,
            'workshop': it.workshop,
            'is_done': it.isDone ? 1 : 0,
            'parent_id': it.parentId,
            'comment': it.comment,
            'master_ids': it.masterIds,
            'start_time': it.startTime.isEmpty ? null : it.startTime,
            'end_time': it.endTime.isEmpty ? null : it.endTime,
          },
        )
        .toList();
  }

  Future<List<String>> validateIssueOrder(int orderId) async {
    await _ensureOrders();
    final order = _orders[orderId];
    if (order == null) return ['Заказ не найден'];

    final reasons = <String>[];
    final debt = order.price - order.paidAmount;
    if (debt > 0.01) {
      final debtStr = debt.toStringAsFixed(debt == debt.roundToDouble() ? 0 : 2);
      reasons.add('Долг: $debtStr ₽');
    }

    final incomplete = order.items.where((it) {
      if (it.isDone) return false;
      final name = it.name.trim();
      if ((name == 'Оклейка' || name == 'Тонировка') && it.parentId == null) return false;
      return true;
    }).toList();
    if (incomplete.isNotEmpty) {
      final labels = incomplete.map((w) {
        final name = w.name.trim();
        final ws = w.workshop.trim();
        final base = name.isEmpty ? 'Без названия' : name;
        if (ws.isNotEmpty) return '$base ($ws)';
        return base;
      }).toList();
      reasons.add(
        'Не выполнены работы (${labels.length}):\n'
        '${labels.map((n) => '— $n').join('\n')}',
      );
    }

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

  Future<bool> updateStatus(int orderId, String newStatus) async {
    if (newStatus == 'Выдан') {
      final reasons = await validateIssueOrder(orderId);
      if (reasons.isNotEmpty) return false;
    }
    await _crm.patchOrder(orderId, {'status': newStatus});
    final prev = _orders[orderId];
    if (prev != null) {
      final list = await _crm.listOrders();
      _orders
        ..clear()
        ..addEntries(list.map((o) => MapEntry(o.id, o)));
    }
    return true;
  }

  Future<void> deleteOrder(int id) async {
    try {
      await _crm.putOrderWrapFilms(id, const []);
    } catch (_) {}
    try {
      await _crm.deleteOrder(id);
    } catch (_) {
      // Старый API без DELETE — уводим с доски
      await _crm.patchOrder(id, {'status': 'Выдан'});
    }
    _orders.remove(id);
  }

  /// Очистить доску в облаке. [clients] — удалить и клиентов/авто.
  Future<Map<String, dynamic>> clearBoard({
    bool hard = false,
    bool clients = false,
  }) async {
    final res = await _crm.clearBoardOrders(hard: hard || clients, clients: clients);
    await refreshAll();
    return res;
  }

  Future<List<Map<String, dynamic>>> getClientsList() async {
    await _ensureClients();
    await _ensureCars();
    if (_clients.isEmpty) {
      final list = await _crm.listClients();
      _clients.addEntries(list.map((c) => MapEntry(c.id, c)));
    }
    return _clients.values
        .map(
          (c) => {
            'id': c.id,
            'name': c.name,
            'phone': c.phone,
            'is_vip': c.isVip ? 1 : 0,
          },
        )
        .toList()
      ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
  }

  Future<List<Map<String, dynamic>>> searchClients(String query) async {
    final all = await getClientsList();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((c) =>
            (c['name']?.toString() ?? '').toLowerCase().contains(q) ||
            (c['phone']?.toString() ?? '').toLowerCase().contains(q))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getClientCars(int clientId) async {
    await _ensureCars();
    return _cars.values
        .where((c) => c.clientId == clientId)
        .map(
          (c) => {
            'id': c.id,
            'client_id': c.clientId,
            'make_model': c.makeModel,
            'plate': c.plate,
            'vin': c.vin,
            'category': c.category,
          },
        )
        .toList();
  }

  Future<int> addCar(int clientId, String makeModel, String plate, {String vin = '', String category = '1'}) async {
    final car = await _crm.createCar(clientId: clientId, makeModel: makeModel, plate: plate);
    _cars[car.id] = car;
    return car.id;
  }

  Future<int> addClient(String name, String phone, {int isVip = 0}) async {
    final c = await _crm.createClient(name: name, phone: phone);
    if (isVip == 1) {
      final patched = await _crm.patchClient(c.id, {'is_vip': true});
      _clients[patched.id] = patched;
      return patched.id;
    }
    _clients[c.id] = c;
    return c.id;
  }

  Future<void> updateClientVip(int id, int isVip) async {
    final c = await _crm.patchClient(id, {'is_vip': isVip == 1});
    _clients[id] = c;
  }

  Future<void> deleteClient(int clientId) async {
    await _crm.deleteClient(clientId);
    final orderIds = _orders.values.where((o) => o.clientId == clientId).map((o) => o.id).toList();
    for (final id in orderIds) {
      _orders.remove(id);
    }
    _cars.removeWhere((_, c) => c.clientId == clientId);
    _clients.remove(clientId);
  }

  Future<void> deleteCar(int carId) async {
    await _crm.deleteCar(carId);
    final orderIds = _orders.values.where((o) => o.carId == carId).map((o) => o.id).toList();
    for (final id in orderIds) {
      _orders.remove(id);
    }
    _cars.remove(carId);
  }

  Future<List<Map<String, dynamic>>> getAllMastersFull() async {
    _masters = await _crm.listMasters();
    return _masters
        .where((m) => m.isActive)
        .map(
          (m) => {
            'id': m.id,
            'name': m.name,
            'role': m.role,
            'is_active': m.isActive ? 1 : 0,
          },
        )
        .toList();
  }

  Future<void> addMaster(String name, String role) async {
    final m = await _crm.createMaster(name: name, role: role);
    _masters = [..._masters, m];
  }

  Future<void> updateMaster(int id, {String? name, String? role}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (role != null) body['role'] = role;
    final m = await _crm.patchMaster(id, body);
    _masters = _masters.map((e) => e.id == id ? m : e).toList();
  }

  Future<void> deleteMasterById(int id) async {
    await _crm.deleteMaster(id);
    _masters = _masters.map((e) {
      if (e.id != id) return e;
      return CrmMaster(id: e.id, name: e.name, role: e.role, isActive: false);
    }).toList();
  }

  Future<void> deleteMaster(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    if (_masters.isEmpty) {
      _masters = await _crm.listMasters();
    }
    final match = _masters.where((e) => e.name == n && e.isActive).toList();
    if (match.isEmpty) return;
    await deleteMasterById(match.first.id);
  }

  Future<List<Map<String, dynamic>>> getAllServices() async {
    _services = await _crm.listServices();
    return _services
        .where((s) => s.isActive)
        .map(
          (s) => {
            'id': s.id,
            'name': s.name,
            'category': s.category,
            'price': s.price,
            'workshop': s.workshop,
            'is_active': 1,
            // локальный прайс ждёт колонки вроде price_1 — дублируем
            'price_1': s.price,
            'price_2': s.price,
            'price_3': s.price,
          },
        )
        .toList();
  }

  Future<void> deleteService(int id) async {
    await _crm.deleteService(id);
    _services = _services.where((e) => e.id != id).toList();
  }

  Future<void> updateServicePrice(String name, String field, double price) async {
    final s = _services.where((e) => e.name == name).toList();
    if (s.isEmpty) {
      _services = await _crm.listServices();
    }
    final match = _services.where((e) => e.name == name);
    if (match.isEmpty) return;
    final svc = match.first;
    await _crm.patchService(svc.id, {'price': price});
    _services = await _crm.listServices();
  }

  Future<List<Map<String, dynamic>>> getInventory() async {
    _inventory = await _crm.listInventory();
    return _inventory
        .map(
          (i) => {
            'id': i.id,
            'name': i.name,
            'quantity': i.quantity,
            'unit': i.unit,
            'category': i.category,
            'min_qty': i.minQty,
            'meters_per_roll': i.metersPerRoll,
          },
        )
        .toList();
  }

  Future<int> addInventoryItem(
    String name,
    double quantity,
    String unit, {
    double minQty = 0,
    String category = 'Прочее',
    double metersPerRoll = 0,
  }) async {
    final item = await _crm.createInventory(
      name: name,
      quantity: quantity,
      unit: unit,
      category: category,
      minQty: minQty,
      metersPerRoll: metersPerRoll,
    );
    _inventory = await _crm.listInventory();
    return item.id;
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
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (quantity != null) body['quantity'] = quantity;
    if (unit != null) body['unit'] = unit;
    if (minQty != null) body['min_qty'] = minQty;
    if (category != null) body['category'] = category;
    if (metersPerRoll != null) body['meters_per_roll'] = metersPerRoll;
    if (body.isEmpty) return;
    await _crm.patchInventory(id, body);
    _inventory = await _crm.listInventory();
  }

  Future<void> deleteInventoryItem(int id) async {
    await _crm.deleteInventoryItem(id);
    _inventory = _inventory.where((e) => e.id != id).toList();
  }

  Future<List<Map<String, dynamic>>> getOrderDefects(int orderId) async {
    final rows = await _crm.listDefects(orderId);
    return rows.map(_defectToLocalMap).toList();
  }

  Future<int> addOrderDefect({
    required int orderId,
    String workshop = '',
    String description = '',
    required List<String> photosB64,
  }) async {
    final photos = photosB64.where((p) => p.isNotEmpty).toList();
    if (photos.isEmpty) {
      final created = await _crm.addDefect(
        orderId,
        description: description,
        workshop: workshop,
        photoB64: '',
      );
      return (created['id'] as num).toInt();
    }
    // Первое фото — основной дефект; остальные — отдельные строки «фото N».
    final first = await _crm.addDefect(
      orderId,
      description: description,
      workshop: workshop,
      photoB64: photos.first,
    );
    final firstId = (first['id'] as num).toInt();
    for (var i = 1; i < photos.length; i++) {
      final suffix = description.trim().isEmpty
          ? 'фото ${i + 1}'
          : '${description.trim()} · фото ${i + 1}';
      await _crm.addDefect(
        orderId,
        description: suffix,
        workshop: workshop,
        photoB64: photos[i],
      );
    }
    return firstId;
  }

  Future<void> deleteOrderDefect(int defectId) async {
    await _crm.deleteDefect(defectId);
  }

  Map<String, dynamic> _defectToLocalMap(Map<String, dynamic> d) {
    final raw = (d['photo_b64'] ?? '').toString();
    final photos = <Map<String, dynamic>>[];
    if (raw.isNotEmpty) {
      if (raw.trimLeft().startsWith('[')) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final e in decoded) {
              final p = e.toString();
              if (p.isNotEmpty) photos.add({'photo_b64': p});
            }
          } else {
            photos.add({'photo_b64': raw});
          }
        } catch (_) {
          photos.add({'photo_b64': raw});
        }
      } else {
        photos.add({'photo_b64': raw});
      }
    }
    return {
      'id': (d['id'] as num).toInt(),
      'order_id': (d['order_id'] as num).toInt(),
      'workshop': d['workshop']?.toString() ?? '',
      'description': d['description']?.toString() ?? '',
      'photo_b64': photos.isEmpty ? '' : photos.first['photo_b64'],
      'created_at': d['created_at']?.toString() ?? '',
      'photos': photos,
    };
  }

  Future<void> adjustInventoryQuantity(
    int id,
    double delta, {
    String reason = 'manual',
    int? orderId,
    String note = '',
  }) async {
    await _crm.inventoryMove(
      itemId: id,
      delta: delta,
      reason: reason,
      orderId: orderId,
      note: note,
    );
    _inventory = await _crm.listInventory();
  }

  Future<List<Map<String, dynamic>>> getInventoryMoves({int? itemId, int limit = 100}) async {
    return _crm.listInventoryMoves(itemId: itemId, limit: limit);
  }

  Future<List<Map<String, dynamic>>> getRecipesForService(String serviceName) async {
    return _crm.listRecipes(serviceName);
  }

  Future<void> setRecipeLine(String serviceName, int inventoryId, double qty) async {
    await _crm.upsertRecipe(serviceName: serviceName, inventoryId: inventoryId, qty: qty);
  }

  Future<void> deleteRecipeLine(int recipeId) async {
    await _crm.deleteRecipe(recipeId);
  }

  Future<List<String>> deductRecipeForService(
    String serviceName, {
    int? orderId,
    int? orderItemId,
  }) async {
    return _crm.deductRecipe(serviceName: serviceName, orderId: orderId);
  }

  Future<void> restoreRecipeForService(
    String serviceName, {
    int? orderId,
    int? orderItemId,
  }) async {
    await _crm.restoreRecipe(serviceName: serviceName, orderId: orderId);
  }

  Future<Map<String, List<Map<String, dynamic>>>> searchGlobal(String q) async {
    await refreshAll();
    final query = q.trim().toLowerCase();
    final clients = _clients.values
        .where((c) => c.name.toLowerCase().contains(query) || c.phone.contains(query))
        .map((c) => {'id': c.id, 'name': c.name, 'phone': c.phone})
        .take(20)
        .toList();
    final orders = _orders.values
        .where((o) {
          final hay = '${o.id} ${o.clientName} ${o.carLabel}'.toLowerCase();
          return hay.contains(query);
        })
        .map(orderToMap)
        .take(20)
        .toList();
    return {'clients': clients, 'orders': orders, 'cars': <Map<String, dynamic>>[]};
  }

  // --- Cash (упрощённый маппинг под CashScreen) ---

  Future<List<Map<String, dynamic>>> getCashRegisters() async {
    final regs = await _cash.listRegisters();
    return regs
        .map(
          (r) => {
            'id': r.id,
            'name': r.name,
            'money_type': r.moneyType,
            'is_active': r.isActive ? 1 : 0,
          },
        )
        .toList();
  }

  Future<int> addCashRegister(String name, String moneyType, {int sortOrder = 100}) async {
    final r = await _cash.createRegister(
      name: name.trim(),
      moneyType: moneyType,
      sortOrder: sortOrder,
    );
    return r.id;
  }

  Future<void> setCashRegisterActive(int registerId, bool active) async {
    await _cash.patchRegister(registerId, isActive: active);
  }

  Future<Map<String, dynamic>?> getCurrentShift() async {
    final s = await _cash.currentShift();
    if (s == null || !s.isOpen) return null;
    return s.toLocalMap();
  }

  Future<List<Map<String, dynamic>>> getCashJournal(String start, String end) async {
    final journal = await _cash.journal(from: start, to: end);
    return journal.map(_journalToMap).toList();
  }

  Map<String, dynamic> _journalToMap(CloudCashJournalEntry e) {
    final isPayment = e.kind == 'payment';
    return {
      'id': e.id,
      'kind': e.kind,
      'source': e.kind,
      'type': isPayment ? 'Приход' : (e.flowType ?? 'Приход'),
      'amount': e.amount,
      'method': e.method.isEmpty ? 'Наличные' : e.method,
      'category': e.category.isEmpty ? (isPayment ? 'Оплата заказа' : 'Прочее') : e.category,
      'description': e.title,
      'title': e.title,
      'created_at': e.createdAt?.toIso8601String() ?? '',
      'register_name': e.registerName,
      'order_id': e.orderId,
      'shift_id': e.shiftId,
      'is_voided': e.isVoided ? 1 : 0,
    };
  }

  Future<List<Map<String, dynamic>>> getShiftRegisterSnapshots(int shiftId) async {
    CloudCashShift? s;
    try {
      final cur = await _cash.currentShift();
      if (cur != null && cur.id == shiftId) {
        s = cur;
      } else {
        s = await _cash.getShift(shiftId);
      }
    } catch (_) {
      s = await _cash.currentShift();
    }
    if (s == null) return getCashRegisters();
    return s.balances
        .map(
          (b) => {
            'id': b.registerId,
            'name': b.registerName ?? 'Касса',
            'money_type': b.moneyType ?? '',
            'opening': b.opening,
            'expected': b.expected ?? b.opening,
            'fact': b.fact,
            if (b.fact != null && b.expected != null) 'difference': b.fact! - b.expected!,
          },
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> getOrderDebts({int limit = 50}) async {
    await _ensureOrders();
    await _ensureClients();
    return _orders.values
        .where((o) => o.debt > 0.01 && o.status != 'Выдан')
        .map(orderToMap)
        .take(limit)
        .toList();
  }

  Future<double> getTotalDebt() async {
    await _ensureOrders();
    return _orders.values
        .where((o) => o.status != 'Выдан')
        .fold<double>(0, (sum, o) {
      final d = o.price - o.paidAmount;
      return sum + (d > 0.01 ? d : 0);
    });
  }

  Future<List<Map<String, dynamic>>> getOrderPayments(int orderId) async {
    final list = await _cash.listPayments(orderId: orderId);
    return list.map(_paymentToLocal).toList();
  }

  Map<String, dynamic> _paymentToLocal(Map<String, dynamic> p) {
    var created = p['created_at']?.toString() ?? '';
    if (created.length >= 16) {
      created = created.substring(0, 16).replaceFirst('T', ' ');
    }
    return {
      'id': (p['id'] as num).toInt(),
      'order_id': (p['crm_order_id'] as num?)?.toInt() ?? (p['order_id'] as num?)?.toInt(),
      'amount': (p['amount'] as num?)?.toDouble() ?? 0,
      'method': p['method']?.toString() ?? '',
      'created_at': created,
      'shift_id': (p['shift_id'] as num?)?.toInt(),
      'register_id': (p['register_id'] as num?)?.toInt(),
    };
  }

  Future<List<Map<String, dynamic>>> getOrderEvents(int orderId) async {
    final list = await _crm.listOrderEvents(orderId);
    return list
        .map(
          (e) => {
            'id': e.id,
            'order_id': e.orderId,
            'event_text': e.eventText,
            'created_at': e.createdAt,
          },
        )
        .toList();
  }

  Future<void> addOrderEvent(int orderId, String text) async {
    await _crm.createOrderEvent(orderId, text);
  }

  Future<Map<String, dynamic>> getOrderHandover(int orderId) async {
    final o = await getOrderById(orderId);
    if (o == null) {
      return {
        'handover_works': 0,
        'handover_inspect': 0,
        'handover_payment': 0,
        'handover_keys': 0,
        'handover_notified': 0,
        'handover_ready': 0,
      };
    }
    return {
      'handover_works': o['handover_works'] ?? 0,
      'handover_inspect': o['handover_inspect'] ?? 0,
      'handover_payment': o['handover_payment'] ?? 0,
      'handover_keys': o['handover_keys'] ?? 0,
      'handover_notified': o['handover_notified'] ?? 0,
      'handover_ready': o['handover_ready'] ?? 0,
    };
  }

  Future<void> saveOrderHandover(int orderId, Map<String, dynamic> values) async {
    final body = <String, dynamic>{};
    for (final k in const [
      'handover_ready',
      'handover_works',
      'handover_payment',
      'handover_keys',
      'handover_inspect',
      'handover_notified',
    ]) {
      if (values.containsKey(k)) {
        final v = values[k];
        body[k] = v == true || v == 1 || v == '1';
      }
    }
    if (body.isEmpty) return;
    final o = await _crm.patchOrder(orderId, body);
    _orders[o.id] = o;
  }

  Future<void> setTechWash(int orderId, String? startDate, String? endDate) async {
    final o = await _crm.patchOrder(orderId, {
      'tech_wash_start': startDate ?? '',
      'tech_wash_end': endDate ?? '',
    });
    _orders[o.id] = o;
  }

  Future<void> setWorkshopTaskCompleted(int orderId, int isCompleted) async {
    final o = await _crm.patchOrder(orderId, {
      'is_workshop_completed': isCompleted == 1,
    });
    _orders[o.id] = o;
  }

  String? _dayPart(String? raw) {
    if (raw == null) return null;
    final s = raw.replaceFirst('T', ' ').trim();
    if (s.isEmpty) return null;
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  bool _spansDay(String? start, String? end, String dateStr) {
    final s = _dayPart(start);
    if (s == null) return false;
    final e = _dayPart((end != null && end.trim().isNotEmpty) ? end : start) ?? s;
    return s.compareTo(dateStr) <= 0 && e.compareTo(dateStr) >= 0;
  }

  Future<List<Map<String, dynamic>>> getOrdersForCalendar(String dateStr) async {
    await _ensureOrders();
    await _ensureClients();
    await _ensureCars();
    final out = <Map<String, dynamic>>[];
    for (final o in _orders.values) {
      if (o.status == 'Выдан') continue;
      final bySchedule = _spansDay(o.startTime, o.endTime, dateStr);
      final byDue = _dayPart(o.dueDate) == dateStr;
      final byEnd = _dayPart(o.endDate) == dateStr;
      final byWash = _spansDay(
        o.techWashStart.isEmpty ? null : o.techWashStart,
        o.techWashEnd.isEmpty ? null : o.techWashEnd,
        dateStr,
      );
      if (!(bySchedule || byDue || byEnd || byWash)) continue;
      final client = _clients[o.clientId];
      final car = _cars[o.carId];
      out.add({
        'id': o.id,
        'status': o.status,
        'price': o.price,
        'paid_amount': o.paidAmount,
        'start_time': o.startTime.isEmpty ? null : o.startTime,
        'end_time': o.endTime.isEmpty ? null : o.endTime,
        'due_date': o.dueDate,
        'tech_wash_start': o.techWashStart.isEmpty ? null : o.techWashStart,
        'tech_wash_end': o.techWashEnd.isEmpty ? null : o.techWashEnd,
        'client_name': o.clientName ?? client?.name ?? '',
        'make_model': car?.makeModel ?? '',
        'plate': car?.plate ?? '',
      });
    }
    out.sort((a, b) => (a['start_time']?.toString() ?? '').compareTo(b['start_time']?.toString() ?? ''));
    return out;
  }

  Future<List<Map<String, dynamic>>> getOrderItemsForCalendar(String dateStr) async {
    await _ensureOrders();
    await _ensureClients();
    await _ensureCars();
    final out = <Map<String, dynamic>>[];
    for (final o in _orders.values) {
      if (o.status == 'Выдан') continue;
      final client = _clients[o.clientId];
      final car = _cars[o.carId];
      for (final it in o.items) {
        final start = it.startTime.trim().isNotEmpty ? it.startTime : o.startTime;
        final end = it.endTime.trim().isNotEmpty ? it.endTime : o.endTime;
        if (!_spansDay(start, end, dateStr)) continue;
        var ws = it.workshop.trim();
        if (ws.isEmpty) {
          ws = _workshopFromName(it.name) ?? '';
        }
        if (ws.isEmpty) continue;
        out.add({
          'item_id': it.id ?? 0,
          'order_id': o.id,
          'work_name': it.name,
          'start_time': start,
          'end_time': end,
          'workshop': ws,
          'is_done': it.isDone ? 1 : 0,
          'parent_id': it.parentId,
          'status': o.status,
          'price': o.price,
          'paid_amount': o.paidAmount,
          'client_name': o.clientName ?? client?.name ?? '',
          'make_model': car?.makeModel ?? '',
          'plate': car?.plate ?? '',
        });
      }
    }
    out.sort((a, b) => (a['start_time']?.toString() ?? '').compareTo(b['start_time']?.toString() ?? ''));
    return out;
  }

  String? _workshopFromName(String? name) {
    final blob = (name ?? '').toLowerCase();
    if (blob.isEmpty) return null;
    const workshops = ['Химчистка', 'Полировка', 'Оклейка', 'Интерьер', 'Оборудование', 'Мойка'];
    for (final w in workshops) {
      if (blob.contains(w.toLowerCase())) return w;
    }
    if (blob.contains('химчист')) return 'Химчистка';
    if (blob.contains('полир') || blob.contains('керамик') || blob.contains('силант')) return 'Полировка';
    if (blob.contains('оклей') || blob.contains('пленк') || blob.contains('тонир')) return 'Оклейка';
    if (blob.contains('интерьер') || blob.contains('салон')) return 'Интерьер';
    if (blob.contains('оборуд') || blob.contains('двигател')) return 'Оборудование';
    if (blob.contains('мойк') || blob.contains('багаж')) return 'Мойка';
    return null;
  }

  Future<void> syncZonePackage({
    required int orderId,
    required String kind,
    required List<String> zoneNames,
    required double packagePrice,
  }) async {
    await _ensureOrders();
    final workshop = 'Оклейка';
    final headerName = kind == 'tint' ? 'Тонировка' : 'Оклейка';
    final wanted = zoneNames.map((n) => n.trim()).where((n) => n.isNotEmpty).toSet();

    if (wanted.isEmpty) {
      final order = _orders[orderId];
      if (order != null) {
        CrmOrderItem? header;
        for (final it in order.items) {
          if (it.name.trim() == headerName && it.parentId == null) {
            header = it;
            break;
          }
        }
        if (header?.id != null) {
          await _crm.deleteOrderItem(orderId, header!.id!);
        }
      }
      await _refreshOrder(orderId);
      return;
    }

    final headerId = await _ensureZonePackage(orderId, kind);
    await _crm.patchOrderItem(orderId, headerId, {
      'price': packagePrice,
      'workshop': workshop,
    });

    await _refreshOrder(orderId);
    final order = _orders[orderId];
    if (order == null) return;
    final children = order.items.where((it) => it.parentId == headerId).toList();
    final byName = {for (final c in children) c.name.trim(): c};

    for (final name in wanted) {
      if (byName.containsKey(name)) continue;
      await _crm.createOrderItem(
        orderId,
        CrmOrderItem(
          name: name,
          price: 0,
          workshop: workshop,
          parentId: headerId,
        ),
      );
    }
    for (final entry in byName.entries) {
      if (wanted.contains(entry.key)) continue;
      final id = entry.value.id;
      if (id != null) await _crm.deleteOrderItem(orderId, id);
    }
    await _refreshOrder(orderId);
  }

  Future<int> _ensureZonePackage(int orderId, String kind) async {
    await _ensureOrders();
    var order = _orders[orderId];
    if (order == null) {
      await _refreshOrder(orderId);
      order = _orders[orderId];
    }
    if (order == null) throw StateError('Заказ $orderId не найден');
    final headerName = kind == 'tint' ? 'Тонировка' : 'Оклейка';
    for (final it in order.items) {
      if (it.name.trim() == headerName && it.parentId == null && it.id != null) {
        return it.id!;
      }
    }
    final created = await _crm.createOrderItem(
      orderId,
      CrmOrderItem(
        name: headerName,
        price: 0,
        workshop: 'Оклейка',
      ),
    );
    await _refreshOrder(orderId);
    return created.id ?? 0;
  }

  bool _isWrapHeader(String? name) => (name ?? '').trim() == 'Оклейка';
  bool _isTintHeader(String? name) => (name ?? '').trim() == 'Тонировка';
  bool _isZoneHeader(String? name) => _isWrapHeader(name) || _isTintHeader(name);

  bool _isWrapLine({String? category, String? name}) {
    final n = (name ?? '').trim();
    if (n.isEmpty || _isWrapHeader(n)) return false;
    if (n.startsWith('Тонировка')) return false;
    if (n.startsWith('Оклейка ·')) return true;
    if ((category ?? '').trim() == 'Оклейка (Пленка)') return true;
    if (n == 'Оклейка капота' || n == 'Оклейка крыши' || n == 'Полная оклейка кузова') return true;
    return false;
  }

  bool _isTintLine({String? category, String? name}) {
    final n = (name ?? '').trim();
    if (n.isEmpty || _isTintHeader(n)) return false;
    if (n.startsWith('Тонировка ·') || n.startsWith('Тонировка ')) return true;
    if ((category ?? '').trim() == 'Тонировка') return true;
    return false;
  }

  Future<int> addOrderWithItems(
    int clientId,
    int carId,
    List<Map<String, dynamic>> items, {
    String? status,
    String dueDate = '',
    String startTime = '',
    String endTime = '',
    String endDate = '',
  }) async {
    final crmItems = items
        .map(
          (i) => CrmOrderItem(
            name: i['name']?.toString() ?? 'Работа',
            price: (i['price'] as num?)?.toDouble() ?? 0,
            workshop: i['workshop']?.toString() ?? '',
          ),
        )
        .toList();
    if (crmItems.isEmpty) {
      crmItems.add(const CrmOrderItem(name: 'Работа', price: 0));
    }
    final resolved = status ?? 'Принят в работу';
    final order = await _crm.createOrder(
      clientId: clientId,
      carId: carId,
      items: crmItems,
      status: resolved,
      dueDate: dueDate.isNotEmpty ? dueDate : DateTime.now().toIso8601String().substring(0, 10),
      masterIds: const [],
    );
    // start/end через patch
    if (startTime.isNotEmpty || endTime.isNotEmpty || dueDate.isNotEmpty) {
      final patched = await _crm.patchOrder(order.id, {
        if (dueDate.isNotEmpty) 'due_date': dueDate,
        if (startTime.isNotEmpty) 'start_time': startTime,
        if (endTime.isNotEmpty) 'end_time': endTime,
      });
      _orders[patched.id] = patched;
      return patched.id;
    }
    _orders[order.id] = order;
    return order.id;
  }

  Future<CrmOrder?> _orderByItemId(int itemId) async {
    await _ensureOrders();
    for (final o in _orders.values) {
      if (o.items.any((i) => i.id == itemId)) return o;
    }
    final list = await _crm.listOrders();
    _orders
      ..clear()
      ..addEntries(list.map((o) => MapEntry(o.id, o)));
    for (final o in _orders.values) {
      if (o.items.any((i) => i.id == itemId)) return o;
    }
    return null;
  }

  Future<void> _refreshOrder(int orderId) async {
    final list = await _crm.listOrders();
    _orders
      ..clear()
      ..addEntries(list.map((o) => MapEntry(o.id, o)));
  }

  Future<void> syncOrderFromItems(int orderId) async {
    // Цена пересчитывается на сервере при item CRUD; здесь только refresh.
    await _refreshOrder(orderId);
  }

  Future<void> updateOrderItemSchedule(
    int itemId,
    String? startTime,
    String? endTime,
    String? workshop,
  ) async {
    if (itemId <= 0) return;
    final o = await _orderByItemId(itemId);
    if (o == null) return;
    await _crm.patchOrderItem(o.id, itemId, {
      if (workshop != null) 'workshop': workshop,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
    });
    await _refreshOrder(o.id);
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
    final asWrap = _isWrapLine(category: category, name: name);
    final asTint = _isTintLine(category: category, name: name);
    if (asWrap || asTint) {
      final kind = asTint ? 'tint' : 'wrap';
      final parentId = await _ensureZonePackage(orderId, kind);
      await _refreshOrder(orderId);
      final order = _orders[orderId];
      CrmOrderItem? header;
      if (order != null) {
        for (final it in order.items) {
          if (it.id == parentId) {
            header = it;
            break;
          }
        }
        for (final it in order.items) {
          if (it.parentId == parentId && it.name.trim() == name.trim()) {
            if (sync) await _refreshOrder(orderId);
            return it.id ?? 0;
          }
        }
      }
      final created = await _crm.createOrderItem(
        orderId,
        CrmOrderItem(
          name: name,
          price: 0,
          workshop: workshop ?? header?.workshop ?? 'Оклейка',
          masterIds: header?.masterIds ?? '',
          startTime: (header?.startTime.isNotEmpty == true) ? header!.startTime : (startTime ?? ''),
          endTime: (header?.endTime.isNotEmpty == true) ? header!.endTime : (endTime ?? ''),
          parentId: parentId,
        ),
      );
      if (price > 0 && (header?.price ?? 0) == 0) {
        await _crm.patchOrderItem(orderId, parentId, {'price': price});
      }
      await _refreshOrder(orderId);
      return created.id ?? 0;
    }

    final created = await _crm.createOrderItem(
      orderId,
      CrmOrderItem(
        name: name,
        price: price,
        workshop: workshop ?? '',
        startTime: startTime ?? '',
        endTime: endTime ?? '',
      ),
    );
    await _refreshOrder(orderId);
    return created.id ?? 0;
  }

  Future<void> deleteOrderItem(int itemId) async {
    if (itemId <= 0) return;
    final o = await _orderByItemId(itemId);
    if (o == null) return;
    final item = o.items.firstWhere((i) => i.id == itemId);
    if (_isZoneHeader(item.name) && item.parentId == null) {
      final kids = o.items.where((i) => i.parentId == itemId).toList();
      for (final k in kids) {
        if (k.id != null) await _crm.deleteOrderItem(o.id, k.id!);
      }
      await _crm.deleteOrderItem(o.id, itemId);
      await _refreshOrder(o.id);
      return;
    }
    final parentId = item.parentId;
    await _crm.deleteOrderItem(o.id, itemId);
    await _refreshOrder(o.id);
    if (parentId != null) {
      final refreshed = _orders[o.id];
      final left = refreshed?.items.where((i) => i.parentId == parentId).toList() ?? [];
      if (left.isEmpty) {
        await _crm.deleteOrderItem(o.id, parentId);
        await _refreshOrder(o.id);
      } else {
        await _syncZoneHeaderDone(o.id, parentId);
      }
    }
  }

  Future<List<String>> updateOrderItemDone(int itemId, bool isDone) async {
    if (itemId <= 0) return [];
    final o = await _orderByItemId(itemId);
    if (o == null) return [];
    CrmOrderItem? item;
    for (final i in o.items) {
      if (i.id == itemId) {
        item = i;
        break;
      }
    }
    if (item == null) return [];
    final wasDone = item.isDone;
    await _crm.patchOrderItem(o.id, itemId, {'is_done': isDone});
    await _refreshOrder(o.id);
    final warnings = <String>[];
    if (isDone && !wasDone) {
      warnings.addAll(await deductRecipeForService(item.name, orderId: o.id, orderItemId: itemId));
    } else if (!isDone && wasDone) {
      await restoreRecipeForService(item.name, orderId: o.id, orderItemId: itemId);
    }
    final parentId = item.parentId;
    if (parentId != null) {
      await _syncZoneHeaderDone(o.id, parentId);
    }
    return warnings;
  }

  Future<void> _syncZoneHeaderDone(int orderId, int headerId) async {
    await _refreshOrder(orderId);
    final order = _orders[orderId];
    if (order == null) return;
    CrmOrderItem? header;
    for (final it in order.items) {
      if (it.id == headerId) {
        header = it;
        break;
      }
    }
    if (header == null || header.parentId != null || !_isZoneHeader(header.name)) return;
    final children = order.items.where((it) => it.parentId == headerId).toList();
    if (children.isEmpty) return;
    final allDone = children.every((c) => c.isDone);
    if (header.isDone != allDone) {
      await _crm.patchOrderItem(orderId, headerId, {'is_done': allDone});
      await _refreshOrder(orderId);
    }
  }

  Future<void> updateOrderItemComment(int itemId, String comment) async {
    if (itemId <= 0) return;
    final o = await _orderByItemId(itemId);
    if (o == null) return;
    await _crm.patchOrderItem(o.id, itemId, {'comment': comment});
    await _refreshOrder(o.id);
  }

  Future<void> updateOrderItemMasters(int itemId, List<int> masterIds) async {
    if (itemId <= 0) return;
    final o = await _orderByItemId(itemId);
    if (o == null) return;
    await _crm.patchOrderItem(o.id, itemId, {'master_ids': masterIds.join(',')});
    await _refreshOrder(o.id);
  }

  Future<void> updateOrderItemPrice(int itemId, double price) async {
    if (itemId <= 0) return;
    final o = await _orderByItemId(itemId);
    if (o == null) return;
    await _crm.patchOrderItem(o.id, itemId, {'price': price});
    await _refreshOrder(o.id);
  }

  Future<void> updateOrderPrice(int orderId, double price) async {
    // Цена считается из items на сервере; принудительно через notes-only не трогаем.
    await getOrderById(orderId);
  }

  Future<void> updateOrderDiscount(
    int orderId, {
    double? discountPercent,
    double? discountFixed,
    String? promoCode,
  }) async {
    final body = <String, dynamic>{};
    if (discountPercent != null) body['discount_percent'] = discountPercent;
    if (discountFixed != null) body['discount_fixed'] = discountFixed;
    if (promoCode != null) body['promo_code'] = promoCode;
    if (body.isEmpty) return;
    final o = await _crm.patchOrder(orderId, body);
    _orders[o.id] = o;
  }

  Future<void> updateOrderMaster(int orderId, int? masterId) async {
    await _crm.patchOrder(orderId, {
      'master_ids': masterId == null ? <int>[] : [masterId],
    }).then((o) => _orders[o.id] = o);
  }

  Future<void> updateOrderSchedule(
    int orderId,
    String dueDate,
    String startTime,
    String endTime,
    String endDate,
  ) async {
    final o = await _crm.patchOrder(orderId, {
      'due_date': dueDate.isNotEmpty ? dueDate : endDate,
      'start_time': startTime,
      'end_time': endTime,
      'end_date': endDate.isNotEmpty ? endDate : dueDate,
    });
    _orders[o.id] = o;
  }

  Future<void> updateOrderNotes(int orderId, String notes) async {
    final o = await _crm.patchOrder(orderId, {'notes': notes});
    _orders[o.id] = o;
  }

  Future<void> updateOrderClientNotes(int orderId, String notes) async {
    final o = await _crm.patchOrder(orderId, {'client_notes': notes});
    _orders[o.id] = o;
  }

  Future<void> updateOrderClientVisibleNotes(int orderId, String notes) async {
    final o = await _crm.patchOrder(orderId, {'client_visible_notes': notes});
    _orders[o.id] = o;
  }

  Future<void> updateOrderMasterNotes(int orderId, String notes) async {
    final o = await _crm.patchOrder(orderId, {'master_notes': notes});
    _orders[o.id] = o;
  }

  Future<void> updateOrderPaymentMethod(int orderId, String method) async {
    final o = await _crm.patchOrder(orderId, {'payment_method': method});
    _orders[o.id] = o;
  }

  Future<Map<String, dynamic>?> getClientByPhone(String phone) async {
    await _ensureClients();
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final tail = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
    for (final c in _clients.values) {
      final p = c.phone.replaceAll(RegExp(r'\D'), '');
      final t = p.length >= 10 ? p.substring(p.length - 10) : p;
      if (t == tail && tail.isNotEmpty) {
        return {'id': c.id, 'name': c.name, 'phone': c.phone, 'is_vip': c.isVip ? 1 : 0};
      }
      if (c.phone == phone.trim()) {
        return {'id': c.id, 'name': c.name, 'phone': c.phone, 'is_vip': c.isVip ? 1 : 0};
      }
    }
    return null;
  }

  Future<int?> getCarId(int clientId, String plate) async {
    await _ensureCars();
    final p = plate.trim().toLowerCase();
    for (final c in _cars.values) {
      if (c.clientId == clientId && c.plate.trim().toLowerCase() == p) return c.id;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getClientCarsForDropdown(String phone) async {
    final client = await getClientByPhone(phone);
    if (client == null) return [];
    return getClientCars(client['id'] as int);
  }

  Future<void> updateCar(
    int carId, {
    String? makeModel,
    String? plate,
    String? vin,
    String? category,
  }) async {
    final body = <String, dynamic>{};
    if (makeModel != null) body['make_model'] = makeModel;
    if (plate != null) body['plate'] = plate;
    if (vin != null) body['vin'] = vin;
    if (category != null) body['category'] = category;
    if (body.isEmpty) return;
    final car = await _crm.patchCar(carId, body);
    _cars[car.id] = car;
  }

  Future<void> reassignOrderCar(int orderId, int carId) async {
    final o = await _crm.patchOrder(orderId, {'car_id': carId});
    _orders[o.id] = o;
  }

  Future<int?> resolveRegisterIdForMethod(String method) async {
    final regs = await _cash.listRegisters();
    for (final r in regs) {
      if (r.isActive && r.moneyType == method) return r.id;
    }
    return regs.isEmpty ? null : regs.first.id;
  }

  Future<void> addPayment(
    int orderId,
    double amount,
    String method, {
    int? shiftId,
    int? registerId,
  }) async {
    var shift = await _cash.currentShift();
    if (shift == null || !shift.isOpen) {
      await _cash.openShift();
    }
    await _cash.createPayment(
      orderId: orderId,
      amount: amount,
      method: method,
      registerId: registerId,
    );
    final list = await _crm.listOrders();
    _orders
      ..clear()
      ..addEntries(list.map((o) => MapEntry(o.id, o)));
  }

  Future<bool> updatePayment(
    int paymentId, {
    required double amount,
    required String method,
    int? registerId,
  }) async {
    if (amount <= 0) return false;
    try {
      final updated = await _cash.patchPayment(
        paymentId,
        amount: amount,
        method: method,
        registerId: registerId,
      );
      final orderId = (updated['crm_order_id'] as num?)?.toInt();
      if (orderId != null) {
        await _refreshOrder(orderId);
      } else {
        final list = await _crm.listOrders();
        _orders
          ..clear()
          ..addEntries(list.map((o) => MapEntry(o.id, o)));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> voidPayment(int paymentId) async {
    try {
      final voided = await _cash.voidPayment(paymentId);
      final orderId = (voided['crm_order_id'] as num?)?.toInt();
      if (orderId != null) {
        await _refreshOrder(orderId);
      }
      return _paymentToLocal(voided);
    } catch (_) {
      return null;
    }
  }

  Future<int> openCashShift(double openingCash, {String note = '', Map<int, double>? openings}) async {
    final existing = await _cash.currentShift();
    if (existing != null && existing.isOpen) return existing.id;
    final s = await _cash.openShift(openings: openings, note: note);
    return s.id;
  }

  Future<void> closeCashShift(
    int shiftId,
    double factCash, {
    String note = '',
    Map<int, double>? facts,
  }) async {
    var resolved = facts;
    if (resolved == null || resolved.isEmpty) {
      final snaps = await getShiftRegisterSnapshots(shiftId);
      resolved = {};
      for (final s in snaps) {
        final rid = (s['id'] as num).toInt();
        final expected = (s['expected'] as num?)?.toDouble() ?? 0;
        final moneyType = s['money_type']?.toString() ?? '';
        resolved[rid] = moneyType == 'Наличные' ? factCash : expected;
      }
    }
    await _cash.closeShift(shiftId, facts: resolved, note: note);
  }

  Future<List<Map<String, dynamic>>> getRecentShifts({int limit = 20}) async {
    final list = await _cash.listShifts(limit: limit);
    return list.map((s) => s.toLocalMap()).toList();
  }

  Future<Map<String, dynamic>?> getCashShiftById(int shiftId) async {
    try {
      final s = await _cash.getShift(shiftId);
      return s.toLocalMap();
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getCashJournalForShift(int shiftId) async {
    final journal = await _cash.journal(shiftId: shiftId);
    return journal.map(_journalToMap).toList();
  }

  Map<String, dynamic> _flowToLocal(Map<String, dynamic> f) {
    var created = f['created_at']?.toString() ?? '';
    if (created.length >= 16) {
      created = created.substring(0, 16).replaceFirst('T', ' ');
    }
    return {
      'id': (f['id'] as num).toInt(),
      'type': f['type']?.toString() ?? '',
      'amount': (f['amount'] as num?)?.toDouble() ?? 0,
      'description': f['description']?.toString() ?? '',
      'category': f['category']?.toString() ?? 'Прочее',
      'method': f['method']?.toString() ?? 'Наличные',
      'register_id': (f['register_id'] as num?)?.toInt(),
      'shift_id': (f['shift_id'] as num?)?.toInt(),
      'counterparty': f['counterparty']?.toString() ?? '',
      'master_id': (f['master_id'] as num?)?.toInt(),
      'inventory_id': (f['inventory_id'] as num?)?.toInt(),
      'inventory_qty': (f['inventory_qty'] as num?)?.toDouble() ?? 0,
      'order_id': (f['order_id'] as num?)?.toInt(),
      'template_key': f['template_key']?.toString() ?? '',
      'note': f['note']?.toString() ?? '',
      'created_at': created,
      'master_name': f['master_name']?.toString(),
      'inventory_name': f['inventory_name']?.toString(),
    };
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
    final created = await _cash.createFlow(
      type: type,
      amount: amount,
      method: method,
      category: category,
      description: description,
      note: note,
      registerId: registerId,
      counterparty: counterparty,
      masterId: masterId,
      inventoryId: inventoryId,
      inventoryQty: inventoryQty,
      orderId: orderId,
      templateKey: templateKey,
    );
    return (created['id'] as num).toInt();
  }

  Future<Map<String, dynamic>?> getCashFlowById(int id) async {
    try {
      return _flowToLocal(await _cash.getFlow(id));
    } catch (_) {
      return null;
    }
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
    try {
      await _cash.updateFlow(
        id,
        type: type,
        amount: amount,
        description: description,
        category: category,
        method: method,
        registerId: registerId,
        counterparty: counterparty,
        masterId: masterId,
        inventoryId: inventoryId,
        inventoryQty: inventoryQty,
        templateKey: templateKey,
        note: note,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteCashFlow(int id) async {
    try {
      await _cash.deleteFlow(id);
      return true;
    } catch (_) {
      return false;
    }
  }

  // Wrap / tint packages
  Future<List<String>> updateWrapPackageDone(int headerId, bool isDone) async {
    final o = await _orderByItemId(headerId);
    if (o == null) return [];
    final children = o.items.where((it) => it.parentId == headerId).toList();
    final warnings = <String>[];
    warnings.addAll(await updateOrderItemDone(headerId, isDone));
    for (final c in children) {
      if (c.id == null) continue;
      warnings.addAll(await updateOrderItemDone(c.id!, isDone));
    }
    return warnings;
  }

  Future<void> updateWrapPackageSchedule(int headerId, String? startTime, String? endTime) async {
    final o = await _orderByItemId(headerId);
    if (o == null) return;
    final header = o.items.firstWhere((it) => it.id == headerId);
    final workshop = header.workshop.isNotEmpty ? header.workshop : 'Оклейка';
    final body = {
      'start_time': startTime ?? '',
      'end_time': endTime ?? '',
      'workshop': workshop,
    };
    await _crm.patchOrderItem(o.id, headerId, body);
    for (final c in o.items.where((it) => it.parentId == headerId)) {
      if (c.id == null) continue;
      await _crm.patchOrderItem(o.id, c.id!, body);
    }
    await _refreshOrder(o.id);
  }

  Future<void> updateWrapPackageMasters(int headerId, List<int> masterIds) async {
    final o = await _orderByItemId(headerId);
    if (o == null) return;
    final csv = masterIds.join(',');
    await _crm.patchOrderItem(o.id, headerId, {'master_ids': csv});
    for (final c in o.items.where((it) => it.parentId == headerId)) {
      if (c.id == null) continue;
      await _crm.patchOrderItem(o.id, c.id!, {'master_ids': csv});
    }
    await _refreshOrder(o.id);
  }

  Future<int> assignMastersToWorkshop(int orderId, String workshop, List<int> masterIds) async {
    await _ensureOrders();
    final o = _orders[orderId];
    if (o == null) {
      await _refreshOrder(orderId);
    }
    final order = _orders[orderId];
    if (order == null) return 0;
    final csv = masterIds.join(',');
    var updated = 0;
    const workshops = {'Мойка', 'Химчистка', 'Полировка', 'Оклейка', 'Интерьер', 'Оборудование'};
    for (final it in order.items) {
      if ((it.name).trim() == 'Оклейка' && it.parentId == null) continue;
      var resolved = it.workshop.trim();
      if (resolved.isEmpty || !workshops.contains(resolved)) {
        resolved = _workshopFromName(it.name) ?? '';
      }
      if (resolved != workshop) continue;
      if (it.id == null || it.id! <= 0) continue;
      await _crm.patchOrderItem(orderId, it.id!, {'master_ids': csv});
      updated++;
    }
    if (masterIds.isNotEmpty) {
      await updateOrderMaster(orderId, masterIds.first);
    } else {
      await updateOrderMaster(orderId, null);
    }
    await _refreshOrder(orderId);
    return updated;
  }

  Future<String> getWorkshopMasterNames(int orderId, String workshop) async {
    await _ensureOrders();
    await _ensureMasters();
    final order = _orders[orderId];
    if (order == null) return '';
    const workshops = {'Мойка', 'Химчистка', 'Полировка', 'Оклейка', 'Интерьер', 'Оборудование'};
    final idSet = <int>{};
    for (final it in order.items) {
      var resolved = it.workshop.trim();
      if (resolved.isEmpty || !workshops.contains(resolved)) {
        resolved = _workshopFromName(it.name) ?? '';
      }
      if (resolved != workshop) continue;
      for (final part in it.masterIds.split(',')) {
        final id = int.tryParse(part.trim());
        if (id != null) idSet.add(id);
      }
    }
    if (idSet.isEmpty) return '';
    final byId = {for (final m in _masters) m.id: m.name};
    return idSet.map((id) => byId[id] ?? '').where((n) => n.isNotEmpty).join(', ');
  }

  Future<void> _ensureMasters() async {
    if (_masters.isNotEmpty) return;
    _masters = await _crm.listMasters();
  }

  Future<List<Map<String, dynamic>>> listWrapFilms({List<String>? categories}) async {
    var list = await _crm.listWrapFilms();
    if (categories != null && categories.isNotEmpty) {
      list = list.where((f) => categories.contains(f['inventory_category']?.toString())).toList();
    }
    return list;
  }

  Future<int> addWrapFilm(
    String name, {
    String category = 'Плёнка оклейка',
    double metersPerRoll = 0,
    String unit = 'м',
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', 'Название плёнки не может быть пустым');
    final existing = await listWrapFilms();
    for (final f in existing) {
      if ((f['name']?.toString() ?? '').trim().toLowerCase() == trimmed.toLowerCase()) {
        return (f['id'] as num).toInt();
      }
    }
    // В облаке film id == inventory id (listWrapFilms).
    return addInventoryItem(
      trimmed,
      0,
      unit,
      category: category,
      metersPerRoll: metersPerRoll,
    );
  }

  Future<List<Map<String, dynamic>>> getOrderWrapFilms(int orderId) async {
    return _crm.getOrderWrapFilms(orderId);
  }

  Future<List<String>> setOrderWrapFilms(int orderId, List<Map<String, dynamic>> films) async {
    return _crm.putOrderWrapFilms(orderId, films);
  }

  Future<List<Map<String, dynamic>>> listFilmRolls(int inventoryId, {bool onlyWithStock = false}) async {
    final rolls = await _crm.listFilmRolls(inventoryId, onlyWithStock: onlyWithStock);
    return rolls.map((r) => r.toLocalMap()).toList();
  }

  Future<int> addFilmRoll({
    required int inventoryId,
    required String rollNumber,
    double? metersInitial,
  }) async {
    final roll = await _crm.createFilmRoll(
      inventoryId: inventoryId,
      rollNumber: rollNumber,
      metersInitial: metersInitial,
    );
    return roll.id;
  }

  Future<List<String>> getRolesList() async {
    final fixed = <String>{
      'Администратор',
      'Приемщик',
      'Мойка',
      'Химчистка',
      'Полировка',
      'Оклейка',
      'Интерьер',
      'Оборудование',
      'Кузовные работы',
      'Тюнинг/Интерьер',
      'Универсал',
    };
    try {
      final api = await _crm.listWorkshopRoles();
      for (final r in api) {
        final n = r['name']?.toString().trim() ?? '';
        if (n.isNotEmpty) fixed.add(n);
      }
    } catch (_) {}
    return fixed.toList()..sort();
  }

  Future<void> addRole(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    await _crm.createWorkshopRole(n);
  }

  Future<void> deleteRole(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    await _crm.deleteWorkshopRoleByName(n);
  }

  Future<Map<String, dynamic>?> getPromocode(String code) async {
    final row = await _crm.getPromocode(code);
    if (row == null) return null;
    return _promoToLocal(row);
  }

  Future<List<Map<String, dynamic>>> getPromocodes() async {
    final list = await _crm.listPromocodes();
    return list.map(_promoToLocal).toList();
  }

  Future<void> upsertPromocode(String code, double percent, double fixed) async {
    await _crm.upsertPromocode(code: code, percent: percent, fixed: fixed);
  }

  Future<void> deletePromocode(int id) async {
    await _crm.deletePromocode(id);
  }

  Map<String, dynamic> _promoToLocal(Map<String, dynamic> p) => {
        'id': (p['id'] as num).toInt(),
        'code': p['code']?.toString() ?? '',
        'discount_percent': (p['discount_percent'] as num?)?.toDouble() ?? 0,
        'discount_fixed': (p['discount_fixed'] as num?)?.toDouble() ?? 0,
        'is_active': (p['is_active'] == true || p['is_active'] == 1) ? 1 : 0,
      };

  Future<List<String>> listInventoryBrands({String query = ''}) async {
    // Облако не ведёт отдельный справочник брендов.
    return const [];
  }

  Future<String> ensureInventoryBrand(String? raw) async {
    return (raw ?? '').trim();
  }

  Future<List<Map<String, dynamic>>> getClientHistory(int clientId) async {
    await _ensureOrders();
    await _ensureCars();
    final out = <Map<String, dynamic>>[];
    for (final o in _orders.values) {
      if (o.clientId != clientId) continue;
      final car = _cars[o.carId];
      final debt = o.price - o.paidAmount;
      out.add({
        'id': o.id,
        'created_at': o.startTime.isNotEmpty ? o.startTime : o.dueDate,
        'notes': o.notes,
        'price': o.price,
        'paid_amount': o.paidAmount,
        'status': o.status,
        'is_completed': o.status == 'Выдан' ? 1 : 0,
        'debt': debt,
        'make_model': car?.makeModel ?? '',
        'plate': car?.plate ?? '',
      });
    }
    out.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    return out;
  }

  Future<List<Map<String, dynamic>>> getOrdersByPlate(String plate) async {
    await _ensureOrders();
    await _ensureCars();
    await _ensureClients();
    final normalized = plate.replaceAll(' ', '').toUpperCase();
    if (normalized.isEmpty) return [];
    final out = <Map<String, dynamic>>[];
    for (final o in _orders.values) {
      final car = _cars[o.carId];
      if (car == null) continue;
      final p = car.plate.replaceAll(' ', '').toUpperCase();
      if (p != normalized) continue;
      final m = orderToMap(o);
      out.add(m);
    }
    out.sort((a, b) {
      final sa = (a['start_time']?.toString() ?? '').compareTo(b['start_time']?.toString() ?? '');
      if (sa != 0) return -sa;
      return (b['id'] as int).compareTo(a['id'] as int);
    });
    return out.take(20).toList();
  }

  Future<List<Map<String, dynamic>>> getLastOrderCartLines({
    required int clientId,
    int? carId,
  }) async {
    await _ensureOrders();
    final candidates = _orders.values.where((o) {
      if (o.clientId != clientId) return false;
      if (carId != null && o.carId != carId) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.id.compareTo(a.id));
    if (candidates.isEmpty) return [];
    final order = candidates.first;
    final items = order.items;
    final result = <Map<String, dynamic>>[];
    for (final item in items) {
      if (item.parentId != null) continue;
      final name = item.name.trim();
      if (name.isEmpty) continue;
      final price = item.price;
      var ws = item.workshop.trim();
      if (ws.isEmpty) ws = _workshopFromName(name) ?? '';

      final isWrap = name == 'Оклейка';
      final isTint = name == 'Тонировка';
      if (isWrap || isTint) {
        final headerId = item.id;
        final kids = items.where((x) => x.parentId == headerId).toList();
        if (kids.isNotEmpty) {
          final zones = kids.map((k) => k.name).toList();
          final kidSum = kids.fold<double>(0, (s, k) => s + k.price);
          result.add({
            'name': zones.length == 1 ? zones.first : '$name · ${zones.length} поз.',
            'price': price > 0 ? price : kidSum,
            'category': isWrap ? 'Оклейка (Пленка)' : 'Тонировка',
            'workshop': ws.isNotEmpty ? ws : (isWrap ? 'Оклейка' : 'Тонировка'),
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

  Future<double> getClientDebtTotal(int clientId) async {
    await _ensureOrders();
    return _orders.values
        .where((o) => o.clientId == clientId && o.status != 'Выдан')
        .fold<double>(0, (sum, o) {
      final d = o.price - o.paidAmount;
      return sum + (d > 0.01 ? d : 0);
    });
  }

  Future<double> suggestMasterPayroll(int masterId, String startDate, String endDate) async {
    await _ensureOrders();
    final start = startDate.length >= 10 ? startDate.substring(0, 10) : startDate;
    final end = endDate.length >= 10 ? endDate.substring(0, 10) : endDate;
    double total = 0;
    for (final o in _orders.values) {
      for (final it in o.items) {
        if (!_itemHasMaster(it.masterIds, masterId)) continue;
        final day = _itemDay(it, o);
        if (day == null) continue;
        if (day.compareTo(start) < 0 || day.compareTo(end) > 0) continue;
        total += it.price;
      }
    }
    return total;
  }

  bool _itemHasMaster(String masterIds, int masterId) {
    final raw = masterIds.trim();
    if (raw.isEmpty) return false;
    for (final part in raw.split(',')) {
      if (int.tryParse(part.trim()) == masterId) return true;
    }
    return false;
  }

  String? _itemDay(CrmOrderItem it, CrmOrder o) {
    final fromItem = _dayPart(it.startTime.isNotEmpty ? it.startTime : it.endTime);
    if (fromItem != null) return fromItem;
    final fromOrder = _dayPart(o.startTime.isNotEmpty ? o.startTime : o.dueDate);
    return fromOrder;
  }

  Future<Map<String, dynamic>> getCompanyStats({String? masterDay, int days = 30}) async {
    return _crm.getStats(masterDay: masterDay, days: days);
  }

  Future<double> getRevenueToday() async {
    final s = await getCompanyStats();
    return (s['revenue_today'] as num?)?.toDouble() ?? 0;
  }

  Future<double> getRevenueMonth() async {
    final s = await getCompanyStats();
    return (s['revenue_month'] as num?)?.toDouble() ?? 0;
  }

  Future<Map<String, double>> getStatsKpis() async {
    final s = await getCompanyStats();
    return {
      'orders_count': (s['orders_count'] as num?)?.toDouble() ?? 0,
      'avg_check': (s['avg_check'] as num?)?.toDouble() ?? 0,
      'revenue_all': (s['revenue_all'] as num?)?.toDouble() ?? 0,
      'open_debt': (s['open_debt'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<List<Map<String, dynamic>>> getRevenueByDay(int days) async {
    final s = await getCompanyStats(days: days);
    final list = (s['revenue_by_day'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> getServicesStats() async {
    final s = await getCompanyStats();
    final list = (s['top_by_count'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> getTopServicesByRevenue({int limit = 5}) async {
    final s = await getCompanyStats();
    final list = (s['top_by_revenue'] as List?) ?? const [];
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .take(limit)
        .toList();
  }

  Future<List<Map<String, dynamic>>> getMasterDayStats(String dayYyyyMmDd) async {
    final s = await getCompanyStats(masterDay: dayYyyyMmDd);
    final list = (s['master_day'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> importClientsBundle(List<Map<String, dynamic>> clients) async {
    final result = await _crm.importClients(clients);
    await refreshAll();
    return result;
  }
}
