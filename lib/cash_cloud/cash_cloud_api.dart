import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_api.dart';
import '../auth/auth_controller.dart';
import 'cash_cloud_models.dart';

class CashCloudException implements Exception {
  final String message;
  final int? statusCode;
  CashCloudException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class CashCloudApi {
  CashCloudApi({this.baseUrl = AuthApi.defaultBaseUrl});

  final String baseUrl;

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _headers() {
    final token = AuthController.instance.accessToken;
    if (token == null || token.isEmpty) {
      throw CashCloudException('Нет сессии — войдите снова', statusCode: 401);
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<List<CloudCashRegister>> listRegisters() async {
    final r = await http.get(_u('/cash/registers'), headers: _headers()).timeout(const Duration(seconds: 15));
    _ensure(r);
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return list.map((e) => CloudCashRegister.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CloudCashShift?> currentShift() async {
    final r =
        await http.get(_u('/cash/shifts/current'), headers: _headers()).timeout(const Duration(seconds: 15));
    if (r.statusCode == 204 || r.bodyBytes.isEmpty || r.body.trim() == 'null') {
      return null;
    }
    _ensure(r);
    final map = jsonDecode(utf8.decode(r.bodyBytes));
    if (map == null) return null;
    return CloudCashShift.fromJson(map as Map<String, dynamic>);
  }

  Future<CloudCashShift> openShift({Map<int, double>? openings, String note = ''}) async {
    final body = <String, dynamic>{
      'note': note,
      'openings': {for (final e in (openings ?? {}).entries) '${e.key}': e.value},
    };
    final r = await http
        .post(_u('/cash/shifts/open'), headers: _headers(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return CloudCashShift.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<CloudCashShift> closeShift(int shiftId, {Map<int, double>? facts, String note = ''}) async {
    final body = <String, dynamic>{
      'note': note,
      'facts': {for (final e in (facts ?? {}).entries) '${e.key}': e.value},
    };
    final r = await http
        .post(_u('/cash/shifts/$shiftId/close'), headers: _headers(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return CloudCashShift.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<List<CloudCashJournalEntry>> journal() async {
    final r = await http.get(_u('/cash/journal'), headers: _headers()).timeout(const Duration(seconds: 15));
    _ensure(r);
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return list.map((e) => CloudCashJournalEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> createFlow({
    required String type,
    required double amount,
    String method = 'Наличные',
    String category = 'Прочее',
    String description = '',
    int? registerId,
  }) async {
    final r = await http
        .post(
          _u('/cash/flows'),
          headers: _headers(),
          body: jsonEncode({
            'type': type,
            'amount': amount,
            'method': method,
            'category': category,
            'description': description,
            if (registerId != null) 'register_id': registerId,
          }),
        )
        .timeout(const Duration(seconds: 15));
    _ensure(r);
  }

  Future<void> createPayment({
    required int orderId,
    required double amount,
    String method = 'Наличные',
    int? registerId,
  }) async {
    final r = await http
        .post(
          _u('/cash/payments'),
          headers: _headers(),
          body: jsonEncode({
            'order_id': orderId,
            'amount': amount,
            'method': method,
            if (registerId != null) 'register_id': registerId,
          }),
        )
        .timeout(const Duration(seconds: 15));
    _ensure(r);
  }

  void _ensure(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    var msg = 'Ошибка кассы (${r.statusCode})';
    try {
      final map = jsonDecode(utf8.decode(r.bodyBytes));
      if (map is Map && map['detail'] != null) {
        final d = map['detail'];
        msg = d is String ? d : d.toString();
      }
    } catch (_) {}
    throw CashCloudException(msg, statusCode: r.statusCode);
  }
}
