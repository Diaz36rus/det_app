import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_models.dart';

class AuthApiException implements Exception {
  final String message;
  final int? statusCode;
  AuthApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class AuthApi {
  AuthApi({this.baseUrl = defaultBaseUrl});

  static const defaultBaseUrl = 'http://api.det-app.ru';

  final String baseUrl;

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q);

  Future<AuthTokens> login({required String login, required String password}) async {
    final ident = login.trim();
    final body = <String, dynamic>{
      'login': ident,
      'password': password,
    };
    if (ident.contains('@')) {
      body['email'] = ident.toLowerCase();
    }
    final r = await http
        .post(
          _u('/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    final tokens = AuthTokens.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
    if (!tokens.isValid) {
      throw AuthApiException('Сервер не вернул токены');
    }
    return tokens;
  }

  Future<AuthTokens> registerStudio({
    required String studioName,
    required String slug,
    required String branchName,
    required String fullName,
    required String email,
    required String password,
    String? phone,
  }) async {
    final r = await http
        .post(
          _u('/auth/register-studio'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'studio_name': studioName.trim(),
            'slug': slug.trim().toLowerCase(),
            'branch_name': branchName.trim(),
            'full_name': fullName.trim(),
            'email': email.trim().toLowerCase(),
            'password': password,
            if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    final tokens = AuthTokens.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
    if (!tokens.isValid) {
      throw AuthApiException('Сервер не вернул токены');
    }
    return tokens;
  }

  Future<AuthTokens> requestAccess({
    required String companySlug,
    required String fullName,
    required String email,
    required String password,
    String? phone,
  }) async {
    final r = await http
        .post(
          _u('/auth/request-access'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'company_slug': companySlug.trim().toLowerCase(),
            'full_name': fullName.trim(),
            'email': email.trim().toLowerCase(),
            'password': password,
            if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    final tokens = AuthTokens.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
    if (!tokens.isValid) {
      throw AuthApiException('Сервер не вернул токены');
    }
    return tokens;
  }

  Future<StudioLookup> studioLookup(String slug) async {
    final r = await http
        .get(_u('/auth/studio-lookup', {'slug': slug.trim().toLowerCase()}))
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    return StudioLookup.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<AuthTokens> refresh(String refreshToken) async {
    final r = await http
        .post(
          _u('/auth/refresh'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': refreshToken}),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    return AuthTokens.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<AuthUser> me(String accessToken) async {
    final r = await http
        .get(
          _u('/auth/me'),
          headers: {'Authorization': 'Bearer $accessToken'},
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    return AuthUser.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  String _err(http.Response r) {
    try {
      final map = jsonDecode(utf8.decode(r.bodyBytes));
      if (map is Map && map['detail'] != null) {
        final d = map['detail'];
        if (d is String) return d;
        return d.toString();
      }
    } catch (_) {}
    if (r.statusCode == 401) return 'Неверный логин или пароль';
    return 'Ошибка сервера (${r.statusCode})';
  }
}

class StudioLookup {
  final int id;
  final String name;
  final String slug;

  const StudioLookup({required this.id, required this.name, required this.slug});

  factory StudioLookup.fromJson(Map<String, dynamic> j) => StudioLookup(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name']?.toString() ?? '',
        slug: j['slug']?.toString() ?? '',
      );
}
