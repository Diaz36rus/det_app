import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'app_theme.dart';

/// PDF заказ-наряда по структуре шаблона «заказ-наряд.docx».
class WorkOrderPdf {
  static const int maxRowsFirstPage = 12;

  /// Пакет оклейки → одна строка (шапка); дети (`parent_id`) не печатаются.
  /// Колонка «Комментарии» всегда пустая — заполняется от руки.
  static List<Map<String, dynamic>> _itemsForPrint(List<Map<String, dynamic>> items) {
    return items.where((w) => w['parent_id'] == null).toList();
  }

  /// Сначала превью; печать — кнопкой в панели PdfPreview.
  static Future<void> showPreview(
    BuildContext context, {
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> masters,
  }) async {
    final orderId = order['id'];
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: AppColors.surface,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: 1100,
            height: 780,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Text(
                        "Превью заказ-наряда #$orderId",
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.text,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: "Закрыть",
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                Expanded(
                  child: FutureBuilder<Uint8List>(
                    future: build(
                      order: order,
                      items: items,
                      masters: masters,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              "Ошибка PDF: ${snapshot.error}",
                              style: GoogleFonts.manrope(color: AppColors.danger),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(color: AppColors.primary),
                        );
                      }
                      final bytes = snapshot.data!;
                      return PdfPreview(
                        build: (_) async => bytes,
                        pdfFileName: 'заказ-наряд-$orderId.pdf',
                        initialPageFormat: PdfPageFormat.a4.landscape,
                        canChangePageFormat: false,
                        canChangeOrientation: false,
                        canDebug: false,
                        allowPrinting: true,
                        allowSharing: true,
                        previewPageMargin: const EdgeInsets.all(12),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<Uint8List> build({
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> masters,
  }) async {
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    final base = pw.ThemeData.withFont(base: font, bold: fontBold);

    final doc = pw.Document(theme: base);
    final printItems = _itemsForPrint(items);
    final pages = <List<Map<String, dynamic>>>[];
    if (printItems.isEmpty) {
      pages.add([]);
    } else {
      for (var i = 0; i < printItems.length; i += maxRowsFirstPage) {
        final end = (i + maxRowsFirstPage).clamp(0, printItems.length);
        pages.add(printItems.sublist(i, end));
      }
    }

    for (var p = 0; p < pages.length; p++) {
      final isFirst = p == 0;
      final isLast = p == pages.length - 1;
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(20, 16, 20, 16),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                if (isFirst) ...[
                  _title(order),
                  pw.SizedBox(height: 6),
                  _headerTable(order),
                  pw.SizedBox(height: 6),
                  _clientTable(order),
                  pw.SizedBox(height: 6),
                ] else
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Text(
                      'Заказ #${order['id']} · продолжение работ',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                pw.Expanded(
                  child: _worksTable(
                    pages[p],
                    masters,
                    startIndex: p * maxRowsFirstPage,
                  ),
                ),
                if (isLast) ...[
                  pw.SizedBox(height: 6),
                  _totals(order),
                ],
              ],
            );
          },
        ),
      );
    }

    return doc.save();
  }

