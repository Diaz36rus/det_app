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
      'end_date': o.dueDate,
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
      'discount_percent': 0,
      'discount_fixed': 0,
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

  Future<bool> updateStatus(int orderId, String newStatus) async {
    await _crm.patchOrder(orderId, {'status': newStatus});
    final prev = _orders[orderId];
    if (prev != null) {
      // refresh from server for consistency
      final list = await _crm.listOrders();
      _orders
        ..clear()
        ..addEntries(list.map((o) => MapEntry(o.id, o)));
    }
    return true;
  }

  Future<void> deleteOrder(int id) async {
    // API пока без DELETE — помечаем как Выдан / игнор
    await _crm.patchOrder(id, {'status': 'Выдан'});
    _orders.remove(id);
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

  Future<List<Map<String, dynamic>>> getAllMastersFull() async {
    _masters = await _crm.listMasters();
    return _masters
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

  Future<List<Map<String, dynamic>>> getAllServices() async {
    _services = await _crm.listServices();
    return _services
        .map(
          (s) => {
            'id': s.id,
            'name': s.name,
            'category': s.category,
            'price': s.price,
            'workshop': s.workshop,
            'is_active': s.isActive ? 1 : 0,
            // локальный прайс ждёт колонки вроде price_1 — дублируем
            'price_1': s.price,
            'price_2': s.price,
            'price_3': s.price,
          },
        )
        .toList();
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
            'min_qty': 0,
          },
        )
        .toList();
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

  Future<Map<String, dynamic>?> getCurrentShift() async {
    final s = await _cash.currentShift();
    if (s == null || !s.isOpen) return null;
    return {
      'id': s.id,
      'status': 'open',
      'note': s.note,
      'branch_id': s.branchId,
    };
  }

  Future<List<Map<String, dynamic>>> getCashJournal(String start, String end) async {
    final journal = await _cash.journal();
    return journal.map(_journalToMap).toList();
  }

  Map<String, dynamic> _journalToMap(CloudCashJournalEntry e) {
    final isPayment = e.kind == 'payment';
    return {
      'id': e.id,
      'kind': e.kind,
      'type': isPayment ? 'Приход' : (e.flowType ?? 'Приход'),
      'amount': e.amount,
      'method': e.method.isEmpty ? 'Наличные' : e.method,
      'category': '',
      'description': e.title,
      'created_at': e.createdAt?.toIso8601String() ?? '',
      'register_name': '',
      'order_id': e.orderId,
      'is_voided': e.isVoided ? 1 : 0,
    };
  }

  Future<List<Map<String, dynamic>>> getShiftRegisterSnapshots(int shiftId) async {
    final s = await _cash.currentShift();
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
    return _orders.values.fold<double>(0, (sum, o) => sum + o.debt);
  }

  Future<List<Map<String, dynamic>>> getOrderPayments(int orderId) async {
    // отдельного списка нет — пусто, оплата через cloud cash
    return [];
  }

  Future<List<Map<String, dynamic>>> getOrderEvents(int orderId) async => [];

  Future<void> addOrderEvent(int orderId, String text) async {}

  Future<Map<String, dynamic>> getOrderHandover(int orderId) async => {
        'handover_works': 0,
        'handover_inspect': 0,
        'handover_payment': 0,
        'handover_keys': 0,
        'handover_notified': 0,
        'handover_ready': 0,
      };

  Future<void> saveOrderHandover(int orderId, Map<String, dynamic> values) async {}

  Future<void> setTechWash(int orderId, String? startDate, String? endDate) async {}

  Future<void> syncZonePackage({
    required int orderId,
    required String kind,
    required List<String> zoneNames,
    required double packagePrice,
  }) async {}

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
    await _crm.deleteOrderItem(o.id, itemId);
    await _refreshOrder(o.id);
  }

  Future<List<String>> updateOrderItemDone(int itemId, bool isDone) async {
    if (itemId <= 0) return [];
    final o = await _orderByItemId(itemId);
    if (o == null) return [];
    await _crm.patchOrderItem(o.id, itemId, {'is_done': isDone});
    await _refreshOrder(o.id);
    return [];
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
    // Скидки в CRM API пока нет — no-op.
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
    });
    _orders[o.id] = o;
  }

  Future<void> updateOrderNotes(int orderId, String notes) async {
    final o = await _crm.patchOrder(orderId, {'notes': notes});
    _orders[o.id] = o;
  }

  Future<void> updateOrderClientNotes(int orderId, String notes) async {
    await updateOrderNotes(orderId, notes);
  }

  Future<void> updateOrderClientVisibleNotes(int orderId, String notes) async {}

  Future<void> updateOrderMasterNotes(int orderId, String notes) async {}

  Future<void> updateOrderPaymentMethod(int orderId, String method) async {}

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

  Future<Map<String, dynamic>?> voidPayment(int paymentId) async {
    // void через API есть — при необходимости расширим; пока null
    return null;
  }

  Future<int> openCashShift(double openingCash, {String note = '', Map<int, double>? openings}) async {
    final existing = await _cash.currentShift();
    if (existing != null && existing.isOpen) return existing.id;
    final s = await _cash.openShift(openings: openings, note: note);
    return s.id;
  }

  // Wrap / zone — безопасные no-op, чтобы карточка не падала
  Future<List<String>> updateWrapPackageDone(int headerId, bool isDone) async => [];

  Future<void> updateWrapPackageSchedule(int headerId, String? startTime, String? endTime) async {}

  Future<void> updateWrapPackageMasters(int headerId, List<int> masterIds) async {}

  Future<void> assignMastersToWorkshop(int orderId, String workshop, List<int> masterIds) async {
    if (masterIds.isNotEmpty) {
      await updateOrderMaster(orderId, masterIds.first);
    }
  }

  Future<List<String>> getRolesList() async =>
      ['Универсал', 'Мойка', 'Химчистка', 'Полировка', 'Оклейка'];
}
