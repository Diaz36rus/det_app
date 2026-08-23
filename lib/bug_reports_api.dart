import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_version.dart';
import 'auth/auth_api.dart';
import 'auth/auth_controller.dart';
import 'database.dart';

/// Облачные баг-репорты: POST /bugs, список для platform admin.
class BugReportsApi {
  BugReportsApi({this.baseUrl = AuthApi.defaultBaseUrl});

  final String baseUrl;

  static final BugReportsApi instance = BugReportsApi();

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q);

  Map<String, String> _headers({String? token}) {
    final h = <String, String>{'Content-Type': 'application/json'};
    final t = token ?? AuthController.instance.accessToken;
    if (t != null && t.isNotEmpty) {
      h['Authorization'] = 'Bearer $t';
    }
    return h;
  }

  static String detectPlatform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isWindows) return 'windows';
      if (Platform.isIOS) return 'ios';
      if (Platform.isMacOS) return 'macos';
      if (Platform.isLinux) return 'linux';
    } catch (_) {}
    return defaultTargetPlatform.name;
  }

  /// Отправить на сервер. Возвращает cloud id или null при ошибке.
  Future<int?> submit({
    required String place,
    required String situation,
    required String details,
    int? clientLocalId,
  }) async {
    await AppVersion.ensureLoaded();
    final body = <String, dynamic>{
      'place': place,
      'situation': situation,
      'details': details,
      'app_version': AppVersion.version,
      'app_build': AppVersion.build,
      'platform': detectPlatform(),
      if (clientLocalId != null) 'client_local_id': clientLocalId,
    };
    final r = await http
        .post(_u('/bugs'), headers: _headers(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return (j['id'] as num?)?.toInt();
  }

  Future<List<CloudBugReport>> listCloud({
    String? status,
    int limit = 100,
    String? releaseToken,
  }) async {
    final q = <String, String>{'limit': '$limit'};
    if (status != null && status.isNotEmpty) q['status'] = status;
    final headers = _headers();
    if (releaseToken != null && releaseToken.isNotEmpty) {
      headers['X-Release-Token'] = releaseToken;
    }
    final r = await http
        .get(_u('/bugs', q), headers: headers)
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List<dynamic>;
    return list
        .map((e) => CloudBugReport.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> patchCloud({
    required int id,
    String? status,
    String? fixNote,
  }) async {
    final body = <String, dynamic>{};
    if (status != null) body['status'] = status;
    if (fixNote != null) body['fix_note'] = fixNote;
    final r = await http
        .patch(_u('/bugs/$id'), headers: _headers(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw AuthApiException(_err(r), statusCode: r.statusCode);
    }
  }

  /// Локально сохранить + попытаться улететь в облако.
  Future<({int localId, bool sent, String? error})> saveAndUpload({
    required String place,
    required String situation,
    required String details,
  }) async {
    final localId = await DatabaseHelper().addBugReport(
      place: place,
      situation: situation,
      details: details,
      syncStatus: 'pending',
    );
    try {
      final cloudId = await submit(
        place: place,
        situation: situation,
        details: details,
        clientLocalId: localId,
      );
      if (cloudId != null) {
        await DatabaseHelper().updateBugReportSync(
          localId,
          syncStatus: 'sent',
          cloudId: cloudId,
        );
        return (localId: localId, sent: true, error: null);
      }
      await DatabaseHelper().updateBugReportSync(localId, syncStatus: 'failed');
      return (localId: localId, sent: false, error: 'Сервер не вернул id');
    } catch (e) {
      await DatabaseHelper().updateBugReportSync(localId, syncStatus: 'failed');
      return (localId: localId, sent: false, error: e.toString());
    }
  }

  /// Повторно отправить неотправленные (после восстановления сети).
  Future<int> flushPending() async {
    final rows = await DatabaseHelper().getBugReportsPendingSync();
    var ok = 0;
    for (final r in rows) {
      final id = (r['id'] as num?)?.toInt();
      if (id == null) continue;
      try {
        final cloudId = await submit(
          place: r['place']?.toString() ?? '',
          situation: r['situation']?.toString() ?? '',
          details: r['details']?.toString() ?? '',
          clientLocalId: id,
        );
        if (cloudId != null) {
          await DatabaseHelper().updateBugReportSync(
            id,
            syncStatus: 'sent',
            cloudId: cloudId,
          );
          ok++;
        }
      } catch (_) {
        await DatabaseHelper().updateBugReportSync(id, syncStatus: 'failed');
      }
    }
    return ok;
  }

  static String _err(http.Response r) {
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is Map && j['detail'] != null) return j['detail'].toString();
    } catch (_) {}
    return 'Ошибка сервера (${r.statusCode})';
  }
}

class CloudBugReport {
  final int id;
  final String place;
  final String situation;
  final String details;
  final String status;
  final String fixNote;
  final String appVersion;
  final int appBuild;
  final String platform;
  final String userEmail;
  final String userName;
  final String companyName;
  final String companySlug;
  final String createdAt;

  CloudBugReport({
    required this.id,
    required this.place,
    required this.situation,
    required this.details,
    required this.status,
    required this.fixNote,
    required this.appVersion,
    required this.appBuild,
    required this.platform,
    required this.userEmail,
    required this.userName,
    required this.companyName,
    required this.companySlug,
    required this.createdAt,
  });

  factory CloudBugReport.fromJson(Map<String, dynamic> j) {
    return CloudBugReport(
      id: (j['id'] as num?)?.toInt() ?? 0,
      place: j['place']?.toString() ?? '',
      situation: j['situation']?.toString() ?? '',
      details: j['details']?.toString() ?? '',
      status: j['status']?.toString() ?? 'open',
      fixNote: j['fix_note']?.toString() ?? '',
      appVersion: j['app_version']?.toString() ?? '',
      appBuild: (j['app_build'] as num?)?.toInt() ?? 0,
      platform: j['platform']?.toString() ?? '',
      userEmail: j['user_email']?.toString() ?? '',
      userName: j['user_name']?.toString() ?? '',
      companyName: j['company_name']?.toString() ?? '',
      companySlug: j['company_slug']?.toString() ?? '',
      createdAt: j['created_at']?.toString() ?? '',
    );
  }
}
