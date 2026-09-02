import 'package:http/http.dart' as http;

import 'auth_api.dart';
import 'auth_controller.dart';

/// HTTP с Bearer-токеном и одним повтором после refresh при 401.
Future<http.Response> authedRequest(
  Future<http.Response> Function(Map<String, String> headers) send, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  Future<http.Response> once() async {
    final token = AuthController.instance.accessToken;
    if (token == null || token.isEmpty) {
      throw AuthApiException('Нет сессии — войдите снова', statusCode: 401);
    }
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    return send(headers).timeout(timeout);
  }

  var response = await once();
  if (response.statusCode != 401) return response;

  final ok = await AuthController.instance.refreshAccessToken();
  if (!ok) return response;
  return once();
}

Future<http.Response> authedGet(
  Uri uri, {
  Duration timeout = const Duration(seconds: 15),
}) =>
    authedRequest((h) => http.get(uri, headers: h), timeout: timeout);

Future<http.Response> authedPost(
  Uri uri, {
  Object? body,
  Duration timeout = const Duration(seconds: 15),
}) =>
    authedRequest((h) => http.post(uri, headers: h, body: body), timeout: timeout);

Future<http.Response> authedPatch(
  Uri uri, {
  Object? body,
  Duration timeout = const Duration(seconds: 15),
}) =>
    authedRequest((h) => http.patch(uri, headers: h, body: body), timeout: timeout);

Future<http.Response> authedDelete(
  Uri uri, {
  Object? body,
  Duration timeout = const Duration(seconds: 15),
}) =>
    authedRequest(
      (h) => body == null
          ? http.delete(uri, headers: h)
          : http.delete(uri, headers: h, body: body),
      timeout: timeout,
    );

Future<http.Response> authedPut(
  Uri uri, {
  Object? body,
  Duration timeout = const Duration(seconds: 15),
}) =>
    authedRequest((h) => http.put(uri, headers: h, body: body), timeout: timeout);
