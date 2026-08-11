import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sync_config.dart';

/// Найденный хост Det App в LAN.
class DiscoveredHost {
  final String baseUrl;
  final String ip;
  final int port;

  const DiscoveredHost({
    required this.baseUrl,
    required this.ip,
    required this.port,
  });
}

/// Скан подсети: GET /health?token=… на :7878.
class LanDiscover {
  LanDiscover._();

  static const _probeTimeout = Duration(milliseconds: 450);
  static const _concurrency = 40;

  /// Ищет хосты в /24 сетях локальных интерфейсов.
  /// [onProgress] — (проверено, всего).
  static Future<List<DiscoveredHost>> findHosts({
    String token = SyncConfig.defaultToken,
    int port = SyncConfig.defaultPort,
    void Function(int done, int total)? onProgress,
  }) async {
    final prefixes = await _subnetPrefixes();
    if (prefixes.isEmpty) return [];

    final targets = <String>[];
    for (final prefix in prefixes) {
      for (var i = 1; i <= 254; i++) {
        targets.add('$prefix.$i');
      }
    }

    final found = <DiscoveredHost>[];
    final seen = <String>{};
    var done = 0;
    final total = targets.length;

    Future<void> probe(String ip) async {
      final host = await _probeHost(ip: ip, port: port, token: token);
      if (host != null && seen.add(host.baseUrl)) {
        found.add(host);
      }
      done++;
      onProgress?.call(done, total);
    }

    // Пул параллельных запросов.
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= targets.length) return;
        await probe(targets[i]);
      }
    }

    await Future.wait(List.generate(_concurrency, (_) => worker()));
    found.sort((a, b) => a.ip.compareTo(b.ip));
    return found;
  }

  static Future<DiscoveredHost?> _probeHost({
    required String ip,
    required int port,
    required String token,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = _probeTimeout
        ..idleTimeout = _probeTimeout
        ..badCertificateCallback = (_, __, ___) => true;
      final uri = Uri(
        scheme: 'http',
        host: ip,
        port: port,
        path: '/health',
        queryParameters: {'token': token},
      );
      final req = await client.getUrl(uri).timeout(_probeTimeout);
      req.headers.set('x-det-token', token);
      final res = await req.close().timeout(_probeTimeout);
      final body = await utf8.decoder.bind(res).join().timeout(_probeTimeout);
      if (res.statusCode != 200) return null;
      final map = jsonDecode(body);
      if (map is! Map) return null;
      if (map['ok'] != true) return null;
      final role = map['role']?.toString();
      if (role != null && role != 'host') return null;
      return DiscoveredHost(
        baseUrl: 'http://$ip:$port',
        ip: ip,
        port: port,
      );
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  /// Префиксы вида `192.168.1` из локальных IPv4.
  static Future<List<String>> _subnetPrefixes() async {
    final out = <String>{};
    try {
      for (final iface in await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      )) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final parts = addr.address.split('.');
          if (parts.length != 4) continue;
          // Типичные частные сети; иначе всё равно сканируем /24.
          out.add('${parts[0]}.${parts[1]}.${parts[2]}');
        }
      }
    } catch (_) {}
    return out.toList();
  }
}
