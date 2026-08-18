import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_api.dart';
import '../auth/auth_controller.dart';
import 'crm_models.dart';

class CrmApiException implements Exception {
  final String message;
  final int? statusCode;
  CrmApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class CrmApi {
  CrmApi({this.baseUrl = AuthApi.defaultBaseUrl});

  final String baseUrl;

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> _headers() {
    final token = AuthController.instance.accessToken;
    if (token == null || token.isEmpty) {
      throw CrmApiException('Нет сессии — войдите снова', statusCode: 401);
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<List<CrmClient>> listClients() async {
    final r = await http.get(_u('/crm/clients'), headers: _headers()).timeout(const Duration(seconds: 15));
    _ensure(r);
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return list.map((e) => CrmClient.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CrmClient> createClient({required String name, String phone = ''}) async {
    final r = await http
        .post(
          _u('/crm/clients'),
          headers: _headers(),
          body: jsonEncode({'name': name, 'phone': phone, 'is_vip': false}),
        )
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return CrmClient.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<List<CrmCar>> listCars({int? clientId}) async {
    final q = clientId == null ? null : {'client_id': '$clientId'};
    final r = await http.get(_u('/crm/cars', q), headers: _headers()).timeout(const Duration(seconds: 15));
    _ensure(r);
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return list.map((e) => CrmCar.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CrmCar> createCar({
    required int clientId,
    required String makeModel,
    String plate = '',
  }) async {
    final r = await http
        .post(
          _u('/crm/cars'),
          headers: _headers(),
          body: jsonEncode({
            'client_id': clientId,
            'make_model': makeModel,
            'plate': plate,
            'vin': '',
            'category': '1',
          }),
        )
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return CrmCar.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<List<CrmOrder>> listOrders() async {
    final r = await http.get(_u('/crm/orders'), headers: _headers()).timeout(const Duration(seconds: 15));
    _ensure(r);
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return list.map((e) => CrmOrder.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CrmOrder> createOrder({
    required int clientId,
    required int carId,
    required List<CrmOrderItem> items,
    String notes = '',
    String status = 'Принят в работу',
    List<int> masterIds = const [],
  }) async {
    final r = await http
        .post(
          _u('/crm/orders'),
          headers: _headers(),
          body: jsonEncode({
            'client_id': clientId,
            'car_id': carId,
            'status': status,
            'notes': notes,
            'master_ids': masterIds,
            'items': items.map((e) => e.toJson()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return CrmOrder.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<CrmOrder> patchOrder(int id, Map<String, dynamic> body) async {
    final r = await http
        .patch(_u('/crm/orders/$id'), headers: _headers(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return CrmOrder.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<List<CrmMaster>> listMasters() async {
    final r = await http.get(_u('/crm/masters'), headers: _headers()).timeout(const Duration(seconds: 15));
    _ensure(r);
    return (jsonDecode(utf8.decode(r.bodyBytes)) as List)
        .map((e) => CrmMaster.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<CrmService>> listServices() async {
    final r = await http.get(_u('/crm/services'), headers: _headers()).timeout(const Duration(seconds: 15));
    _ensure(r);
    return (jsonDecode(utf8.decode(r.bodyBytes)) as List)
        .map((e) => CrmService.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addDefect(int orderId, {required String description, String workshop = '', String photoB64 = ''}) async {
    final r = await http
        .post(
          _u('/crm/orders/$orderId/defects'),
          headers: _headers(),
          body: jsonEncode({
            'description': description,
            'workshop': workshop,
            'photo_b64': photoB64,
          }),
        )
        .timeout(const Duration(seconds: 30));
    _ensure(r);
  }

  Future<List<CrmInventoryItem>> listInventory() async {
    final r = await http.get(_u('/crm/inventory'), headers: _headers()).timeout(const Duration(seconds: 15));
    _ensure(r);
    return (jsonDecode(utf8.decode(r.bodyBytes)) as List)
        .map((e) => CrmInventoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CrmInventoryItem> createInventory({
    required String name,
    double quantity = 0,
    String unit = 'шт',
    String category = 'Прочее',
  }) async {
    final r = await http
        .post(
          _u('/crm/inventory'),
          headers: _headers(),
          body: jsonEncode({
            'name': name,
            'quantity': quantity,
            'unit': unit,
            'category': category,
          }),
        )
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return CrmInventoryItem.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<void> inventoryMove({required int itemId, required double delta, String reason = 'adjust'}) async {
    final r = await http
        .post(
          _u('/crm/inventory/moves'),
          headers: _headers(),
          body: jsonEncode({'item_id': itemId, 'delta': delta, 'reason': reason}),
        )
        .timeout(const Duration(seconds: 15));
    _ensure(r);
  }

  void _ensure(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    var msg = 'Ошибка CRM (${r.statusCode})';
    try {
      final map = jsonDecode(utf8.decode(r.bodyBytes));
      if (map is Map && map['detail'] != null) {
        final d = map['detail'];
        msg = d is String ? d : d.toString();
      }
    } catch (_) {}
    throw CrmApiException(msg, statusCode: r.statusCode);
  }
}
