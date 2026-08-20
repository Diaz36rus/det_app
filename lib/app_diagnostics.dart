import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'auth/auth_api.dart';
import 'crm/cloud_mode.dart';
import 'database.dart';
import 'sync/sync_config.dart';
import 'sync/sync_controller.dart';

enum ConnStatus { ok, down }

/// Диагностика: статус «связи» + кольцевой лог ошибок для баг-репортов.
class AppDiagnostics extends ChangeNotifier {
  AppDiagnostics._();
  static final AppDiagnostics instance = AppDiagnostics._();

  static const _maxMemory = 80;
  static const _autoBugThrottle = Duration(hours: 2);

  ConnStatus _status = ConnStatus.ok;
  String _statusDetail = 'Локальный режим';
  String? _syncBaseUrl;
  DateTime? _lastAutoBugAt;
  final List<DiagEntry> _memory = [];
  Timer? _pingTimer;
  bool _started = false;

  ConnStatus get status => _status;
  String get statusDetail => _statusDetail;
  bool get isOk => _status == ConnStatus.ok;
  String? get syncBaseUrl => _syncBaseUrl;
  List<DiagEntry> get recentErrors => List.unmodifiable(_memory);

  Future<void> start() async {
    if (_started) return;
    _started = true;

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      final msg = details.exceptionAsString();
      final overflow = msg.contains('OVERFLOWED') || msg.contains('overflowed');
      unawaited(log(
        level: overflow ? 'warn' : 'error',
        source: 'FlutterError',
        message: msg,
        stack: details.stack?.toString(),
        autoBug: !overflow,
      ));
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(log(
        level: 'error',
        source: 'PlatformDispatcher',
        message: error.toString(),
        stack: stack.toString(),
      ));
      return true;
    };

    try {
      final cfg = SyncController.instance.config;
      if (cfg.isClient) {
        _syncBaseUrl = cfg.normalizedBaseUrl;
      } else if (cfg.isHost) {
        _syncBaseUrl = SyncController.instance.suggestedClientUrl;
      } else {
        _syncBaseUrl = await DatabaseHelper().getAppSetting('sync_base_url');
      }
      final rows = await DatabaseHelper().getAppErrorLogs(limit: 40);
      for (final r in rows.reversed) {
        _memory.add(DiagEntry.fromMap(r));
      }
      while (_memory.length > _maxMemory) {
        _memory.removeAt(0);
      }
    } catch (e, st) {
      debugPrint('AppDiagnostics.start DB: $e\n$st');
    }

