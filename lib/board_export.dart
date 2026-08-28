import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Экспорт видимых заказов доски в CSV (UTF-8 BOM) — ровные колонки для Excel.
class BoardExport {
  BoardExport._();

  static final _money = NumberFormat('#,##0.##', 'ru_RU');

  static Future<File> writeCsv(List<Map<String, dynamic>> orders) async {
    final headers = [
      'ID',
      'Статус',
      'Клиент',
      'Телефон',
      'Авто',
      'Госномер',
      'Мастер',
      'Начало',
      'Цена',
      'Оплачено',
      'Долг',
      'Заметки',
    ];

    String esc(String? v) {
      final s = (v ?? '').replaceAll('"', '""');
      return '"$s"';
    }

    String money(dynamic v) {
      final n = (v as num?)?.toDouble() ?? 0;
      return _money.format(n);
    }

    final buf = StringBuffer();
    // BOM для Excel
    buf.write('\uFEFF');
    buf.writeln(headers.join(';'));

    for (final o in orders) {
      final price = (o['price'] as num?)?.toDouble() ?? 0;
      final paid = (o['paid_amount'] as num?)?.toDouble() ?? 0;
      final debt = price - paid;
      final row = [
        esc(o['id']?.toString()),
        esc(o['status']?.toString()),
        esc(o['client_name']?.toString()),
        esc(o['client_phone']?.toString()),
        esc(o['make_model']?.toString()),
        esc(o['plate']?.toString()),
        esc(o['master_name']?.toString()),
        esc(o['start_time']?.toString() ?? o['due_date']?.toString()),
        esc(money(price)),
        esc(money(paid)),
        esc(money(debt > 0 ? debt : 0)),
        esc(o['notes']?.toString()),
      ];
      buf.writeln(row.join(';'));
    }

    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File(p.join(dir.path, 'detapp_board_$stamp.csv'));
    await file.writeAsString(buf.toString(), flush: true);
    return file;
  }
}
