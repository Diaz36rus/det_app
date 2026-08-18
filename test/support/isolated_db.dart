import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:det_app/database.dart';

/// Изолирует detailing.db / sync config во временную папку (не трогает боевые Documents).
class FakePathProvider extends PathProviderPlatform {
  FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

Directory? _testDocs;

Future<void> bindIsolatedTestDb() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  _testDocs = await Directory.systemTemp.createTemp('det_app_regression_');
  PathProviderPlatform.instance = FakePathProvider(_testDocs!.path);
}

Future<void> resetIsolatedDb() async {
  await DatabaseHelper().resetDatabase();
}

Future<void> disposeIsolatedTestDb() async {
  try {
    final helper = DatabaseHelper();
    // закрыть через reset (локальный режим во временной папке)
    await helper.resetDatabase();
  } catch (_) {}
  final dir = _testDocs;
  _testDocs = null;
  if (dir != null && await dir.exists()) {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}

Future<Map<String, dynamic>> invById(int id) async {
  final rows = await DatabaseHelper().getInventory();
  return rows.firstWhere((r) => (r['id'] as num).toInt() == id);
}

Future<double> invQty(int id) async {
  final row = await invById(id);
  return (row['quantity'] as num?)?.toDouble() ?? 0;
}
