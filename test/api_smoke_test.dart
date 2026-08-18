import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Дымовая проверка облака (нужен интернет). Не трогает локальную БД.
void main() {
  const base = 'http://api.det-app.ru';

  Future<String> apiVersion() async {
    final r = await http.get(Uri.parse('$base/health')).timeout(const Duration(seconds: 12));
    expect(r.statusCode, 200);
    final map = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return map['version']?.toString() ?? '';
  }

  bool _atLeast(String v, int major, int minor) {
    final parts = v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    if (parts[0] != major) return parts[0] > major;
    return parts[1] >= minor;
  }

  Future<String> ownerToken() async {
    final r = await http
        .post(
          Uri.parse('$base/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'login': 'owner@demo.det-app.ru',
            'password': 'DetAppAdmin2026!',
          }),
        )
        .timeout(const Duration(seconds: 12));
    expect(r.statusCode, 200, reason: utf8.decode(r.bodyBytes));
    final map = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return map['access_token']?.toString() ?? '';
  }

  test('GET /health ok', () async {
    final r = await http.get(Uri.parse('$base/health')).timeout(const Duration(seconds: 12));
    expect(r.statusCode, 200);
    final map = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    expect(map['ok'], true);
    expect(map['service'], 'det-app-api');
    expect(map['version'], isNotEmpty);
  });

  test('GET /updates/latest.json has build and packs', () async {
    final r =
        await http.get(Uri.parse('$base/updates/latest.json')).timeout(const Duration(seconds: 12));
    expect(r.statusCode, 200);
    final map = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    expect((map['build'] as num?)?.toInt() ?? 0, greaterThan(0));
    expect((map['url']?.toString() ?? ''), isNotEmpty);
    expect((map['sha256']?.toString() ?? ''), isNotEmpty);
  });

  test('POST /auth/login legacy email field', () async {
    final r = await http
        .post(
          Uri.parse('$base/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': 'admin@det-app.ru',
            'password': 'DetAppAdmin2026!',
          }),
        )
        .timeout(const Duration(seconds: 12));
    expect(r.statusCode, 200, reason: utf8.decode(r.bodyBytes));
  });

  test('POST /auth/login by login field (needs API 0.4+)', () async {
    final ver = await apiVersion();
    if (!_atLeast(ver, 0, 4)) {
      print('SKIP login-field: API $ver');
      return;
    }
    final r = await http
        .post(
          Uri.parse('$base/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'login': 'admin@det-app.ru',
            'password': 'DetAppAdmin2026!',
          }),
        )
        .timeout(const Duration(seconds: 12));
    expect(r.statusCode, 200, reason: utf8.decode(r.bodyBytes));
  });

  test('POST /auth/login by phone (needs API 0.4+)', () async {
    final ver = await apiVersion();
    if (!_atLeast(ver, 0, 4)) {
      print('SKIP phone-login: API $ver');
      return;
    }
    final r = await http
        .post(
          Uri.parse('$base/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'login': '9000000001',
            'password': 'DetAppAdmin2026!',
          }),
        )
        .timeout(const Duration(seconds: 20));
    expect(r.statusCode, 200, reason: utf8.decode(r.bodyBytes));
  });

  test('CRM create client+car+order visible in list (needs API 0.5+)', () async {
    final ver = await apiVersion();
    if (!_atLeast(ver, 0, 5)) {
      print('SKIP crm: API $ver (need 0.5.0+)');
      return;
    }
    final token = await ownerToken();
    expect(token, isNotEmpty);
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final stamp = DateTime.now().millisecondsSinceEpoch;

    final c = await http
        .post(
          Uri.parse('$base/crm/clients'),
          headers: headers,
          body: jsonEncode({'name': 'Smoke $stamp', 'phone': '900111$stamp'.substring(0, 10)}),
        )
        .timeout(const Duration(seconds: 15));
    expect(c.statusCode, 200, reason: utf8.decode(c.bodyBytes));
    final client = jsonDecode(utf8.decode(c.bodyBytes)) as Map<String, dynamic>;
    final clientId = (client['id'] as num).toInt();

    final carR = await http
        .post(
          Uri.parse('$base/crm/cars'),
          headers: headers,
          body: jsonEncode({
            'client_id': clientId,
            'make_model': 'Toyota Smoke',
            'plate': 'A$stamp',
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(carR.statusCode, 200, reason: utf8.decode(carR.bodyBytes));
    final car = jsonDecode(utf8.decode(carR.bodyBytes)) as Map<String, dynamic>;
    final carId = (car['id'] as num).toInt();

    final o = await http
        .post(
          Uri.parse('$base/crm/orders'),
          headers: headers,
          body: jsonEncode({
            'client_id': clientId,
            'car_id': carId,
            'items': [
              {'name': 'Мойка smoke', 'price': 1500, 'workshop': 'Мойка'},
            ],
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(o.statusCode, 200, reason: utf8.decode(o.bodyBytes));
    final order = jsonDecode(utf8.decode(o.bodyBytes)) as Map<String, dynamic>;
    final orderId = (order['id'] as num).toInt();

    final list = await http
        .get(Uri.parse('$base/crm/orders'), headers: headers)
        .timeout(const Duration(seconds: 15));
    expect(list.statusCode, 200, reason: utf8.decode(list.bodyBytes));
    final orders = jsonDecode(utf8.decode(list.bodyBytes)) as List;
    expect(orders.any((e) => (e as Map)['id'] == orderId), isTrue);
  });

  test('Cash open shift + payment updates paid_amount (needs API 0.6+)', () async {
    final ver = await apiVersion();
    if (!_atLeast(ver, 0, 6)) {
      print('SKIP cash: API $ver (need 0.6.0+)');
      return;
    }
    final token = await ownerToken();
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // ensure / open shift
    final cur = await http
        .get(Uri.parse('$base/cash/shifts/current'), headers: headers)
        .timeout(const Duration(seconds: 15));
    expect(cur.statusCode, 200, reason: utf8.decode(cur.bodyBytes));
    Map<String, dynamic>? shift;
    if (cur.body.trim().isNotEmpty && cur.body.trim() != 'null') {
      shift = jsonDecode(utf8.decode(cur.bodyBytes)) as Map<String, dynamic>;
    }
    if (shift == null || shift['status'] != 'open') {
      final open = await http
          .post(
            Uri.parse('$base/cash/shifts/open'),
            headers: headers,
            body: jsonEncode({'openings': {}, 'note': 'smoke'}),
          )
          .timeout(const Duration(seconds: 15));
      expect(open.statusCode, 200, reason: utf8.decode(open.bodyBytes));
      shift = jsonDecode(utf8.decode(open.bodyBytes)) as Map<String, dynamic>;
    }

    final c = await http
        .post(
          Uri.parse('$base/crm/clients'),
          headers: headers,
          body: jsonEncode({'name': 'Cash $stamp', 'phone': '900333${stamp % 10000}'}),
        )
        .timeout(const Duration(seconds: 15));
    expect(c.statusCode, 200, reason: utf8.decode(c.bodyBytes));
    final clientId = (jsonDecode(utf8.decode(c.bodyBytes))['id'] as num).toInt();

    final carR = await http
        .post(
          Uri.parse('$base/crm/cars'),
          headers: headers,
          body: jsonEncode({'client_id': clientId, 'make_model': 'Cash Car', 'plate': 'C$stamp'}),
        )
        .timeout(const Duration(seconds: 15));
    final carId = (jsonDecode(utf8.decode(carR.bodyBytes))['id'] as num).toInt();

    final o = await http
        .post(
          Uri.parse('$base/crm/orders'),
          headers: headers,
          body: jsonEncode({
            'client_id': clientId,
            'car_id': carId,
            'items': [
              {'name': 'Оплата smoke', 'price': 2500, 'workshop': 'Мойка'},
            ],
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(o.statusCode, 200, reason: utf8.decode(o.bodyBytes));
    final orderId = (jsonDecode(utf8.decode(o.bodyBytes))['id'] as num).toInt();

    final pay = await http
        .post(
          Uri.parse('$base/cash/payments'),
          headers: headers,
          body: jsonEncode({'order_id': orderId, 'amount': 1000, 'method': 'Наличные'}),
        )
        .timeout(const Duration(seconds: 15));
    expect(pay.statusCode, 200, reason: utf8.decode(pay.bodyBytes));

    final got = await http
        .get(Uri.parse('$base/crm/orders/$orderId'), headers: headers)
        .timeout(const Duration(seconds: 15));
    expect(got.statusCode, 200);
    final order = jsonDecode(utf8.decode(got.bodyBytes)) as Map<String, dynamic>;
    expect((order['paid_amount'] as num).toDouble(), greaterThanOrEqualTo(1000));

    // second session sees journal
    final token2 = await ownerToken();
    final j = await http
        .get(
          Uri.parse('$base/cash/journal'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token2',
          },
        )
        .timeout(const Duration(seconds: 15));
    expect(j.statusCode, 200, reason: utf8.decode(j.bodyBytes));
    final journal = jsonDecode(utf8.decode(j.bodyBytes)) as List;
    expect(journal.any((e) => (e as Map)['kind'] == 'payment' && e['order_id'] == orderId), isTrue);
  });

  test('CRM order items CRUD keeps stable ids (needs API 0.9+)', () async {
    final ver = await apiVersion();
    if (!_atLeast(ver, 0, 9)) {
      print('SKIP items-crud: API $ver');
      return;
    }
    final token = await ownerToken();
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final c = await http
        .post(
          Uri.parse('$base/crm/clients'),
          headers: headers,
          body: jsonEncode({'name': 'Items $stamp', 'phone': '900444${stamp % 10000}'}),
        )
        .timeout(const Duration(seconds: 15));
    final clientId = (jsonDecode(utf8.decode(c.bodyBytes))['id'] as num).toInt();
    final carR = await http
        .post(
          Uri.parse('$base/crm/cars'),
          headers: headers,
          body: jsonEncode({'client_id': clientId, 'make_model': 'Items Car', 'plate': 'I$stamp'}),
        )
        .timeout(const Duration(seconds: 15));
    final carId = (jsonDecode(utf8.decode(carR.bodyBytes))['id'] as num).toInt();
    final o = await http
        .post(
          Uri.parse('$base/crm/orders'),
          headers: headers,
          body: jsonEncode({
            'client_id': clientId,
            'car_id': carId,
            'items': [
              {'name': 'Мойка', 'price': 1000, 'workshop': 'Мойка'},
            ],
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(o.statusCode, 200, reason: utf8.decode(o.bodyBytes));
    final order = jsonDecode(utf8.decode(o.bodyBytes)) as Map<String, dynamic>;
    final orderId = (order['id'] as num).toInt();
    final firstId = ((order['items'] as List).first as Map)['id'] as num;

    final add = await http
        .post(
          Uri.parse('$base/crm/orders/$orderId/items'),
          headers: headers,
          body: jsonEncode({'name': 'Полировка', 'price': 5000, 'workshop': 'Полировка'}),
        )
        .timeout(const Duration(seconds: 15));
    expect(add.statusCode, 200, reason: utf8.decode(add.bodyBytes));
    final added = jsonDecode(utf8.decode(add.bodyBytes)) as Map<String, dynamic>;
    final secondId = (added['id'] as num).toInt();

    final patch = await http
        .patch(
          Uri.parse('$base/crm/orders/$orderId/items/$firstId'),
          headers: headers,
          body: jsonEncode({'is_done': true, 'price': 1200, 'comment': 'ok'}),
        )
        .timeout(const Duration(seconds: 15));
    expect(patch.statusCode, 200, reason: utf8.decode(patch.bodyBytes));
    final patched = jsonDecode(utf8.decode(patch.bodyBytes)) as Map<String, dynamic>;
    expect(patched['id'], firstId);
    expect(patched['is_done'], true);
    expect((patched['price'] as num).toDouble(), 1200);

    final got = await http
        .get(Uri.parse('$base/crm/orders/$orderId'), headers: headers)
        .timeout(const Duration(seconds: 15));
    final full = jsonDecode(utf8.decode(got.bodyBytes)) as Map<String, dynamic>;
    expect((full['price'] as num).toDouble(), 6200);
    final ids = (full['items'] as List).map((e) => (e as Map)['id']).toSet();
    expect(ids.contains(firstId), isTrue);
    expect(ids.contains(secondId), isTrue);

    final del = await http
        .delete(Uri.parse('$base/crm/orders/$orderId/items/$secondId'), headers: headers)
        .timeout(const Duration(seconds: 15));
    expect(del.statusCode, 200, reason: utf8.decode(del.bodyBytes));
  });

  test('CRM order card core: notes/discount/events/void (needs API 0.10+)', () async {
    final ver = await apiVersion();
    if (!_atLeast(ver, 0, 10)) {
      print('SKIP order-card: API $ver');
      return;
    }
    final token = await ownerToken();
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final stamp = DateTime.now().millisecondsSinceEpoch;

    var shiftR = await http
        .get(Uri.parse('$base/cash/shifts/current'), headers: headers)
        .timeout(const Duration(seconds: 15));
    Map<String, dynamic>? shift;
    if (shiftR.statusCode == 200 && shiftR.body.trim().isNotEmpty && shiftR.body.trim() != 'null') {
      shift = jsonDecode(utf8.decode(shiftR.bodyBytes)) as Map<String, dynamic>;
    }
    if (shift == null || shift['status'] != 'open') {
      final open = await http
          .post(
            Uri.parse('$base/cash/shifts/open'),
            headers: headers,
            body: jsonEncode({'openings': {}, 'note': 'smoke-card'}),
          )
          .timeout(const Duration(seconds: 15));
      expect(open.statusCode, 200, reason: utf8.decode(open.bodyBytes));
    }

    final c = await http
        .post(
          Uri.parse('$base/crm/clients'),
          headers: headers,
          body: jsonEncode({'name': 'Card $stamp', 'phone': '900555${stamp % 10000}'}),
        )
        .timeout(const Duration(seconds: 15));
    final clientId = (jsonDecode(utf8.decode(c.bodyBytes))['id'] as num).toInt();
    final carR = await http
        .post(
          Uri.parse('$base/crm/cars'),
          headers: headers,
          body: jsonEncode({'client_id': clientId, 'make_model': 'Card Car', 'plate': 'K$stamp'}),
        )
        .timeout(const Duration(seconds: 15));
    final carId = (jsonDecode(utf8.decode(carR.bodyBytes))['id'] as num).toInt();
    final o = await http
        .post(
          Uri.parse('$base/crm/orders'),
          headers: headers,
          body: jsonEncode({
            'client_id': clientId,
            'car_id': carId,
            'items': [
              {'name': 'Мойка', 'price': 2000, 'workshop': 'Мойка'},
            ],
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(o.statusCode, 200, reason: utf8.decode(o.bodyBytes));
    final orderId = (jsonDecode(utf8.decode(o.bodyBytes))['id'] as num).toInt();

    final patch = await http
        .patch(
          Uri.parse('$base/crm/orders/$orderId'),
          headers: headers,
          body: jsonEncode({
            'client_notes': 'клиент: ждать',
            'master_notes': 'мастер: полироль',
            'client_visible_notes': 'видимая',
            'payment_method': 'Карта',
            'discount_percent': 10,
            'discount_fixed': 100,
            'promo_code': 'SMOKE10',
            'end_date': '2026-08-20',
            'handover_works': true,
            'handover_keys': true,
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(patch.statusCode, 200, reason: utf8.decode(patch.bodyBytes));
    final patched = jsonDecode(utf8.decode(patch.bodyBytes)) as Map<String, dynamic>;
    expect(patched['client_notes'], 'клиент: ждать');
    expect(patched['master_notes'], 'мастер: полироль');
    expect(patched['promo_code'], 'SMOKE10');
    expect(patched['handover_works'], true);
    // 2000 * 10% + 100 = 300 discount → 1700
    expect((patched['price'] as num).toDouble(), 1700);

    final ev = await http
        .post(
          Uri.parse('$base/crm/orders/$orderId/events'),
          headers: headers,
          body: jsonEncode({'event_text': 'smoke event'}),
        )
        .timeout(const Duration(seconds: 15));
    expect(ev.statusCode, 200, reason: utf8.decode(ev.bodyBytes));
    final events = await http
        .get(Uri.parse('$base/crm/orders/$orderId/events'), headers: headers)
        .timeout(const Duration(seconds: 15));
    expect(events.statusCode, 200);
    final evList = jsonDecode(utf8.decode(events.bodyBytes)) as List;
    expect(evList.any((e) => (e as Map)['event_text'] == 'smoke event'), isTrue);

    final pay = await http
        .post(
          Uri.parse('$base/cash/payments'),
          headers: headers,
          body: jsonEncode({'order_id': orderId, 'amount': 500, 'method': 'Наличные'}),
        )
        .timeout(const Duration(seconds: 15));
    expect(pay.statusCode, 200, reason: utf8.decode(pay.bodyBytes));
    final paymentId = (jsonDecode(utf8.decode(pay.bodyBytes))['id'] as num).toInt();

    final listed = await http
        .get(Uri.parse('$base/cash/payments?order_id=$orderId'), headers: headers)
        .timeout(const Duration(seconds: 15));
    expect(listed.statusCode, 200, reason: utf8.decode(listed.bodyBytes));
    final pays = jsonDecode(utf8.decode(listed.bodyBytes)) as List;
    expect(pays.any((e) => (e as Map)['id'] == paymentId), isTrue);

    final voided = await http
        .delete(Uri.parse('$base/cash/payments/$paymentId'), headers: headers)
        .timeout(const Duration(seconds: 15));
    expect(voided.statusCode, 200, reason: utf8.decode(voided.bodyBytes));
    expect((jsonDecode(utf8.decode(voided.bodyBytes)) as Map)['is_voided'], true);

    final after = await http
        .get(Uri.parse('$base/crm/orders/$orderId'), headers: headers)
        .timeout(const Duration(seconds: 15));
    final afterOrder = jsonDecode(utf8.decode(after.bodyBytes)) as Map<String, dynamic>;
    expect((afterOrder['paid_amount'] as num).toDouble(), 0);
  });

  test('CRM workshops+calendar fields (needs API 0.11+)', () async {
    final ver = await apiVersion();
    if (!_atLeast(ver, 0, 11)) {
      print('SKIP workshops-calendar: API $ver');
      return;
    }
    final token = await ownerToken();
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final c = await http
        .post(
          Uri.parse('$base/crm/clients'),
          headers: headers,
          body: jsonEncode({'name': 'Cal $stamp', 'phone': '900666${stamp % 10000}'}),
        )
        .timeout(const Duration(seconds: 15));
    final clientId = (jsonDecode(utf8.decode(c.bodyBytes))['id'] as num).toInt();
    final carR = await http
        .post(
          Uri.parse('$base/crm/cars'),
          headers: headers,
          body: jsonEncode({'client_id': clientId, 'make_model': 'Cal Car', 'plate': 'W$stamp'}),
        )
        .timeout(const Duration(seconds: 15));
    final carId = (jsonDecode(utf8.decode(carR.bodyBytes))['id'] as num).toInt();
    final day = '2026-08-19';
    final o = await http
        .post(
          Uri.parse('$base/crm/orders'),
          headers: headers,
          body: jsonEncode({
            'client_id': clientId,
            'car_id': carId,
            'start_time': '${day}T10:00:00',
            'end_time': '${day}T12:30:00',
            'items': [
              {
                'name': 'Мойка',
                'price': 1500,
                'workshop': 'Мойка',
                'start_time': '${day}T10:00:00',
                'end_time': '${day}T11:00:00',
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(o.statusCode, 200, reason: utf8.decode(o.bodyBytes));
    final orderId = (jsonDecode(utf8.decode(o.bodyBytes))['id'] as num).toInt();

    final patch = await http
        .patch(
          Uri.parse('$base/crm/orders/$orderId'),
          headers: headers,
          body: jsonEncode({
            'tech_wash_start': day,
            'tech_wash_end': day,
            'is_workshop_completed': true,
            'start_time': '${day}T10:00:00',
            'end_time': '${day}T14:30:00',
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(patch.statusCode, 200, reason: utf8.decode(patch.bodyBytes));
    final patched = jsonDecode(utf8.decode(patch.bodyBytes)) as Map<String, dynamic>;
    expect(patched['tech_wash_start'], day);
    expect(patched['is_workshop_completed'], true);
    expect(patched['start_time'], '${day}T10:00:00');
    expect(patched['end_time'], '${day}T14:30:00');
  });

  test('CRM zone package parent_id wrap/tint (needs API 0.12+)', () async {
    final ver = await apiVersion();
    if (!_atLeast(ver, 0, 12)) {
      print('SKIP zone-package: API $ver');
      return;
    }
    final token = await ownerToken();
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final c = await http
        .post(
          Uri.parse('$base/crm/clients'),
          headers: headers,
          body: jsonEncode({'name': 'Pkg $stamp', 'phone': '900888${stamp % 10000}'}),
        )
        .timeout(const Duration(seconds: 15));
    final clientId = (jsonDecode(utf8.decode(c.bodyBytes))['id'] as num).toInt();
    final carR = await http
        .post(
          Uri.parse('$base/crm/cars'),
          headers: headers,
          body: jsonEncode({'client_id': clientId, 'make_model': 'Pkg Car', 'plate': 'P$stamp'}),
        )
        .timeout(const Duration(seconds: 15));
    final carId = (jsonDecode(utf8.decode(carR.bodyBytes))['id'] as num).toInt();
    final o = await http
        .post(
          Uri.parse('$base/crm/orders'),
          headers: headers,
          body: jsonEncode({
            'client_id': clientId,
            'car_id': carId,
            'items': [
              {'name': 'Оклейка', 'price': 25000, 'workshop': 'Оклейка'},
            ],
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(o.statusCode, 200, reason: utf8.decode(o.bodyBytes));
    final order = jsonDecode(utf8.decode(o.bodyBytes)) as Map<String, dynamic>;
    final orderId = (order['id'] as num).toInt();
    final headerId = ((order['items'] as List).first as Map)['id'] as num;

    final z1 = await http
        .post(
          Uri.parse('$base/crm/orders/$orderId/items'),
          headers: headers,
          body: jsonEncode({
            'name': 'Оклейка · Капот',
            'price': 0,
            'workshop': 'Оклейка',
            'parent_id': headerId.toInt(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(z1.statusCode, 200, reason: utf8.decode(z1.bodyBytes));
    final zone = jsonDecode(utf8.decode(z1.bodyBytes)) as Map<String, dynamic>;
    expect(zone['parent_id'], headerId);

    final z2 = await http
        .post(
          Uri.parse('$base/crm/orders/$orderId/items'),
          headers: headers,
          body: jsonEncode({
            'name': 'Оклейка · Крыша',
            'price': 0,
            'workshop': 'Оклейка',
            'parent_id': headerId.toInt(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(z2.statusCode, 200, reason: utf8.decode(z2.bodyBytes));

    final got = await http
        .get(Uri.parse('$base/crm/orders/$orderId'), headers: headers)
        .timeout(const Duration(seconds: 15));
    final full = jsonDecode(utf8.decode(got.bodyBytes)) as Map<String, dynamic>;
    expect((full['price'] as num).toDouble(), 25000);
    final items = full['items'] as List;
    expect(items.length, 3);
    final kids = items.where((e) => (e as Map)['parent_id'] == headerId).length;
    expect(kids, 2);

    // Удаление шапки каскадом убирает зоны
    final del = await http
        .delete(Uri.parse('$base/crm/orders/$orderId/items/$headerId'), headers: headers)
        .timeout(const Duration(seconds: 15));
    expect(del.statusCode, 200, reason: utf8.decode(del.bodyBytes));
    final after = await http
        .get(Uri.parse('$base/crm/orders/$orderId'), headers: headers)
        .timeout(const Duration(seconds: 15));
    final afterItems = (jsonDecode(utf8.decode(after.bodyBytes)) as Map)['items'] as List;
    expect(afterItems, isEmpty);
  });

  test('CRM film rolls + order wrap films (needs API 0.13+)', () async {
    final ver = await apiVersion();
    if (!_atLeast(ver, 0, 13)) {
      print('SKIP film-rolls: API $ver');
      return;
    }
    final token = await ownerToken();
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final stamp = DateTime.now().millisecondsSinceEpoch;

    final inv = await http
        .post(
          Uri.parse('$base/crm/inventory'),
          headers: headers,
          body: jsonEncode({
            'name': 'Film $stamp',
            'quantity': 0,
            'unit': 'м',
            'category': 'Плёнка оклейка',
            'meters_per_roll': 15,
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(inv.statusCode, 200, reason: utf8.decode(inv.bodyBytes));
    final invId = (jsonDecode(utf8.decode(inv.bodyBytes))['id'] as num).toInt();

    final rollR = await http
        .post(
          Uri.parse('$base/crm/film-rolls'),
          headers: headers,
          body: jsonEncode({
            'inventory_id': invId,
            'roll_number': 'R$stamp',
            'meters_initial': 15,
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(rollR.statusCode, 200, reason: utf8.decode(rollR.bodyBytes));
    final roll = jsonDecode(utf8.decode(rollR.bodyBytes)) as Map<String, dynamic>;
    final rollId = (roll['id'] as num).toInt();
    expect((roll['meters_left'] as num).toDouble(), 15);

    final films = await http
        .get(Uri.parse('$base/crm/wrap-films'), headers: headers)
        .timeout(const Duration(seconds: 15));
    expect(films.statusCode, 200);
    final filmList = jsonDecode(utf8.decode(films.bodyBytes)) as List;
    expect(filmList.any((e) => (e as Map)['id'] == invId), isTrue);

    final c = await http
        .post(
          Uri.parse('$base/crm/clients'),
          headers: headers,
          body: jsonEncode({'name': 'FilmOrd $stamp', 'phone': '900999${stamp % 10000}'}),
        )
        .timeout(const Duration(seconds: 15));
    final clientId = (jsonDecode(utf8.decode(c.bodyBytes))['id'] as num).toInt();
    final carR = await http
        .post(
          Uri.parse('$base/crm/cars'),
          headers: headers,
          body: jsonEncode({'client_id': clientId, 'make_model': 'Film Car', 'plate': 'F$stamp'}),
        )
        .timeout(const Duration(seconds: 15));
    final carId = (jsonDecode(utf8.decode(carR.bodyBytes))['id'] as num).toInt();
    final o = await http
        .post(
          Uri.parse('$base/crm/orders'),
          headers: headers,
          body: jsonEncode({
            'client_id': clientId,
            'car_id': carId,
            'items': [
              {'name': 'Оклейка', 'price': 1000, 'workshop': 'Оклейка'},
            ],
          }),
        )
        .timeout(const Duration(seconds: 15));
    final orderId = (jsonDecode(utf8.decode(o.bodyBytes))['id'] as num).toInt();

    final put = await http
        .put(
          Uri.parse('$base/crm/orders/$orderId/wrap-films'),
          headers: headers,
          body: jsonEncode({
            'films': [
              {'film_id': invId, 'roll_id': rollId, 'meters': 3.5},
            ],
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(put.statusCode, 200, reason: utf8.decode(put.bodyBytes));

    final rolls = await http
        .get(Uri.parse('$base/crm/film-rolls?inventory_id=$invId'), headers: headers)
        .timeout(const Duration(seconds: 15));
    final rollAfter = (jsonDecode(utf8.decode(rolls.bodyBytes)) as List)
        .cast<Map>()
        .firstWhere((e) => e['id'] == rollId);
    expect((rollAfter['meters_left'] as num).toDouble(), 11.5);

    final clear = await http
        .put(
          Uri.parse('$base/crm/orders/$orderId/wrap-films'),
          headers: headers,
          body: jsonEncode({'films': []}),
        )
        .timeout(const Duration(seconds: 15));
    expect(clear.statusCode, 200, reason: utf8.decode(clear.bodyBytes));
    final rolls2 = await http
        .get(Uri.parse('$base/crm/film-rolls?inventory_id=$invId'), headers: headers)
        .timeout(const Duration(seconds: 15));
    final restored = (jsonDecode(utf8.decode(rolls2.bodyBytes)) as List)
        .cast<Map>()
        .firstWhere((e) => e['id'] == rollId);
    expect((restored['meters_left'] as num).toDouble(), 15);
  });

  test('CRM recipes deduct/restore on inventory (needs API 0.14+)', () async {
    final ver = await apiVersion();
    if (!_atLeast(ver, 0, 14)) {
      print('SKIP recipes: API $ver');
      return;
    }
    final token = await ownerToken();
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final stamp = DateTime.now().millisecondsSinceEpoch;

    final inv = await http
        .post(
          Uri.parse('$base/crm/inventory'),
          headers: headers,
          body: jsonEncode({
            'name': 'Shampoo $stamp',
            'quantity': 10,
            'unit': 'мл',
            'category': 'Мойка',
            'min_qty': 2,
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(inv.statusCode, 200, reason: utf8.decode(inv.bodyBytes));
    final invId = (jsonDecode(utf8.decode(inv.bodyBytes))['id'] as num).toInt();

    final upsert = await http
        .put(
          Uri.parse('$base/crm/recipes'),
          headers: headers,
          body: jsonEncode({
            'service_name': 'Мойка кузова $stamp',
            'inventory_id': invId,
            'qty': 3,
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(upsert.statusCode, 200, reason: utf8.decode(upsert.bodyBytes));

    final listed = await http
        .get(
          Uri.parse('$base/crm/recipes?service_name=${Uri.encodeQueryComponent('Мойка кузова $stamp')}'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
    expect(listed.statusCode, 200);
    final recipes = jsonDecode(utf8.decode(listed.bodyBytes)) as List;
    expect(recipes.length, 1);
    expect((recipes.first as Map)['qty'], 3);

    final deduct = await http
        .post(
          Uri.parse('$base/crm/recipes/deduct'),
          headers: headers,
          body: jsonEncode({'service_name': 'Мойка кузова $stamp'}),
        )
        .timeout(const Duration(seconds: 15));
    expect(deduct.statusCode, 200, reason: utf8.decode(deduct.bodyBytes));

    final after = await http
        .get(Uri.parse('$base/crm/inventory'), headers: headers)
        .timeout(const Duration(seconds: 15));
    final items = jsonDecode(utf8.decode(after.bodyBytes)) as List;
    final row = items.cast<Map>().firstWhere((e) => e['id'] == invId);
    expect((row['quantity'] as num).toDouble(), 7);

    final restore = await http
        .post(
          Uri.parse('$base/crm/recipes/restore'),
          headers: headers,
          body: jsonEncode({'service_name': 'Мойка кузова $stamp'}),
        )
        .timeout(const Duration(seconds: 15));
    expect(restore.statusCode, 200, reason: utf8.decode(restore.bodyBytes));

    final after2 = await http
        .get(Uri.parse('$base/crm/inventory'), headers: headers)
        .timeout(const Duration(seconds: 15));
    final items2 = jsonDecode(utf8.decode(after2.bodyBytes)) as List;
    final row2 = items2.cast<Map>().firstWhere((e) => e['id'] == invId);
    expect((row2['quantity'] as num).toDouble(), 10);

    final patch = await http
        .patch(
          Uri.parse('$base/crm/inventory/$invId'),
          headers: headers,
          body: jsonEncode({'min_qty': 5, 'quantity': 4}),
        )
        .timeout(const Duration(seconds: 15));
    expect(patch.statusCode, 200, reason: utf8.decode(patch.bodyBytes));
    final patched = jsonDecode(utf8.decode(patch.bodyBytes)) as Map<String, dynamic>;
    expect((patched['quantity'] as num).toDouble(), 4);
    expect((patched['min_qty'] as num).toDouble(), 5);
  });

  test('Cash flows CRUD + inventory purchase (needs API 0.15+)', () async {
    final ver = await apiVersion();
    if (!_atLeast(ver, 0, 15)) {
      print('SKIP cash-flows: API $ver (need 0.15.0+)');
      return;
    }
    final token = await ownerToken();
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final stamp = DateTime.now().millisecondsSinceEpoch;

    final cur = await http
        .get(Uri.parse('$base/cash/shifts/current'), headers: headers)
        .timeout(const Duration(seconds: 15));
    expect(cur.statusCode, 200, reason: utf8.decode(cur.bodyBytes));
    Map<String, dynamic>? shift;
    if (cur.body.trim().isNotEmpty && cur.body.trim() != 'null') {
      shift = jsonDecode(utf8.decode(cur.bodyBytes)) as Map<String, dynamic>;
    }
    if (shift == null || shift['status'] != 'open') {
      final open = await http
          .post(
            Uri.parse('$base/cash/shifts/open'),
            headers: headers,
            body: jsonEncode({'openings': {}, 'note': 'smoke-flow'}),
          )
          .timeout(const Duration(seconds: 15));
      expect(open.statusCode, 200, reason: utf8.decode(open.bodyBytes));
      shift = jsonDecode(utf8.decode(open.bodyBytes)) as Map<String, dynamic>;
    }
    final shiftId = (shift!['id'] as num).toInt();

    final invR = await http
        .post(
          Uri.parse('$base/crm/inventory'),
          headers: headers,
          body: jsonEncode({
            'name': 'Cash inv $stamp',
            'unit': 'шт',
            'category': 'Прочее',
            'quantity': 1,
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(invR.statusCode, 200, reason: utf8.decode(invR.bodyBytes));
    final invId = (jsonDecode(utf8.decode(invR.bodyBytes))['id'] as num).toInt();

    final flow = await http
        .post(
          Uri.parse('$base/cash/flows'),
          headers: headers,
          body: jsonEncode({
            'type': 'Расход',
            'amount': 500,
            'category': 'Закупка',
            'method': 'Наличные',
            'description': 'Smoke purchase $stamp',
            'inventory_id': invId,
            'inventory_qty': 3,
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(flow.statusCode, 200, reason: utf8.decode(flow.bodyBytes));
    final flowMap = jsonDecode(utf8.decode(flow.bodyBytes)) as Map<String, dynamic>;
    final flowId = (flowMap['id'] as num).toInt();
    expect(flowMap['inventory_id'], invId);

    final gotFlow = await http
        .get(Uri.parse('$base/cash/flows/$flowId'), headers: headers)
        .timeout(const Duration(seconds: 15));
    expect(gotFlow.statusCode, 200, reason: utf8.decode(gotFlow.bodyBytes));

    final invList = await http
        .get(Uri.parse('$base/crm/inventory'), headers: headers)
        .timeout(const Duration(seconds: 15));
    final items = jsonDecode(utf8.decode(invList.bodyBytes)) as List;
    final row = items.cast<Map>().firstWhere((e) => e['id'] == invId);
    expect((row['quantity'] as num).toDouble(), 4);

    final patch = await http
        .patch(
          Uri.parse('$base/cash/flows/$flowId'),
          headers: headers,
          body: jsonEncode({
            'type': 'Расход',
            'amount': 600,
            'description': 'Smoke purchase patched $stamp',
            'category': 'Закупка',
            'method': 'Наличные',
            'inventory_id': invId,
            'inventory_qty': 2,
          }),
        )
        .timeout(const Duration(seconds: 15));
    expect(patch.statusCode, 200, reason: utf8.decode(patch.bodyBytes));

    final afterPatch = await http
        .get(Uri.parse('$base/crm/inventory'), headers: headers)
        .timeout(const Duration(seconds: 15));
    final items2 = jsonDecode(utf8.decode(afterPatch.bodyBytes)) as List;
    final row2 = items2.cast<Map>().firstWhere((e) => e['id'] == invId);
    expect((row2['quantity'] as num).toDouble(), 3);

    final j = await http
        .get(
          Uri.parse('$base/cash/journal?shift_id=$shiftId'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
    expect(j.statusCode, 200, reason: utf8.decode(j.bodyBytes));
    final journal = jsonDecode(utf8.decode(j.bodyBytes)) as List;
    expect(
      journal.any((e) => (e as Map)['kind'] == 'flow' && e['id'] == flowId),
      isTrue,
    );
    expect(
      journal.any((e) => (e as Map)['category'] == 'Закупка'),
      isTrue,
    );

    final shifts = await http
        .get(Uri.parse('$base/cash/shifts?limit=5'), headers: headers)
        .timeout(const Duration(seconds: 15));
    expect(shifts.statusCode, 200, reason: utf8.decode(shifts.bodyBytes));

    final del = await http
        .delete(Uri.parse('$base/cash/flows/$flowId'), headers: headers)
        .timeout(const Duration(seconds: 15));
    expect(del.statusCode, 204, reason: utf8.decode(del.bodyBytes));

    final afterDel = await http
        .get(Uri.parse('$base/crm/inventory'), headers: headers)
        .timeout(const Duration(seconds: 15));
    final items3 = jsonDecode(utf8.decode(afterDel.bodyBytes)) as List;
    final row3 = items3.cast<Map>().firstWhere((e) => e['id'] == invId);
    expect((row3['quantity'] as num).toDouble(), 1);
  });
}
