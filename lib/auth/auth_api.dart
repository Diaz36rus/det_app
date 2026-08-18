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

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Future<AuthTokens> login({required String login, required String password}) async {
    final ident = login.trim();
    // login — новый контракт (0.4+); email дублируем для совместимости с API 0.3.
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
    final map = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final tokens = AuthTokens.fromJson(map);
    if (!tokens.isValid) {
      throw AuthApiException('Сервер не вернул токены');
    }
    return tokens;
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
