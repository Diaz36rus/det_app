import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import 'sync_protocol.dart';

/// Удалённая SQLite через HTTP POST /db на хосте.
class RemoteDatabase implements Database, Transaction {
  RemoteDatabase._({
    required this.baseUrl,
    required this.token,
  });

  final String baseUrl;
  final String token;
  bool _open = true;
  HttpClient? _client;

  static Future<RemoteDatabase> connect({
    required String baseUrl,
    required String token,
  }) async {
    var u = baseUrl.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    final db = RemoteDatabase._(baseUrl: u, token: token);
    // Проверка связи
    await db._getHealth();
    await db.rawQuery('SELECT 1 AS ok');
    return db;
  }

  HttpClient get _http {
    _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 30);
    return _client!;
  }

  Future<void> _getHealth() async {
    final uri = Uri.parse('$baseUrl/health').replace(
      queryParameters: {'token': token},
    );
    final req = await _http.getUrl(uri).timeout(const Duration(seconds: 5));
    req.headers.set('x-det-token', token);
    final res = await req.close().timeout(const Duration(seconds: 5));
    final body = await utf8.decoder.bind(res).join();
    if (res.statusCode != 200) {
      throw StateError('Health failed HTTP ${res.statusCode}: $body');
    }
  }

  Future<Object?> _call(Map<String, Object?> payload) async {
    if (!_open) throw StateError('RemoteDatabase closed');
    final uri = Uri.parse('$baseUrl/db');
    final encoded = utf8.encode(jsonEncode(payload));
    // Фото дефектов (base64) — крупные тела; даём запас по таймауту.
    final sendTimeout = encoded.length > 200000
        ? const Duration(seconds: 90)
        : const Duration(seconds: 20);
    final readTimeout = encoded.length > 200000
        ? const Duration(seconds: 120)
        : const Duration(seconds: 45);
    final req = await _http.postUrl(uri).timeout(sendTimeout);
    req.headers.set('content-type', 'application/json; charset=utf-8');
    req.headers.set('x-det-token', token);
    req.contentLength = encoded.length;
    req.add(encoded);
    final res = await req.close().timeout(readTimeout);
    final body = await utf8.decoder.bind(res).join();
    final map = jsonDecode(body) as Map<String, dynamic>;
    if (res.statusCode != 200 || map['ok'] != true) {
      throw StateError(map['error']?.toString() ?? 'Remote DB error: $body');
    }
    return map['result'];
  }

  List<Map<String, Object?>> _rows(Object? result) {
    if (result == null) return [];
    final list = result as List;
    return list
        .map((e) => Map<String, Object?>.from(e as Map))
        .toList();
  }

  @override
  Database get database => this;

  @override
  String get path => 'remote:$baseUrl';

  @override
  bool get isOpen => _open;

  @override
  Future<void> close() async {
    _open = false;
    _client?.close(force: true);
    _client = null;
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) {
    // На LAN без настоящего BEGIN — DatabaseHelper транзакции не использует.
    return action(this);
  }

  @override
  Future<T> readTransaction<T>(Future<T> Function(Transaction txn) action) {
    return action(this);
  }

  @override
  Future<T> devInvokeMethod<T>(String method, [Object? arguments]) {
    throw UnimplementedError('devInvokeMethod remote');
  }

  @override
  Future<T> devInvokeSqlMethod<T>(String method, String sql, [List<Object?>? arguments]) {
    throw UnimplementedError('devInvokeSqlMethod remote');
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    await _call({
      'op': 'execute',
      'sql': sql,
      'arguments': encodeArgs(arguments),
    });
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    final r = await _call({
      'op': 'rawInsert',
      'sql': sql,
      'arguments': encodeArgs(arguments),
    });
    return (r as num).toInt();
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    final r = await _call({
      'op': 'rawUpdate',
      'sql': sql,
      'arguments': encodeArgs(arguments),
    });
    return (r as num).toInt();
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async {
    final r = await _call({
      'op': 'rawDelete',
      'sql': sql,
      'arguments': encodeArgs(arguments),
    });
    return (r as num).toInt();
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    final r = await _call({
      'op': 'rawQuery',
      'sql': sql,
      'arguments': encodeArgs(arguments),
    });
    return _rows(r);
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final r = await _call({
      'op': 'insert',
      'table': table,
      'values': encodeRow(values),
      'nullColumnHack': nullColumnHack,
      'conflictAlgorithm': conflictToName(conflictAlgorithm),
    });
    return (r as num).toInt();
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final r = await _call({
      'op': 'update',
      'table': table,
      'values': encodeRow(values),
      'where': where,
      'whereArgs': encodeArgs(whereArgs),
      'conflictAlgorithm': conflictToName(conflictAlgorithm),
    });
    return (r as num).toInt();
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    final r = await _call({
      'op': 'delete',
      'table': table,
      'where': where,
      'whereArgs': encodeArgs(whereArgs),
    });
    return (r as num).toInt();
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final r = await _call({
      'op': 'query',
      'table': table,
      'distinct': distinct,
      'columns': columns,
      'where': where,
      'whereArgs': encodeArgs(whereArgs),
      'groupBy': groupBy,
      'having': having,
      'orderBy': orderBy,
      'limit': limit,
      'offset': offset,
    });
    return _rows(r);
  }

  @override
  Future<QueryCursor> rawQueryCursor(String sql, List<Object?>? arguments, {int? bufferSize}) {
    throw UnimplementedError('rawQueryCursor not supported over LAN sync');
  }

  @override
  Future<QueryCursor> queryCursor(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
    int? bufferSize,
  }) {
    throw UnimplementedError('queryCursor not supported over LAN sync');
  }

  @override
  Batch batch() => _RemoteBatch();
}

class _RemoteBatch implements Batch {
  _RemoteBatch();
  int _len = 0;

  @override
  int get length => _len;

  @override
  Future<List<Object?>> apply({bool? noResult, bool? continueOnError}) {
    throw UnimplementedError('Batch not supported over LAN sync');
  }

  @override
  Future<List<Object?>> commit({bool? exclusive, bool? noResult, bool? continueOnError}) {
    throw UnimplementedError('Batch not supported over LAN sync');
  }

  @override
  void delete(String table, {String? where, List<Object?>? whereArgs}) => _len++;

  @override
  void execute(String sql, [List<Object?>? arguments]) => _len++;

  @override
  void insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) =>
      _len++;

  @override
  void query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) =>
      _len++;

  @override
  void rawDelete(String sql, [List<Object?>? arguments]) => _len++;

  @override
  void rawInsert(String sql, [List<Object?>? arguments]) => _len++;

  @override
  void rawQuery(String sql, [List<Object?>? arguments]) => _len++;

  @override
  void rawUpdate(String sql, [List<Object?>? arguments]) => _len++;

  @override
  void update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) =>
      _len++;
}