  static pw.Widget _title(Map<String, dynamic> order) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'ЗАКАЗ-НАРЯД № ${order['id']}',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()),
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      ],
    );
  }

  static String _datePart(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString().trim();
    if (s.isEmpty) return '';
    try {
      final n = s.replaceFirst('T', ' ').split('.').first.trim();
      final dt = DateTime.parse(n.contains(' ') ? n.replaceFirst(' ', 'T') : n);
      return DateFormat('dd.MM.yyyy').format(dt);
    } catch (_) {
      if (s.length >= 10 && s.contains('-')) {
        final p = s.substring(0, 10).split('-');
        if (p.length == 3) return '${p[2]}.${p[1]}.${p[0]}';
      }
      return s;
    }
  }

  static String _timePart(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString().trim();
    if (s.isEmpty) return '';
    try {
      final n = s.replaceFirst('T', ' ').split('.').first.trim();
      final dt = DateTime.parse(n.contains(' ') ? n.replaceFirst(' ', 'T') : n);
      return DateFormat('HH:mm').format(dt);
    } catch (_) {
      final m = RegExp(r'(\d{1,2}:\d{2})').firstMatch(s);
      return m?.group(1) ?? '';
    }
  }

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    bool label = false,
    pw.Alignment align = pw.Alignment.centerLeft,
    double? height,
  }) {
    return pw.Container(
      height: height,
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: label ? 8 : 9,
          fontWeight: bold || label ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: label ? PdfColors.grey700 : PdfColors.black,
        ),
      ),
    );
  }

  static pw.TableBorder get _border => pw.TableBorder.all(color: PdfColors.grey700, width: 0.6);

  static pw.Widget _headerTable(Map<String, dynamic> order) {
    final admin = order['master_name']?.toString() ?? '';
    final receptionDate = _datePart(order['start_time'] ?? order['created_at']);
    final planDate = _datePart(order['end_date'] ?? order['due_date'] ?? order['end_time']);
    final receptionTime = _timePart(order['start_time']);
    final planTime = _timePart(order['end_time']);

    return pw.Table(
      border: _border,
      columnWidths: {
        0: const pw.FlexColumnWidth(1.1),
        1: const pw.FlexColumnWidth(1.6),
        2: const pw.FlexColumnWidth(1.1),
        3: const pw.FlexColumnWidth(1.2),
        4: const pw.FlexColumnWidth(1.1),
        5: const pw.FlexColumnWidth(1.2),
        6: const pw.FlexColumnWidth(0.8),
        7: const pw.FlexColumnWidth(1.0),
      },
      children: [
        pw.TableRow(children: [
          _cell('Администратор', label: true),
          _cell(admin),
          _cell('Число приёма', label: true),
          _cell(receptionDate),
          _cell('Число план', label: true),
          _cell(planDate),
          _cell('факт', label: true),
          _cell(''),
        ]),
        pw.TableRow(children: [
          _cell('Мастер-приёмщик', label: true),
          _cell(admin),
          _cell('Время приёма', label: true),
          _cell(receptionTime),
          _cell('Время план', label: true),
          _cell(planTime),
          _cell('факт', label: true),
          _cell(''),
        ]),
      ],
    );
  }

  static pw.Widget _clientTable(Map<String, dynamic> order) {
    return pw.Table(
      border: _border,
      columnWidths: {
        0: const pw.FlexColumnWidth(2.2),
        1: const pw.FlexColumnWidth(1.2),
        2: const pw.FlexColumnWidth(1.8),
        3: const pw.FlexColumnWidth(1.8),
        4: const pw.FlexColumnWidth(1.4),
      },
      children: [
        pw.TableRow(children: [
          _cell('Марка, модель автомобиля', label: true),
          _cell('Гос. номер', label: true),
          _cell('VIN автомобиля', label: true),
          _cell('ФИО клиента', label: true),
          _cell('Номер телефона', label: true),
        ]),
        pw.TableRow(children: [
          _cell(order['make_model']?.toString() ?? ''),
          _cell(order['plate']?.toString() ?? '', bold: true),
          _cell(order['vin']?.toString() ?? ''),
          _cell(order['client_name']?.toString() ?? '', bold: true),
          _cell(order['client_phone']?.toString() ?? ''),
        ]),
      ],
    );
  }

  static String _masterNames(List<Map<String, dynamic>> masters, dynamic rawIds) {
    if (rawIds == null) return '';
    final s = rawIds.toString().trim();
    if (s.isEmpty) return '';
    final ids = s
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList();
    return ids.map((id) {
      final found = masters.where((m) => (m['id'] as num).toInt() == id).toList();
      return found.isNotEmpty ? found.first['name']?.toString() ?? '' : '';
    }).where((n) => n.isNotEmpty).join(', ');
  }

  static String _executor(Map<String, dynamic> item, List<Map<String, dynamic>> masters) {
    final ws = (item['workshop'] as String?)?.trim() ?? '';
    final names = _masterNames(masters, item['master_ids']);
    if (ws.isEmpty) return names;
    if (names.isEmpty) return ws;
    return '$ws · $names';
  }

  static String _money(dynamic v) {
    final n = (v as num?)?.toDouble() ?? 0;
    if (n == n.roundToDouble()) return n.toStringAsFixed(0);
    return n.toStringAsFixed(2);
  }

  static pw.Widget _worksTable(
    List<Map<String, dynamic>> pageItems,
    List<Map<String, dynamic>> masters, {
    required int startIndex,
  }) {
    // Работы/Исполнитель −30%, Сумма −50%, Выполнено −15%; всё в Комментарии.
    // Было flex: 2.6 / 2.2 / 1.4 → стало 1.82 / 1.54 / 2.84
    const columnWidths = {
      0: pw.FixedColumnWidth(28),
      1: pw.FlexColumnWidth(1.82),
      2: pw.FlexColumnWidth(1.54),
      3: pw.FixedColumnWidth(40),
      4: pw.FixedColumnWidth(62), // 6 цифр + « ₽»
      5: pw.FlexColumnWidth(2.84),
      6: pw.FixedColumnWidth(58),
    };

    return pw.LayoutBuilder(
      builder: (context, constraints) {
        const headerH = 22.0;
        final bodyH = (constraints?.maxHeight ?? 360) - headerH;
        // Растягиваем строки на всю оставшуюся высоту страницы.
        final rowH = bodyH > 0 ? bodyH / maxRowsFirstPage : 24.0;

        final rows = <pw.TableRow>[
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
            children: [
              _cell('№', label: true, align: pw.Alignment.center, height: headerH),
              _cell('Работы', label: true, height: headerH),
              _cell('Исполнитель / Цех / Мастер', label: true, height: headerH),
              _cell('ЗП', label: true, align: pw.Alignment.center, height: headerH),
              _cell('Сумма', label: true, align: pw.Alignment.centerRight, height: headerH),
              _cell('Комментарии', label: true, height: headerH),
              _cell('Выполнено', label: true, align: pw.Alignment.center, height: headerH),
            ],
          ),
        ];

        final count = pageItems.length > maxRowsFirstPage ? maxRowsFirstPage : pageItems.length;

        for (var i = 0; i < maxRowsFirstPage; i++) {
          if (i < count) {
            final w = pageItems[i];
            rows.add(
              pw.TableRow(children: [
                _cell('${startIndex + i + 1}', align: pw.Alignment.center, height: rowH),
                _cell(w['name']?.toString() ?? '', height: rowH),
                _cell(_executor(w, masters), height: rowH),
                _cell('', height: rowH),
                _cell('${_money(w['price'])} ₽', align: pw.Alignment.centerRight, height: rowH),
                _cell(w['comment']?.toString() ?? '', height: rowH),
                _cell('', height: rowH),
              ]),
            );
          } else {
            rows.add(
              pw.TableRow(children: [
                _cell('${startIndex + i + 1}', align: pw.Alignment.center, height: rowH),
                _cell('', height: rowH),
                _cell('', height: rowH),
                _cell('', height: rowH),
                _cell('', height: rowH),
                _cell('', height: rowH),
                _cell('', height: rowH),
              ]),
            );
          }
        }

        return pw.Table(
          border: _border,
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          columnWidths: columnWidths,
          children: rows,
        );
      },
    );
  }

  static pw.Widget _totals(Map<String, dynamic> order) {
    final price = (order['price'] as num?)?.toDouble() ?? 0;
    final paid = (order['paid_amount'] as num?)?.toDouble() ?? 0;
    final debt = price - paid;
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Итого: ${_money(price)} ₽', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Text('Оплачено: ${_money(paid)} ₽', style: const pw.TextStyle(fontSize: 10)),
            pw.Text(
              'Долг: ${_money(debt > 0 ? debt : 0)} ₽',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }
}
