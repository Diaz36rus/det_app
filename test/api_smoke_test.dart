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
}