    await refreshConnection(force: true);
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(refreshConnection());
    });
  }

  Future<void> setSyncBaseUrl(String? url) async {
    final trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty) {
      await SyncController.instance.applyRole(role: SyncRole.local);
      _syncBaseUrl = null;
    } else {
      final err = await SyncController.instance.applyRole(
        role: SyncRole.client,
        baseUrl: trimmed,
      );
      _syncBaseUrl = SyncController.instance.config.normalizedBaseUrl;
      if (err != null) {
        await log(level: 'error', source: 'SyncConnect', message: err, autoBug: true);
      }
    }
    await refreshConnection(force: true);
  }

  Future<void> refreshConnection({bool force = false}) async {
    final sync = SyncController.instance;
    final cfg = sync.config;

    // Облачная сессия важнее LAN-роли для индикатора.
    if (CloudMode.sessionActive && !cfg.isClient) {
      final ok = await _ping(AuthApi.defaultBaseUrl);
      _syncBaseUrl = AuthApi.defaultBaseUrl;
      if (ok) {
        _setStatus(ConnStatus.ok, 'Облако · api.det-app.ru');
      } else {
        _setStatus(ConnStatus.down, 'Облако недоступно');
      }
      return;
    }

    if (cfg.isHost) {
      if (sync.isHosting) {
        final url = sync.suggestedClientUrl ?? 'порт ${cfg.port}';
        _syncBaseUrl = url;
        _setStatus(ConnStatus.ok, 'Хост активен · клиенты: $url');
      } else {
        _setStatus(
          ConnStatus.down,
          sync.lastError ?? 'Хост не запущен (проверьте порт / firewall)',
        );
      }
      return;
    }

    if (cfg.isClient) {
      final url = cfg.normalizedBaseUrl;
      _syncBaseUrl = url;
      final ok = await _ping(url, token: cfg.token);
      if (ok) {
        _setStatus(ConnStatus.ok, 'Клиент · связь с $url');
      } else {
        _setStatus(ConnStatus.down, 'Клиент · нет связи с $url');
        await log(
          level: 'error',
          source: 'SyncPing',
          message: 'Не удалось подключиться к $url',
          autoBug: true,
        );
      }
      return;
    }

    _syncBaseUrl = null;
    final hasRecentError = _memory.any(
      (e) =>
          (e.level == 'error' || e.level == 'fatal') &&
          DateTime.now().difference(e.at) < const Duration(minutes: 30),
    );
    if (hasRecentError) {
      _setStatus(ConnStatus.down, 'Есть ошибки за последние 30 мин');
    } else {
      _setStatus(ConnStatus.ok, 'Локальный режим (один ПК)');
    }
  }

  Future<bool> _ping(String baseUrl, {String? token}) async {
    HttpClient? client;
    try {
      final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      var uri = Uri.parse('$base/health');
      if (token != null && token.isNotEmpty) {
        uri = uri.replace(queryParameters: {'token': token});
      }
      client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 4));
      if (token != null) req.headers.set('x-det-token', token);
      final res = await req.close().timeout(const Duration(seconds: 4));
      await res.drain<void>();
      return res.statusCode >= 200 && res.statusCode < 500;
    } catch (_) {
      try {
        final uri = Uri.parse(baseUrl);
        final host = uri.host;
        final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
        final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
        await socket.close();
        return true;
      } catch (_) {
        return false;
      }
    } finally {
      client?.close(force: true);
    }
  }

  void _setStatus(ConnStatus next, String detail) {
    if (_status == next && _statusDetail == detail) return;
    _status = next;
    _statusDetail = detail;
    notifyListeners();
  }

  Future<void> acknowledgeLocalErrors() async {
    final cfg = SyncController.instance.config;
    if (cfg.isClient || cfg.isHost) {
      await refreshConnection(force: true);
      return;
    }
    _setStatus(ConnStatus.ok, 'Локальный режим (ошибки просмотрены)');
  }

  Future<void> log({
    required String level,
    required String source,
    required String message,
    String? stack,
    bool autoBug = false,
  }) async {
    final entry = DiagEntry(
      at: DateTime.now(),
      level: level,
      source: source,
      message: message,
      stack: stack,
    );
    _memory.add(entry);
    while (_memory.length > _maxMemory) {
      _memory.removeAt(0);
    }

    if (level == 'error' || level == 'fatal') {
      _setStatus(ConnStatus.down, 'Есть ошибки — см. лог / баг-репорт');
    }

    try {
      await DatabaseHelper().addAppErrorLog(
        level: level,
        source: source,
        message: message,
        stack: stack,
      );
    } catch (e) {
      debugPrint('AppDiagnostics.persist: $e');
    }

    notifyListeners();

    if (autoBug || level == 'fatal' || level == 'error') {
      await _maybeAutoBug(entry);
    }
  }

  Future<void> _maybeAutoBug(DiagEntry entry) async {
    final now = DateTime.now();
    if (_lastAutoBugAt != null && now.difference(_lastAutoBugAt!) < _autoBugThrottle) {
      return;
    }
    _lastAutoBugAt = now;
    try {
      await DatabaseHelper().addBugReport(
        place: 'Автолог · ${entry.source}',
        situation: 'Сбой зафиксирован автоматически (смена на работе)',
        details: formatLogForBugReport(limit: 25),
      );
    } catch (e) {
      debugPrint('AppDiagnostics.autoBug: $e');
    }
  }

  String formatLogForBugReport({int limit = 40}) {
    final buf = StringBuffer();
    final cfg = SyncController.instance.config;
    buf.writeln('=== DIAG ${DateTime.now().toIso8601String()} ===');
    buf.writeln('status: ${_status.name} · $_statusDetail');
    buf.writeln('sync_role: ${cfg.role.name}');
    buf.writeln('sync_url: ${_syncBaseUrl?.isNotEmpty == true ? _syncBaseUrl : "(local)"}');
    buf.writeln('platform: ${Platform.operatingSystem}');
    buf.writeln('--- last $limit events ---');
    final slice = _memory.length <= limit ? _memory : _memory.sublist(_memory.length - limit);
    for (final e in slice) {
      buf.writeln(e.format());
      buf.writeln('---');
    }
    return buf.toString();
  }

  void disposeTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }
}

class DiagEntry {
  final DateTime at;
  final String level;
  final String source;
  final String message;
  final String? stack;

  DiagEntry({
    required this.at,
    required this.level,
    required this.source,
    required this.message,
    this.stack,
  });

  factory DiagEntry.fromMap(Map<String, dynamic> m) {
    return DiagEntry(
      at: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
      level: m['level']?.toString() ?? 'error',
      source: m['source']?.toString() ?? '',
      message: m['message']?.toString() ?? '',
      stack: m['stack']?.toString(),
    );
  }

  String format() {
    final t = at.toIso8601String().substring(0, 19);
    final s = StringBuffer('[$t][$level][$source] $message');
    if (stack != null && stack!.trim().isNotEmpty) {
      final lines = stack!.split('\n').take(12).join('\n');
      s.writeln();
      s.write(lines);
    }
    return s.toString();
  }
}

class ConnStatusDot extends StatelessWidget {
  final VoidCallback? onTap;
  final double size;

  const ConnStatusDot({super.key, this.onTap, this.size = 10});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppDiagnostics.instance, SyncController.instance]),
      builder: (context, _) {
        final ok = AppDiagnostics.instance.isOk;
        final role = SyncController.instance.config.role;
        final color = ok ? AppColors.success : AppColors.danger;
        final roleLabel = CloudMode.sessionActive && !SyncController.instance.config.isClient
            ? 'Облако'
            : switch (role) {
                SyncRole.host => 'Хост',
                SyncRole.client => 'Клиент',
                SyncRole.local => 'Локально',
              };
        final tip = ok
            ? '$roleLabel · OK · ${AppDiagnostics.instance.statusDetail}'
            : '$roleLabel · нет связи · ${AppDiagnostics.instance.statusDetail}';
        return Tooltip(
          message: tip,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.45),
                          blurRadius: 6,
                          spreadRadius: 0.5,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    roleLabel,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
