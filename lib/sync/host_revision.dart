import 'dart:convert';
import 'dart:io';

import 'sync_config.dart';

/// Версия данных хоста из GET /health (SQLite data_version).
class HostRevision {
  HostRevision._();

  static Future<int?> fetch({
    required String baseUrl,
    String token = SyncConfig.defaultToken,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    HttpClient? client;
    try {
      var u = baseUrl.trim();
      while (u.endsWith('/')) {
        u = u.substring(0, u.length - 1);
      }
      if (u.isEmpty) return null;
      var uri = Uri.parse('$u/health');
      uri = uri.replace(queryParameters: {...uri.queryParameters, 'token': token});
      client = HttpClient()
        ..connectionTimeout = timeout
        ..idleTimeout = timeout;
      final req = await client.getUrl(uri).timeout(timeout);
      req.headers.set('x-det-token', token);
      final res = await req.close().timeout(timeout);
      final body = await utf8.decoder.bind(res).join().timeout(timeout);
      if (res.statusCode != 200) return null;
      final map = jsonDecode(body);
      if (map is! Map) return null;
      final rev = map['rev'];
      if (rev is int) return rev;
      if (rev is num) return rev.toInt();
      return int.tryParse(rev?.toString() ?? '');
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }
}
