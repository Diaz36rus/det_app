import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_api.dart';
import '../auth/authed_http.dart';
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


  Future<List<CloudCashRegister>> listRegisters() async {
    final r = await authedGet(_u('/cash/registers'), timeout: const Duration(seconds: 15));
    _ensure(r);
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return list.map((e) => CloudCashRegister.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CloudCashRegister> createRegister({
    required String name,
    required String moneyType,
    int sortOrder = 100,
  }) async {
    final r = await authedPost(_u('/cash/registers'), body: jsonEncode({
            'name': name,
            'money_type': moneyType,
            'sort_order': sortOrder,
          }), timeout: const Duration(seconds: 15));
    _ensure(r);
    return CloudCashRegister.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<CloudCashRegister> patchRegister(
    int registerId, {
    String? name,
    String? moneyType,
    bool? isActive,
    int? sortOrder,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (moneyType != null) 'money_type': moneyType,
      if (isActive != null) 'is_active': isActive,
      if (sortOrder != null) 'sort_order': sortOrder,
    };
    final r = await authedPatch(_u('/cash/registers/$registerId'), body: jsonEncode(body), timeout: const Duration(seconds: 15));
    _ensure(r);
    return CloudCashRegister.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<CloudCashShift?> currentShift({int? branchId}) async {
    final q = <String, String>{
      if (branchId != null) 'branch_id': '$branchId',
    };
    final uri = _u('/cash/shifts/current').replace(queryParameters: q.isEmpty ? null : q);
    final r = await authedGet(uri, timeout: const Duration(seconds: 15));
    if (r.statusCode == 204 || r.bodyBytes.isEmpty || r.body.trim() == 'null') {
      return null;
    }
    _ensure(r);
    final map = jsonDecode(utf8.decode(r.bodyBytes));
    if (map == null) return null;
    return CloudCashShift.fromJson(map as Map<String, dynamic>);
  }

  Future<CloudCashShift> getShift(int shiftId) async {
    final r = await authedGet(_u('/cash/shifts/$shiftId'), timeout: const Duration(seconds: 15));
    _ensure(r);
    return CloudCashShift.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<List<CloudCashShift>> listShifts({int limit = 20}) async {
    final uri = _u('/cash/shifts').replace(queryParameters: {'limit': '$limit'});
    final r = await authedGet(uri, timeout: const Duration(seconds: 15));
    _ensure(r);
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return list.map((e) => CloudCashShift.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CloudCashShift> openShift({Map<int, double>? openings, String note = ''}) async {
    final body = <String, dynamic>{
      'note': note,
      'openings': {for (final e in (openings ?? {}).entries) '${e.key}': e.value},
    };
    final r = await authedPost(_u('/cash/shifts/open'), body: jsonEncode(body), timeout: const Duration(seconds: 15));
    _ensure(r);
    return CloudCashShift.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<CloudCashShift> closeShift(int shiftId, {Map<int, double>? facts, String note = ''}) async {
    final body = <String, dynamic>{
      'note': note,
      'facts': {for (final e in (facts ?? {}).entries) '${e.key}': e.value},
    };
    final r = await authedPost(_u('/cash/shifts/$shiftId/close'), body: jsonEncode(body), timeout: const Duration(seconds: 15));
    _ensure(r);
    return CloudCashShift.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<List<CloudCashJournalEntry>> journal({
    String? from,
    String? to,
    int? shiftId,
    int? branchId,
  }) async {
    final q = <String, String>{
      if (from != null && from.isNotEmpty) 'from': from.length >= 10 ? from.substring(0, 10) : from,
      if (to != null && to.isNotEmpty) 'to': to.length >= 10 ? to.substring(0, 10) : to,
      if (shiftId != null) 'shift_id': '$shiftId',
      if (branchId != null) 'branch_id': '$branchId',
    };
    final uri = _u('/cash/journal').replace(queryParameters: q.isEmpty ? null : q);
    final r = await authedGet(uri, timeout: const Duration(seconds: 15));
    _ensure(r);
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return list.map((e) => CloudCashJournalEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> createFlow({
    required String type,
    required double amount,
    String method = 'Наличные',
    String category = 'Прочее',
    String description = '',
    String note = '',
    int? registerId,
    String counterparty = '',
    int? masterId,
    int? inventoryId,
    double inventoryQty = 0,
    int? orderId,
    String templateKey = '',
  }) async {
    final r = await authedPost(_u('/cash/flows'), body: jsonEncode({
            'type': type,
            'amount': amount,
            'method': method,
            'category': category,
            'description': description,
            'note': note,
            'counterparty': counterparty,
            'inventory_qty': inventoryQty,
            'template_key': templateKey,
            if (registerId != null) 'register_id': registerId,
            if (masterId != null) 'master_id': masterId,
            if (inventoryId != null) 'inventory_id': inventoryId,
            if (orderId != null) 'order_id': orderId,
          }), timeout: const Duration(seconds: 15));
    _ensure(r);
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(r.bodyBytes)) as Map);
  }

  Future<Map<String, dynamic>> getFlow(int flowId) async {
    final r = await authedGet(_u('/cash/flows/$flowId'), timeout: const Duration(seconds: 15));
    _ensure(r);
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(r.bodyBytes)) as Map);
  }

  Future<Map<String, dynamic>> updateFlow(
    int flowId, {
    required String type,
    required double amount,
    required String description,
    String category = 'Прочее',
    String method = 'Наличные',
    String note = '',
    int? registerId,
    String counterparty = '',
    int? masterId,
    int? inventoryId,
    double inventoryQty = 0,
    int? orderId,
    String templateKey = '',
  }) async {
    final r = await authedPatch(_u('/cash/flows/$flowId'), body: jsonEncode({
            'type': type,
            'amount': amount,
            'method': method,
            'category': category,
            'description': description,
            'note': note,
            'counterparty': counterparty,
            'inventory_qty': inventoryQty,
            'template_key': templateKey,
            'master_id': masterId,
            'inventory_id': inventoryId,
            'order_id': orderId,
            if (registerId != null) 'register_id': registerId,
          }), timeout: const Duration(seconds: 15));
    _ensure(r);
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(r.bodyBytes)) as Map);
  }

  Future<void> deleteFlow(int flowId) async {
    final r = await authedDelete(_u('/cash/flows/$flowId'), timeout: const Duration(seconds: 15));
    _ensure(r);
  }

  Future<void> createPayment({
    required int orderId,
    required double amount,
    String method = 'Наличные',
    int? registerId,
  }) async {
    final r = await authedPost(_u('/cash/payments'), body: jsonEncode({
            'order_id': orderId,
            'amount': amount,
            'method': method,
            if (registerId != null) 'register_id': registerId,
          }), timeout: const Duration(seconds: 15));
    _ensure(r);
  }

  Future<Map<String, dynamic>> patchPayment(
    int paymentId, {
    double? amount,
    String? method,
    int? registerId,
  }) async {
    final body = <String, dynamic>{
      if (amount != null) 'amount': amount,
      if (method != null) 'method': method,
      if (registerId != null) 'register_id': registerId,
    };
    final r = await authedPatch(_u('/cash/payments/$paymentId'), body: jsonEncode(body), timeout: const Duration(seconds: 15));
    _ensure(r);
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(r.bodyBytes)) as Map);
  }

  Future<List<Map<String, dynamic>>> listPayments({int? orderId, bool includeVoided = false}) async {
    final q = <String, String>{
      if (orderId != null) 'order_id': '$orderId',
      if (includeVoided) 'include_voided': 'true',
    };
    final uri = _u('/cash/payments').replace(queryParameters: q.isEmpty ? null : q);
    final r = await authedGet(uri, timeout: const Duration(seconds: 15));
    _ensure(r);
    return (jsonDecode(utf8.decode(r.bodyBytes)) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> voidPayment(int paymentId) async {
    final r = await authedDelete(_u('/cash/payments/$paymentId'), timeout: const Duration(seconds: 15));
    _ensure(r);
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(r.bodyBytes)) as Map);
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
