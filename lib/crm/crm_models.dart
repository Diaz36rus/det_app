class CrmClient {
  final int id;
  final int companyId;
  final String name;
  final String phone;
  final bool isVip;

  const CrmClient({
    required this.id,
    required this.companyId,
    required this.name,
    required this.phone,
    required this.isVip,
  });

  factory CrmClient.fromJson(Map<String, dynamic> j) => CrmClient(
        id: (j['id'] as num).toInt(),
        companyId: (j['company_id'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        phone: j['phone']?.toString() ?? '',
        isVip: j['is_vip'] == true,
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

  const CrmCar({
    required this.id,
    required this.companyId,
    required this.clientId,
    required this.makeModel,
    required this.plate,
    required this.vin,
    required this.category,
  });

  factory CrmCar.fromJson(Map<String, dynamic> j) => CrmCar(
        id: (j['id'] as num).toInt(),
        companyId: (j['company_id'] as num).toInt(),
        clientId: (j['client_id'] as num).toInt(),
        makeModel: j['make_model']?.toString() ?? '',
        plate: j['plate']?.toString() ?? '',
        vin: j['vin']?.toString() ?? '',
        category: j['category']?.toString() ?? '1',
      );

  String get label => '$makeModel ${plate.isEmpty ? '' : plate}'.trim();
}

class CrmOrderItem {
  final int? id;
  final String name;
  final double price;
  final String workshop;
  final bool isDone;

  const CrmOrderItem({
    this.id,
    required this.name,
    required this.price,
    this.workshop = '',
    this.isDone = false,
  });

  factory CrmOrderItem.fromJson(Map<String, dynamic> j) => CrmOrderItem(
        id: (j['id'] as num?)?.toInt(),
        name: j['name']?.toString() ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        workshop: j['workshop']?.toString() ?? '',
        isDone: j['is_done'] == true || j['is_done'] == 1,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'price': price,
        'workshop': workshop,
        'is_done': isDone,
      };
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
  final List<int> masterIds;
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
    this.masterIds = const [],
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
        masterIds: (j['master_ids'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const [],
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
  const CrmMaster({required this.id, required this.name, required this.role, required this.isActive});
  factory CrmMaster.fromJson(Map<String, dynamic> j) => CrmMaster(
        id: (j['id'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        role: j['role']?.toString() ?? '',
        isActive: j['is_active'] != false,
      );
}

class CrmService {
  final int id;
  final String name;
  final String category;
  final double price;
  final String workshop;
  final bool isActive;
  const CrmService({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.workshop,
    required this.isActive,
  });
  factory CrmService.fromJson(Map<String, dynamic> j) => CrmService(
        id: (j['id'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        category: j['category']?.toString() ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
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
  const CrmInventoryItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
  });
  factory CrmInventoryItem.fromJson(Map<String, dynamic> j) => CrmInventoryItem(
        id: (j['id'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        quantity: (j['quantity'] as num?)?.toDouble() ?? 0,
        unit: j['unit']?.toString() ?? 'шт',
        category: j['category']?.toString() ?? '',
      );
}
