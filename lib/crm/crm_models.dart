class CrmClient {
  final int id;
  final int companyId;
  final String name;
  final String phone;
  final bool isVip;
  final bool telegramLinked;
  final String telegramChatId;

  const CrmClient({
    required this.id,
    required this.companyId,
    required this.name,
    required this.phone,
    required this.isVip,
    this.telegramLinked = false,
    this.telegramChatId = '',
  });

  factory CrmClient.fromJson(Map<String, dynamic> j) => CrmClient(
        id: (j['id'] as num).toInt(),
        companyId: (j['company_id'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        phone: j['phone']?.toString() ?? '',
        isVip: j['is_vip'] == true,
        telegramLinked: j['telegram_linked'] == true ||
            (j['telegram_chat_id']?.toString() ?? '').trim().isNotEmpty,
        telegramChatId: j['telegram_chat_id']?.toString() ?? '',
      );
}

class CrmCar {
  final int id;
  final int companyId;
  final int clientId;
  final String makeModel;
  final String plate;
  final String vin;
  final String category;
  final int year;

  const CrmCar({
    required this.id,
    required this.companyId,
    required this.clientId,
    required this.makeModel,
    required this.plate,
    required this.vin,
    required this.category,
    this.year = 0,
  });

  factory CrmCar.fromJson(Map<String, dynamic> j) => CrmCar(
        id: (j['id'] as num).toInt(),
        companyId: (j['company_id'] as num).toInt(),
        clientId: (j['client_id'] as num).toInt(),
        makeModel: j['make_model']?.toString() ?? '',
        plate: j['plate']?.toString() ?? '',
        vin: j['vin']?.toString() ?? '',
        category: j['category']?.toString() ?? '1',
        year: (j['year'] as num?)?.toInt() ?? 0,
      );

  String get label {
    final base = '$makeModel ${plate.isEmpty ? '' : plate}'.trim();
    if (year > 0) return '$base · $year';
    return base;
  }
}

class CrmOrderItem {
  final int? id;
  final String name;
  final double price;
  final String workshop;
  final bool isDone;
  final String comment;
  final String masterIds;
  final String startTime;
  final String endTime;
  final int? parentId;

  const CrmOrderItem({
    this.id,
    required this.name,
    required this.price,
    this.workshop = '',
    this.isDone = false,
    this.comment = '',
    this.masterIds = '',
    this.startTime = '',
    this.endTime = '',
    this.parentId,
  });

  factory CrmOrderItem.fromJson(Map<String, dynamic> j) => CrmOrderItem(
        id: (j['id'] as num?)?.toInt(),
        name: j['name']?.toString() ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        workshop: j['workshop']?.toString() ?? '',
        isDone: j['is_done'] == true || j['is_done'] == 1,
        comment: j['comment']?.toString() ?? '',
        masterIds: j['master_ids']?.toString() ?? '',
        startTime: j['start_time']?.toString() ?? '',
        endTime: j['end_time']?.toString() ?? '',
        parentId: (j['parent_id'] as num?)?.toInt(),
      );

  Map<String, Object?> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'price': price,
        'workshop': workshop,
        'is_done': isDone,
        'comment': comment,
        'master_ids': masterIds,
        'start_time': startTime,
        'end_time': endTime,
        if (parentId != null) 'parent_id': parentId,
      };

  CrmOrderItem copyWith({
    int? id,
    String? name,
    double? price,
    String? workshop,
    bool? isDone,
    String? comment,
    String? masterIds,
    String? startTime,
    String? endTime,
    int? parentId,
  }) =>
      CrmOrderItem(
        id: id ?? this.id,
        name: name ?? this.name,
        price: price ?? this.price,
        workshop: workshop ?? this.workshop,
        isDone: isDone ?? this.isDone,
        comment: comment ?? this.comment,
        masterIds: masterIds ?? this.masterIds,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        parentId: parentId ?? this.parentId,
      );
}

class CrmOrder {
  final int id;
  final int companyId;
  final int branchId;
  final int clientId;
  final int carId;
  final String status;
  final double price;
  final double paidAmount;
  final String notes;
  final String dueDate;
  final String startTime;
  final String endTime;
  final String endDate;
  final String clientNotes;
  final String clientVisibleNotes;
  final String masterNotes;
  final String paymentMethod;
  final double discountPercent;
  final double discountFixed;
  final String promoCode;
  final String leadSource;
  final double depositRequired;
  final bool handoverReady;
  final bool handoverWorks;
  final bool handoverPayment;
  final bool handoverKeys;
  final bool handoverInspect;
  final bool handoverNotified;
  final String techWashStart;
  final String techWashEnd;
  final bool isWorkshopCompleted;
  final List<int> masterIds;
  final int? receptionistId;
  final List<CrmOrderItem> items;
  final String? clientName;
  final String? carLabel;

  const CrmOrder({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.clientId,
    required this.carId,
    required this.status,
    required this.price,
    required this.paidAmount,
    required this.notes,
    required this.dueDate,
    this.startTime = '',
    this.endTime = '',
    this.endDate = '',
    this.clientNotes = '',
    this.clientVisibleNotes = '',
    this.masterNotes = '',
    this.paymentMethod = 'Наличные',
    this.discountPercent = 0,
    this.discountFixed = 0,
    this.promoCode = '',
    this.leadSource = '',
    this.depositRequired = 0,
    this.handoverReady = false,
    this.handoverWorks = false,
    this.handoverPayment = false,
    this.handoverKeys = false,
    this.handoverInspect = false,
    this.handoverNotified = false,
    this.techWashStart = '',
    this.techWashEnd = '',
    this.isWorkshopCompleted = false,
    this.masterIds = const [],
    this.receptionistId,
    this.items = const [],
    this.clientName,
    this.carLabel,
  });

  double get debt => (price - paidAmount).clamp(0, double.infinity);

  factory CrmOrder.fromJson(Map<String, dynamic> j) => CrmOrder(
        id: (j['id'] as num).toInt(),
        companyId: (j['company_id'] as num).toInt(),
        branchId: (j['branch_id'] as num).toInt(),
        clientId: (j['client_id'] as num).toInt(),
        carId: (j['car_id'] as num).toInt(),
        status: j['status']?.toString() ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        paidAmount: (j['paid_amount'] as num?)?.toDouble() ?? 0,
        notes: j['notes']?.toString() ?? '',
        dueDate: j['due_date']?.toString() ?? '',
        startTime: j['start_time']?.toString() ?? '',
        endTime: j['end_time']?.toString() ?? '',
        endDate: j['end_date']?.toString() ?? '',
        clientNotes: j['client_notes']?.toString() ?? '',
        clientVisibleNotes: j['client_visible_notes']?.toString() ?? '',
        masterNotes: j['master_notes']?.toString() ?? '',
        paymentMethod: j['payment_method']?.toString() ?? 'Наличные',
        discountPercent: (j['discount_percent'] as num?)?.toDouble() ?? 0,
        discountFixed: (j['discount_fixed'] as num?)?.toDouble() ?? 0,
        promoCode: j['promo_code']?.toString() ?? '',
        leadSource: j['lead_source']?.toString() ?? '',
        depositRequired: (j['deposit_required'] as num?)?.toDouble() ?? 0,
        handoverReady: j['handover_ready'] == true,
        handoverWorks: j['handover_works'] == true,
        handoverPayment: j['handover_payment'] == true,
        handoverKeys: j['handover_keys'] == true,
        handoverInspect: j['handover_inspect'] == true,
        handoverNotified: j['handover_notified'] == true,
        techWashStart: j['tech_wash_start']?.toString() ?? '',
        techWashEnd: j['tech_wash_end']?.toString() ?? '',
        isWorkshopCompleted: j['is_workshop_completed'] == true,
        masterIds: (j['master_ids'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const [],
        receptionistId: (j['receptionist_id'] as num?)?.toInt(),
        items: (j['items'] as List?)
                ?.map((e) => CrmOrderItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        clientName: j['client_name']?.toString(),
        carLabel: j['car_label']?.toString(),
      );
}

class CrmMaster {
  final int id;
  final String name;
  final String role;
  final bool isActive;
  final bool onShift;
  const CrmMaster({
    required this.id,
    required this.name,
    required this.role,
    required this.isActive,
    this.onShift = false,
  });
  factory CrmMaster.fromJson(Map<String, dynamic> j) => CrmMaster(
        id: (j['id'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        role: j['role']?.toString() ?? '',
        isActive: j['is_active'] != false,
        onShift: j['on_shift'] == true || j['on_shift'] == 1,
      );
}

class CrmService {
  final int id;
  final String name;
  final String category;
  final double price;
  final double price2;
  final double price3;
  final double price4;
  final double fixedPrice;
  final String workshop;
  final bool isActive;
  const CrmService({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.price2 = 0,
    this.price3 = 0,
    this.price4 = 0,
    this.fixedPrice = 0,
    required this.workshop,
    required this.isActive,
  });

  double priceForClass(String? category) {
    if (fixedPrice > 0) return fixedPrice;
    final c = (category ?? '1').trim();
    final key = c.isEmpty ? '1' : c[0];
    switch (key) {
      case '2':
        return price2 > 0 ? price2 : price;
      case '3':
        return price3 > 0 ? price3 : price;
      case '4':
        return price4 > 0 ? price4 : price;
      default:
        return price;
    }
  }

  factory CrmService.fromJson(Map<String, dynamic> j) => CrmService(
        id: (j['id'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        category: j['category']?.toString() ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        price2: (j['price2'] as num?)?.toDouble() ?? 0,
        price3: (j['price3'] as num?)?.toDouble() ?? 0,
        price4: (j['price4'] as num?)?.toDouble() ?? 0,
        fixedPrice: (j['fixed_price'] as num?)?.toDouble() ?? 0,
        workshop: j['workshop']?.toString() ?? '',
        isActive: j['is_active'] != false,
      );
}

class CrmInventoryItem {
  final int id;
  final String name;
  final double quantity;
  final String unit;
  final String category;
  final double minQty;
  final double metersPerRoll;
  final double unitCost;
  const CrmInventoryItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
    this.minQty = 0,
    this.metersPerRoll = 0,
    this.unitCost = 0,
  });
  factory CrmInventoryItem.fromJson(Map<String, dynamic> j) => CrmInventoryItem(
        id: (j['id'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        quantity: (j['quantity'] as num?)?.toDouble() ?? 0,
        unit: j['unit']?.toString() ?? 'шт',
        category: j['category']?.toString() ?? '',
        minQty: (j['min_qty'] as num?)?.toDouble() ?? 0,
        metersPerRoll: (j['meters_per_roll'] as num?)?.toDouble() ?? 0,
        unitCost: (j['unit_cost'] as num?)?.toDouble() ?? 0,
      );
}

class CrmFilmRoll {
  final int id;
  final int inventoryId;
  final String rollNumber;
  final double metersInitial;
  final double metersLeft;

  const CrmFilmRoll({
    required this.id,
    required this.inventoryId,
    required this.rollNumber,
    required this.metersInitial,
    required this.metersLeft,
  });

  factory CrmFilmRoll.fromJson(Map<String, dynamic> j) => CrmFilmRoll(
        id: (j['id'] as num).toInt(),
        inventoryId: (j['inventory_id'] as num).toInt(),
        rollNumber: j['roll_number']?.toString() ?? '',
        metersInitial: (j['meters_initial'] as num?)?.toDouble() ?? 0,
        metersLeft: (j['meters_left'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toLocalMap() => {
        'id': id,
        'inventory_id': inventoryId,
        'roll_number': rollNumber,
        'meters_initial': metersInitial,
        'meters_left': metersLeft,
      };
}

class CrmOrderEvent {
  final int id;
  final int orderId;
  final String eventText;
  final String createdAt;

  const CrmOrderEvent({
    required this.id,
    required this.orderId,
    required this.eventText,
    required this.createdAt,
  });

  factory CrmOrderEvent.fromJson(Map<String, dynamic> j) {
    var created = j['created_at']?.toString() ?? '';
    if (created.length >= 16) {
      created = created.substring(0, 16).replaceFirst('T', ' ');
    }
    return CrmOrderEvent(
      id: (j['id'] as num).toInt(),
      orderId: (j['order_id'] as num).toInt(),
      eventText: j['event_text']?.toString() ?? '',
      createdAt: created,
    );
  }
}
