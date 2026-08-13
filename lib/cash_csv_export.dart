import 'dart:io';

import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Выгрузка журнала кассы в CSV (Excel / 1С).
class CashCsvExport {
  CashCsvExport._();

  static String _esc(Object? v) {
    var s = (v ?? '').toString().replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
    // Разделитель ; — привычно для русской локали Excel.
    if (s.contains(';') || s.contains('"')) {
      s = '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String build(List<Map<String, dynamic>> journal) {
    final buf = StringBuffer('\uFEFF'); // UTF-8 BOM для Excel
    buf.writeln('Дата;Тип;Категория;Способ;Сумма;Описание;Заказ;Смена');
    for (final r in journal) {
      final amount = (r['amount'] as num?)?.toDouble() ?? 0;
      final amountStr = amount == amount.roundToDouble()
          ? amount.toInt().toString()
          : amount.toStringAsFixed(2).replaceAll('.', ',');
      buf.writeln([
        _esc(r['created_at']),
        _esc(r['type']),
        _esc(r['category']),
        _esc(r['method']),
        _esc(amountStr),
        _esc(r['title']),
        _esc(r['order_id'] ?? ''),
        _esc(r['shift_id'] ?? ''),
      ].join(';'));
    }
    return buf.toString();
  }

  /// Пишет файл в Documents/det_app_exports и открывает его.
  /// Возвращает путь или `null` при ошибке.
  static Future<String?> writeAndOpen({
    required List<Map<String, dynamic>> journal,
    required String startDate,
    required String endDate,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'det_app_exports'));
    if (!await dir.exists()) await dir.create(recursive: true);

    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final range = startDate == endDate ? startDate : '${startDate}_$endDate';
    final path = p.join(dir.path, 'kassa_${range}_$stamp.csv');
    final file = File(path);
    await file.writeAsString(build(journal), flush: true);
    await OpenFilex.open(path);
    return path;
  }
}
