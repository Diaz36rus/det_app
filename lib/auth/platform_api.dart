import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_api.dart';
import 'company_api.dart';

/// Platform admin: студии и филиалы.
class PlatformApi {
  PlatformApi({this.baseUrl = AuthApi.defaultBaseUrl});

  final String baseUrl;

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _auth(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Future<List<PlatformCompany>> listCompanies({required String accessToken}) async {
    final r = await http
        .get(_u('/platform/companies'), headers: _auth(accessToken))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List<dynamic>;
    return list.map((e) => PlatformCompany.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CompanyCreated> createCompany({
    required String accessToken,
    required String name,
    required String slug,
    String branchName = 'Основной филиал',
    String? ownerEmail,
    String? ownerPassword,
    String? ownerFullName,
    String? ownerPhone,
  }) async {
    final body = <String, dynamic>{
      'name': name.trim(),
      'slug': slug.trim().toLowerCase(),
      'branch_name': branchName.trim(),
    };
    if (ownerEmail != null && ownerEmail.trim().isNotEmpty) {
      body['owner_email'] = ownerEmail.trim().toLowerCase();
      body['owner_password'] = ownerPassword;
      if (ownerFullName != null && ownerFullName.trim().isNotEmpty) {
        body['owner_full_name'] = ownerFullName.trim();
      }
      if (ownerPhone != null && ownerPhone.trim().isNotEmpty) {
        body['owner_phone'] = ownerPhone.trim();
      }
    }
    final r = await http
        .post(_u('/platform/companies'), headers: _auth(accessToken), body: jsonEncode(body))
        .timeout(const Duration(seconds: 25));
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    return CompanyCreated.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<List<CompanyBranch>> listCompanyBranches({
    required String accessToken,
    required int companyId,
  }) async {
    final r = await http
        .get(_u('/platform/companies/$companyId/branches'), headers: _auth(accessToken))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List<dynamic>;
    return list.map((e) => CompanyBranch.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CompanyBranch> createPlatformBranch({
    required String accessToken,
    required int companyId,
    required String name,
  }) async {
    final r = await http
        .post(
          _u('/platform/companies/$companyId/branches'),
          headers: _auth(accessToken),
          body: jsonEncode({'name': name.trim()}),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    return CompanyBranch.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<PlatformCompany> setCompanyActive({
    required String accessToken,
    required int companyId,
    required bool isActive,
  }) async {
    final r = await http
        .patch(
          _u('/platform/companies/$companyId'),
          headers: _auth(accessToken),
          body: jsonEncode({'is_active': isActive}),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    return PlatformCompany.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> wipeOrDeleteCompany({
    required String accessToken,
    required int companyId,
    bool hard = false,
    bool wipeData = false,
  }) async {
    final q = <String, String>{};
    if (hard) q['hard'] = 'true';
    if (wipeData) q['wipe_data'] = 'true';
    final r = await http
        .delete(
          _u('/platform/companies/$companyId').replace(queryParameters: q),
          headers: _auth(accessToken),
        )
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<List<PlatformUser>> listCompanyUsers({
    required String accessToken,
    required int companyId,
  }) async {
    final r = await http
        .get(_u('/platform/companies/$companyId/users'), headers: _auth(accessToken))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List<dynamic>;
    return list.map((e) => PlatformUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<PlatformUser> setUserActive({
    required String accessToken,
    required int userId,
    required bool isActive,
  }) async {
    final r = await http
        .patch(
          _u('/platform/users/$userId').replace(queryParameters: {'is_active': '$isActive'}),
          headers: _auth(accessToken),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    return PlatformUser.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<void> deleteUser({
    required String accessToken,
    required int userId,
  }) async {
    final r = await http
        .delete(_u('/platform/users/$userId'), headers: _auth(accessToken))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
  }

  Future<CompanyBranch> setBranchActive({
    required String accessToken,
    required int branchId,
    required bool isActive,
  }) async {
    final r = await http
        .patch(
          _u('/platform/branches/$branchId').replace(queryParameters: {'is_active': '$isActive'}),
          headers: _auth(accessToken),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    return CompanyBranch.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
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

class PlatformCompany {
  final int id;
  final String name;
  final String slug;
  final bool isActive;

  const PlatformCompany({
    required this.id,
    required this.name,
    required this.slug,
    required this.isActive,
  });

  factory PlatformCompany.fromJson(Map<String, dynamic> j) => PlatformCompany(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name']?.toString() ?? '',
        slug: j['slug']?.toString() ?? '',
        isActive: j['is_active'] != false,
      );
}

class PlatformUser {
  final int id;
  final String email;
  final String? phone;
  final String fullName;
  final bool isActive;
  final List<String> roles;
  final bool pendingAssignment;
  final int? companyId;

  const PlatformUser({
    required this.id,
    required this.email,
    this.phone,
    required this.fullName,
    required this.isActive,
    this.roles = const [],
    this.pendingAssignment = false,
    this.companyId,
  });

  factory PlatformUser.fromJson(Map<String, dynamic> j) => PlatformUser(
        id: (j['id'] as num?)?.toInt() ?? 0,
        email: j['email']?.toString() ?? '',
        phone: j['phone']?.toString(),
        fullName: j['full_name']?.toString() ?? '',
        isActive: j['is_active'] != false,
        roles: (j['roles'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        pendingAssignment: j['pending_assignment'] == true,
        companyId: (j['company_id'] as num?)?.toInt(),
      );

  String get displayLabel {
    if (fullName.trim().isNotEmpty) return fullName.trim();
    return email;
  }
}

class CompanyCreated {
  final PlatformCompany company;
  final CompanyBranch branch;
  final int? ownerUserId;
  final String? ownerEmail;

  const CompanyCreated({
    required this.company,
    required this.branch,
    this.ownerUserId,
    this.ownerEmail,
  });

  factory CompanyCreated.fromJson(Map<String, dynamic> j) => CompanyCreated(
        company: PlatformCompany.fromJson(j['company'] as Map<String, dynamic>? ?? {}),
        branch: CompanyBranch.fromJson(j['branch'] as Map<String, dynamic>? ?? {}),
        ownerUserId: (j['owner_user_id'] as num?)?.toInt(),
        ownerEmail: j['owner_email']?.toString(),
      );
}
