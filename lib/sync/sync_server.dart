import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database.dart';
import 'sync_protocol.dart';

/// Локальный LAN-сервер: одна SQLite на хосте, клиенты шлют SQL-операции по HTTP.
class SyncServer {
  SyncServer({
    required this.database,
    required this.token,
    this.port = 7878,
  });

  final Database database;
  final String token;
  final int port;

  HttpServer? _server;
  Future<void> _queue = Future.value();

  bool get isRunning => _server != null;
  int? get boundPort => _server?.port;

  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    debugPrint('SyncServer listening on 0.0.0.0:$port');
    unawaited(_serve());
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  Future<void> _serve() async {
    final server = _server;
    if (server == null) return;
    await for (final req in server) {
      unawaited(_handle(req));
    }
  }

  Future<T> _serialized<T>(Future<T> Function() fn) {
    final c = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        c.complete(await fn());
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;

      // Публичная страница для QR (системная камера открывает http → сюда → в приложение).
      if (req.method == 'GET' && (path == '/join' || path == '/open-client')) {
        await _serveJoinPage(req);
        return;
      }

      if (!_authOk(req)) {
        await _json(req, 401, {'ok': false, 'error': 'unauthorized'});
        return;
      }

      if (req.method == 'GET' && (path == '/health' || path == '/')) {
        // data_version растёт при любой записи в SQLite (локально или с клиента).
        var rev = DatabaseHelper.dataRevision.value;
        try {
          final rows = await database.rawQuery('PRAGMA data_version');
          if (rows.isNotEmpty) {
            final v = rows.first.values.first;
            if (v is int) {
              rev = v;
            } else if (v is num) {
              rev = v.toInt();
            } else {
              rev = int.tryParse(v?.toString() ?? '') ?? rev;
            }
          }
        } catch (_) {}
        await _json(req, 200, {
          'ok': true,
          'role': 'host',
          'port': port,
          'rev': rev,
        });
        return;
      }

      if (req.method == 'POST' && path == '/db') {
        final body = await utf8.decoder.bind(req).join();
        final map = jsonDecode(body) as Map<String, dynamic>;
        final result = await _serialized(() => _execOp(map));
        await _json(req, 200, {'ok': true, 'result': result});
        return;
      }

      await _json(req, 404, {'ok': false, 'error': 'not found'});
    } catch (e, st) {
      debugPrint('SyncServer error: $e\n$st');
      try {
        await _json(req, 500, {'ok': false, 'error': e.toString()});
      } catch (_) {}
    }
  }

  bool _authOk(HttpRequest req) {
    final h = req.headers.value('x-det-token');
    if (h != null && h == token) return true;
    final q = req.uri.queryParameters['token'];
    return q == token;
  }

  static const _mutatingOps = {
    'execute',
    'rawInsert',
    'rawUpdate',
    'rawDelete',
    'insert',
    'update',
    'delete',
  };

  Future<Object?> _execOp(Map<String, dynamic> map) async {
    final op = map['op']?.toString() ?? '';
    final db = database;
    final Object? result;

    switch (op) {
      case 'execute':
        await db.execute(
          map['sql'] as String,
          _args(map['arguments']),
        );
        result = null;
        break;
      case 'rawQuery':
        final qRows = await db.rawQuery(
          map['sql'] as String,
          _args(map['arguments']),
        );
        result = qRows.map(encodeRow).toList();
        break;
      case 'rawInsert':
        result = await db.rawInsert(
          map['sql'] as String,
          _args(map['arguments']),
        );
        break;
      case 'rawUpdate':
        result = await db.rawUpdate(
          map['sql'] as String,
          _args(map['arguments']),
        );
        break;
      case 'rawDelete':
        result = await db.rawDelete(
          map['sql'] as String,
          _args(map['arguments']),
        );
        break;
      case 'query':
        final rows = await db.query(
          map['table'] as String,
          distinct: map['distinct'] as bool?,
          columns: (map['columns'] as List?)?.cast<String>(),
          where: map['where'] as String?,
          whereArgs: _args(map['whereArgs']),
          groupBy: map['groupBy'] as String?,
          having: map['having'] as String?,
          orderBy: map['orderBy'] as String?,
          limit: (map['limit'] as num?)?.toInt(),
          offset: (map['offset'] as num?)?.toInt(),
        );
        result = rows.map(encodeRow).toList();
        break;
      case 'insert':
        result = await db.insert(
          map['table'] as String,
          Map<String, Object?>.from(map['values'] as Map),
          nullColumnHack: map['nullColumnHack'] as String?,
          conflictAlgorithm: conflictFromName(map['conflictAlgorithm'] as String?),
        );
        break;
      case 'update':
        result = await db.update(
          map['table'] as String,
          Map<String, Object?>.from(map['values'] as Map),
          where: map['where'] as String?,
          whereArgs: _args(map['whereArgs']),
          conflictAlgorithm: conflictFromName(map['conflictAlgorithm'] as String?),
        );
        break;
      case 'delete':
        result = await db.delete(
          map['table'] as String,
          where: map['where'] as String?,
          whereArgs: _args(map['whereArgs']),
        );
        break;
      default:
        throw StateError('Unknown op: $op');
    }

    if (_mutatingOps.contains(op)) {
      // Чтобы UI хоста подтянул заказы/кассу с телефона.
      DatabaseHelper.bumpDataRevision();
    }
    return result;
  }

  List<Object?>? _args(dynamic v) {
    if (v == null) return null;
    return (v as List).cast<Object?>();
  }

  Future<void> _json(HttpRequest req, int code, Map<String, Object?> body) async {
    req.response.statusCode = code;
    req.response.headers.contentType = ContentType.json;
    req.response.headers.add('Access-Control-Allow-Origin', '*');
    req.response.write(jsonEncode(body));
    await req.response.close();
  }

  /// HTML-лендинг: камера сканирует http://host:7878/join?url=… → открыть Det App.
  Future<void> _serveJoinPage(HttpRequest req) async {
    final hostUrl = (req.uri.queryParameters['url'] ?? '').trim();
    final fallback = 'http://${req.headers.host ?? '127.0.0.1'}:$port';
    final target = hostUrl.isNotEmpty ? hostUrl : fallback;
    final deep = Uri(
      scheme: 'detapp',
      host: 'connect',
      queryParameters: {'url': target},
    ).toString();
    final intent =
        'intent://connect?url=${Uri.encodeComponent(target)}#Intent;scheme=detapp;package=com.example.det_app;S.browser_fallback_url=${Uri.encodeComponent(req.uri.toString())};end';
    final escapedTarget = const HtmlEscape().convert(target);
    final html = '''
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Det App — подключение</title>
<style>
  body{margin:0;font-family:system-ui,sans-serif;background:#0f1419;color:#f1f5f9;
       padding:28px 20px;text-align:center}
  h1{font-size:22px;margin:0 0 8px}
  p{color:#94a3b8;line-height:1.45;font-size:14px}
  a.btn{display:block;margin:14px 0;padding:16px;border-radius:12px;text-decoration:none;
        font-weight:700;color:#fff}
  .primary{background:#2563eb}
  .ok{background:#16a34a}
  code{display:block;margin-top:16px;padding:10px;background:#1e293b;border-radius:8px;
       font-size:12px;word-break:break-all;color:#e2e8f0}
</style>
</head>
<body>
  <h1>Det App</h1>
  <p>Открываем приложение и подставляем адрес хоста…</p>
  <a class="btn ok" id="intent" href="$intent">Открыть Det App</a>
  <a class="btn primary" id="deep" href="$deep">Открыть (если кнопка выше не сработала)</a>
  <p>Нет приложения? Установите Det App с обновления по Wi‑Fi, затем нажмите кнопку снова.<br>
  Либо в приложении: Связь → «Сканировать QR хоста».</p>
  <code>$escapedTarget</code>
  <script>
    setTimeout(function(){ location.href = ${jsonEncode(intent)}; }, 200);
    setTimeout(function(){ location.href = ${jsonEncode(deep)}; }, 700);
  </script>
</body>
</html>
''';
    req.response.statusCode = 200;
    req.response.headers.contentType = ContentType.html;
    req.response.headers.add('Access-Control-Allow-Origin', '*');
    req.response.write(html);
    await req.response.close();
  }
}
