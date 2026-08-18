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

  Future<CrmClient> patchClient(int id, Map<String, dynamic> body) async {
    final r = await http
        .patch(_u('/crm/clients/$id'), headers: _headers(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return CrmClient.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<CrmMaster> createMaster({required String name, String role = 'Универсал'}) async {
    final r = await http
        .post(
          _u('/crm/masters'),
          headers: _headers(),
          body: jsonEncode({'name': name, 'role': role}),
        )
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return CrmMaster.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<CrmMaster> patchMaster(int id, Map<String, dynamic> body) async {
    final r = await http
        .patch(_u('/crm/masters/$id'), headers: _headers(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return CrmMaster.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<CrmService> createService({
    required String name,
    String category = 'Прочее',
    double price = 0,
    String workshop = '',
  }) async {
    final r = await http
        .post(
          _u('/crm/services'),
          headers: _headers(),
          body: jsonEncode({
            'name': name,
            'category': category,
            'price': price,
            'workshop': workshop,
          }),
        )
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return CrmService.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<CrmService> patchService(int id, Map<String, dynamic> body) async {
    final r = await http
        .patch(_u('/crm/services/$id'), headers: _headers(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return CrmService.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
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
    String dueDate = '',
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
            'due_date': dueDate,
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

  Future<CrmOrderItem> createOrderItem(int orderId, CrmOrderItem item) async {
    final r = await http
        .post(
          _u('/crm/orders/$orderId/items'),
          headers: _headers(),
          body: jsonEncode(item.toJson()..remove('id')),
        )
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return CrmOrderItem.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<CrmOrderItem> patchOrderItem(int orderId, int itemId, Map<String, dynamic> body) async {
    final r = await http
        .patch(
          _u('/crm/orders/$orderId/items/$itemId'),
          headers: _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return CrmOrderItem.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<void> deleteOrderItem(int orderId, int itemId) async {
    final r = await http
        .delete(_u('/crm/orders/$orderId/items/$itemId'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    _ensure(r);
  }

  Future<CrmCar> patchCar(int id, Map<String, dynamic> body) async {
    final r = await http
        .patch(_u('/crm/cars/$id'), headers: _headers(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return CrmCar.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
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

  Future<List<Map<String, dynamic>>> listWrapFilms() async {
    final r = await http.get(_u('/crm/wrap-films'), headers: _headers()).timeout(const Duration(seconds: 15));
    _ensure(r);
    return (jsonDecode(utf8.decode(r.bodyBytes)) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<CrmFilmRoll>> listFilmRolls(int inventoryId, {bool onlyWithStock = false}) async {
    final uri = _u('/crm/film-rolls').replace(queryParameters: {
      'inventory_id': '$inventoryId',
      if (onlyWithStock) 'only_with_stock': 'true',
    });
    final r = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 15));
    _ensure(r);
    return (jsonDecode(utf8.decode(r.bodyBytes)) as List)
        .map((e) => CrmFilmRoll.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CrmFilmRoll> createFilmRoll({
    required int inventoryId,
    required String rollNumber,
    double? metersInitial,
  }) async {
    final r = await http
        .post(
          _u('/crm/film-rolls'),
          headers: _headers(),
          body: jsonEncode({
            'inventory_id': inventoryId,
            'roll_number': rollNumber,
            if (metersInitial != null) 'meters_initial': metersInitial,
          }),
        )
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return CrmFilmRoll.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> getOrderWrapFilms(int orderId) async {
    final r = await http
        .get(_u('/crm/orders/$orderId/wrap-films'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return (jsonDecode(utf8.decode(r.bodyBytes)) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<String>> putOrderWrapFilms(int orderId, List<Map<String, dynamic>> films) async {
    final payload = films
        .map(
          (f) => {
            'film_id': f['filmId'] ?? f['film_id'],
            'roll_id': f['rollId'] ?? f['roll_id'],
            'meters': f['meters'] ?? 0,
          },
        )
        .toList();
    final r = await http
        .put(
          _u('/crm/orders/$orderId/wrap-films'),
          headers: _headers(),
          body: jsonEncode({'films': payload}),
        )
        .timeout(const Duration(seconds: 20));
    _ensure(r);
    final map = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return ((map['warnings'] as List?) ?? const []).map((e) => e.toString()).toList();
  }

  Future<List<CrmOrderEvent>> listOrderEvents(int orderId) async {
    final r = await http
        .get(_u('/crm/orders/$orderId/events'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return (jsonDecode(utf8.decode(r.bodyBytes)) as List)
        .map((e) => CrmOrderEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CrmOrderEvent> createOrderEvent(int orderId, String text) async {
    final r = await http
        .post(
          _u('/crm/orders/$orderId/events'),
          headers: _headers(),
          body: jsonEncode({'event_text': text}),
        )
        .timeout(const Duration(seconds: 15));
    _ensure(r);
    return CrmOrderEvent.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
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
