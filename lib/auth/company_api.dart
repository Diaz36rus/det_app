import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_api.dart';
import 'auth_models.dart';

/// API компании: пользователи, роли, назначение.
class CompanyApi {
  CompanyApi({this.baseUrl = AuthApi.defaultBaseUrl});

  final String baseUrl;

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q);

  Map<String, String> _auth(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Future<List<AuthUser>> listUsers({
    required String accessToken,
    bool? pending,
  }) async {
    final q = <String, String>{};
    if (pending != null) q['pending'] = pending ? 'true' : 'false';
    final r = await http
        .get(_u('/company/users', q.isEmpty ? null : q), headers: _auth(accessToken))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List<dynamic>;
    return list.map((e) => AuthUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<CompanyRole>> listRoles({required String accessToken}) async {
    final r = await http
        .get(_u('/company/roles'), headers: _auth(accessToken))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List<dynamic>;
    return list.map((e) => CompanyRole.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<CompanyBranch>> listBranches({required String accessToken}) async {
    final r = await http
        .get(_u('/company/branches'), headers: _auth(accessToken))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List<dynamic>;
    return list.map((e) => CompanyBranch.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<String>> listWorkshops({required String accessToken}) async {
    final r = await http
        .get(_u('/company/workshops'), headers: _auth(accessToken))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    final map = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return (map['items'] as List?)?.map((e) => e.toString()).toList() ?? const [];
  }

  Future<CompanyBranch> createBranch({
    required String accessToken,
    required String name,
  }) async {
    final r = await http
        .post(
          _u('/company/branches'),
          headers: _auth(accessToken),
          body: jsonEncode({'name': name.trim()}),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    return CompanyBranch.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<AuthUser> createUser({
    required String accessToken,
    required String email,
    required String password,
    required String fullName,
    String? phone,
    required List<String> roleNames,
    List<int> branchIds = const [],
    List<String> workshops = const [],
  }) async {
    final r = await http
        .post(
          _u('/company/users'),
          headers: _auth(accessToken),
          body: jsonEncode({
            'email': email.trim().toLowerCase(),
            'password': password,
            'full_name': fullName.trim(),
            if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
            'role_names': roleNames,
            'branch_ids': branchIds,
            'workshops': workshops,
            'link_master': true,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    return AuthUser.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<AuthUser> assignUser({
    required String accessToken,
    required int userId,
    required List<String> roleNames,
    List<int> branchIds = const [],
    List<String> workshops = const [],
  }) async {
    final r = await http
        .patch(
          _u('/company/users/$userId/assign'),
          headers: _auth(accessToken),
          body: jsonEncode({
            'role_names': roleNames,
            'branch_ids': branchIds,
            'workshops': workshops,
            'link_master': true,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    return AuthUser.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  String _err(http.Response r) {
    try {
      final m = jsonDecode(utf8.decode(r.bodyBytes));
      if (m is Map && m['detail'] != null) {
        final d = m['detail'];
        if (d is String) return d;
        return d.toString();
      }
    } catch (_) {}
    return 'Ошибка API (${r.statusCode})';
  }
}

class CompanyRole {
  final int id;
  final String name;

  const CompanyRole({required this.id, required this.name});

  factory CompanyRole.fromJson(Map<String, dynamic> j) => CompanyRole(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name']?.toString() ?? '',
      );
}

class CompanyBranch {
  final int id;
  final String name;
  final bool isActive;

  const CompanyBranch({
    required this.id,
    required this.name,
    this.isActive = true,
  });

  factory CompanyBranch.fromJson(Map<String, dynamic> j) => CompanyBranch(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name']?.toString() ?? '',
        isActive: j['is_active'] != false,
      );
}
