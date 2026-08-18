class CloudCashRegister {
  final int id;
  final String name;
  final String moneyType;
  final bool isActive;

  const CloudCashRegister({
    required this.id,
    required this.name,
    required this.moneyType,
    required this.isActive,
  });

  factory CloudCashRegister.fromJson(Map<String, dynamic> j) => CloudCashRegister(
        id: (j['id'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        moneyType: j['money_type']?.toString() ?? '',
        isActive: j['is_active'] != false,
      );
}

class CloudCashShiftBalance {
  final int registerId;
  final String? registerName;
  final String? moneyType;
  final double opening;
  final double? expected;
  final double? fact;

  const CloudCashShiftBalance({
    required this.registerId,
    this.registerName,
    this.moneyType,
    required this.opening,
    this.expected,
    this.fact,
  });

  factory CloudCashShiftBalance.fromJson(Map<String, dynamic> j) => CloudCashShiftBalance(
        registerId: (j['register_id'] as num).toInt(),
        registerName: j['register_name']?.toString(),
        moneyType: j['money_type']?.toString(),
        opening: (j['opening'] as num?)?.toDouble() ?? 0,
        expected: (j['expected'] as num?)?.toDouble(),
        fact: (j['fact'] as num?)?.toDouble(),
      );
}

class CloudCashShift {
  final int id;
  final int branchId;
  final String status;
  final String note;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final List<CloudCashShiftBalance> balances;

  const CloudCashShift({
    required this.id,
    required this.branchId,
    required this.status,
    required this.note,
    this.openedAt,
    this.closedAt,
    this.balances = const [],
  });

  bool get isOpen => status == 'open';

  factory CloudCashShift.fromJson(Map<String, dynamic> j) {
    DateTime? parse(String key) {
      final raw = j[key]?.toString();
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    }

    return CloudCashShift(
      id: (j['id'] as num).toInt(),
      branchId: (j['branch_id'] as num).toInt(),
      status: j['status']?.toString() ?? '',
      note: j['note']?.toString() ?? '',
      openedAt: parse('opened_at'),
      closedAt: parse('closed_at'),
      balances: (j['balances'] as List?)
              ?.map((e) => CloudCashShiftBalance.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toLocalMap() {
    double? totalDiff;
    for (final b in balances) {
      if (b.fact != null && b.expected != null) {
        totalDiff = (totalDiff ?? 0) + (b.fact! - b.expected!);
      }
    }
    return {
      'id': id,
      'status': status,
      'note': note,
      'branch_id': branchId,
      'opened_at': openedAt?.toIso8601String() ?? '',
      'closed_at': closedAt?.toIso8601String() ?? '',
      if (totalDiff != null) 'difference': totalDiff,
    };
  }
}

class CloudCashJournalEntry {
  final String kind;
  final int id;
  final double amount;
  final String method;
  final String title;
  final int shiftId;
  final String? flowType;
  final int? orderId;
  final bool isVoided;
  final DateTime? createdAt;
  final String category;
  final String registerName;

  const CloudCashJournalEntry({
    required this.kind,
    required this.id,
    required this.amount,
    required this.method,
    required this.title,
    required this.shiftId,
    this.flowType,
    this.orderId,
    this.isVoided = false,
    this.createdAt,
    this.category = '',
    this.registerName = '',
  });

  factory CloudCashJournalEntry.fromJson(Map<String, dynamic> j) {
    DateTime? at;
    final raw = j['created_at']?.toString();
    if (raw != null && raw.isNotEmpty) {
      at = DateTime.tryParse(raw);
    }
    return CloudCashJournalEntry(
      kind: j['kind']?.toString() ?? '',
      id: (j['id'] as num).toInt(),
      amount: (j['amount'] as num?)?.toDouble() ?? 0,
      method: j['method']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      shiftId: (j['shift_id'] as num?)?.toInt() ?? 0,
      flowType: j['flow_type']?.toString(),
      orderId: (j['order_id'] as num?)?.toInt(),
      isVoided: j['is_voided'] == true,
      createdAt: at,
      category: j['category']?.toString() ?? '',
      registerName: j['register_name']?.toString() ?? '',
    );
  }
}
