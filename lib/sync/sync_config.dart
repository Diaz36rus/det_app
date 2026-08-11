import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum SyncRole { local, host, client }

/// Локальный файл настроек связи (не в SQLite — иначе клиент не узнает URL до подключения).
class SyncConfig {
  SyncRole role;
  int port;
  String baseUrl;
  String token;

  SyncConfig({
    this.role = SyncRole.local,
    this.port = defaultPort,
    this.baseUrl = '',
    this.token = defaultToken,
  });

  static const defaultPort = 7878;
  static const defaultToken = 'det-lan';
  static const fileName = 'det_sync_config.json';

  bool get isHost => role == SyncRole.host;
  bool get isClient => role == SyncRole.client;
  bool get isLocal => role == SyncRole.local;

  String get normalizedBaseUrl {
    var u = baseUrl.trim();
    if (u.isEmpty) return '';
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'port': port,
        'baseUrl': baseUrl,
        'token': token,
      };

  factory SyncConfig.fromJson(Map<String, dynamic> j) {
    final roleName = j['role']?.toString() ?? 'local';
    final role = SyncRole.values.firstWhere(
      (r) => r.name == roleName,
      orElse: () => SyncRole.local,
    );
    return SyncConfig(
      role: role,
      port: (j['port'] as num?)?.toInt() ?? defaultPort,
      baseUrl: j['baseUrl']?.toString() ?? '',
      token: (j['token']?.toString().isNotEmpty == true)
          ? j['token'].toString()
          : defaultToken,
    );
  }

  static Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, fileName));
  }

  static Future<SyncConfig> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return SyncConfig();
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return SyncConfig.fromJson(map);
    } catch (_) {
      return SyncConfig();
    }
  }

  Future<void> save() async {
    final f = await _file();
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()));
  }

  /// IPv4 адреса интерфейсов (без loopback) — чтобы показать на UI хоста.
  static Future<List<String>> lanIpv4Addresses() async {
    final out = <String>[];
    try {
      for (final iface in await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      )) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          out.add(addr.address);
        }
      }
    } catch (_) {}
    return out;
  }
}
