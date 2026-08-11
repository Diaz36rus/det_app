import 'dart:convert';

import 'database.dart';

const kOrderTemplatesKey = 'order_templates';

/// Шаблон корзины «Новый заказ» (хранится в app_settings JSON).
class OrderTemplate {
  final String id;
  final String name;
  final List<Map<String, dynamic>> items;

  const OrderTemplate({
    required this.id,
    required this.name,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'items': items,
      };

  factory OrderTemplate.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) items.add(Map<String, dynamic>.from(e));
      }
    }
    return OrderTemplate(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Шаблон',
      items: items,
    );
  }
}

class OrderTemplatesStore {
  OrderTemplatesStore._();

  static Future<List<OrderTemplate>> load() async {
    final raw = await DatabaseHelper().getAppSetting(kOrderTemplatesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => OrderTemplate.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => t.id.isNotEmpty && t.items.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveAll(List<OrderTemplate> list) async {
    final encoded = jsonEncode(list.map((t) => t.toJson()).toList());
    await DatabaseHelper().setAppSetting(kOrderTemplatesKey, encoded);
  }

  static Future<OrderTemplate> saveFromCart({
    required String name,
    required List<Map<String, dynamic>> cart,
  }) async {
    final items = cart.map((e) {
      final m = <String, dynamic>{
        'name': e['name'],
        'price': e['price'],
        'category': e['category'] ?? '',
        'workshop': e['workshop'] ?? '',
      };
      final zones = e['wrapZones'];
      if (zones is List) m['wrapZones'] = List<String>.from(zones.map((z) => z.toString()));
      return m;
    }).toList();
    final tpl = OrderTemplate(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'Шаблон' : name.trim(),
      items: items,
    );
    final all = await load();
    all.insert(0, tpl);
    await _saveAll(all);
    return tpl;
  }

  static Future<void> delete(String id) async {
    final all = await load();
    all.removeWhere((t) => t.id == id);
    await _saveAll(all);
  }
}
