import 'package:flutter/foundation.dart';

import '../database.dart';
import 'sync_config.dart';
import 'sync_server.dart';

/// Управление режимом local / host / client.
class SyncController extends ChangeNotifier {
  SyncController._();
  static final SyncController instance = SyncController._();

  SyncConfig config = SyncConfig();
  SyncServer? _server;
  List<String> lanIps = [];
  String? lastError;
  bool ready = false;

  bool get isHosting => _server?.isRunning == true;
  String? get suggestedClientUrl {
    if (lanIps.isEmpty) return null;
    return 'http://${lanIps.first}:${config.port}';
  }

  Future<void> load() async {
    config = await SyncConfig.load();
    lanIps = await SyncConfig.lanIpv4Addresses();
    ready = true;
    notifyListeners();
  }

  /// Вызвать после открытия локальной БД (не для client).
  Future<void> startHostIfNeeded() async {
    if (!config.isHost) return;
    await _startServer();
  }

  Future<void> _startServer() async {
    await _server?.stop();
    _server = null;
    try {
      final db = await DatabaseHelper().database;
      final server = SyncServer(
        database: db,
        token: config.token,
        port: config.port,
      );
      await server.start();
      _server = server;
      lanIps = await SyncConfig.lanIpv4Addresses();
      lastError = null;
      await DatabaseHelper().setAppSetting(
        'sync_base_url',
        suggestedClientUrl ?? 'http://127.0.0.1:${config.port}',
      );
    } catch (e, st) {
      lastError = 'Не удалось запустить хост: $e';
      debugPrint('$lastError\n$st');
    }
    notifyListeners();
  }

  Future<void> stopHost() async {
    await _server?.stop();
    _server = null;
    notifyListeners();
  }

  /// Переключить режим. После client/local — нужен reopen БД.
  Future<String?> applyRole({
    required SyncRole role,
    String? baseUrl,
    int? port,
    String? token,
  }) async {
    lastError = null;
    if (role == SyncRole.host) {
      await stopHost();
      // Сначала убедимся что БД локальная
      await DatabaseHelper().reopenAsLocal();
      config.role = SyncRole.host;
      config.port = port ?? config.port;
      if (token != null && token.isNotEmpty) config.token = token;
      config.baseUrl = '';
      await config.save();
      await _startServer();
      if (lastError != null) return lastError;
      return null;
    }

    if (role == SyncRole.client) {
      final url = (baseUrl ?? config.baseUrl).trim();
      if (url.isEmpty) {
        lastError = 'Укажите адрес хоста, например http://192.168.1.10:7878';
        notifyListeners();
        return lastError;
      }
      await stopHost();
      config.role = SyncRole.client;
      config.baseUrl = url;
      config.port = port ?? config.port;
      if (token != null && token.isNotEmpty) config.token = token;
      await config.save();
      try {
        await DatabaseHelper().reopenAsClient(
          url: config.normalizedBaseUrl,
          token: config.token,
        );
        await DatabaseHelper().setAppSetting('sync_base_url', config.normalizedBaseUrl);
        lastError = null;
      } catch (e) {
        lastError = 'Нет связи с хостом: $e';
        // Откат на local, чтобы приложение жило
        config.role = SyncRole.local;
        await config.save();
        await DatabaseHelper().reopenAsLocal();
        notifyListeners();
        return lastError;
      }
      notifyListeners();
      return null;
    }

    // local
    await stopHost();
    config.role = SyncRole.local;
    config.baseUrl = '';
    await config.save();
    await DatabaseHelper().reopenAsLocal();
    await DatabaseHelper().setAppSetting('sync_base_url', '');
    notifyListeners();
    return null;
  }

  Future<void> saveClientUrl(String url) async {
    await applyRole(role: SyncRole.client, baseUrl: url);
  }
}
