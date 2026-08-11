import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'app_datetime.dart';
import 'app_theme.dart';
import 'database.dart';

/// Z-отчёт закрытой смены: кассы, расхождения, журнал.
class ShiftZReportPdf {
  ShiftZReportPdf._();

  static final _money = NumberFormat('#,##0.##', 'ru_RU');

  static Future<void> showPreview(
    BuildContext context, {
    required int shiftId,
  }) async {
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: AppColors.surface,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: 900,
            height: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Text(
                        'Z-отчёт смены #$shiftId',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.text,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                Expanded(
                  child: FutureBuilder<Uint8List>(
                    future: build(shiftId: shiftId),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Ошибка PDF: ${snapshot.error}',
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
                        pdfFileName: 'z-otchet-smena-$shiftId.pdf',
                        initialPageFormat: PdfPageFormat.a4,
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

  static Future<Uint8List> build({required int shiftId}) async {
    final db = DatabaseHelper();
    final shift = await db.getCashShiftById(shiftId);
    if (shift == null) throw StateError('Смена #$shiftId не найдена');
    final snaps = await db.getShiftRegisterSnapshots(shiftId);
    final journal = await db.getCashJournalForShift(shiftId);

    final opened = AppDateTime.format(shift['opened_at']);
    final closed = AppDateTime.format(shift['closed_at']);
    final note = shift['note']?.toString() ?? '';
    final totalDiff = (shift['difference'] as num?)?.toDouble() ?? 0;

    double income = 0;
    double expense = 0;
    final byMethod = <String, double>{};
    for (final j in journal) {
      final amount = (j['amount'] as num?)?.toDouble() ?? 0;
      final type = j['type']?.toString() ?? '';
      final method = (j['method']?.toString().isNotEmpty == true)
          ? j['method'].toString()
          : '—';
      if (type == 'Расход') {
        expense += amount;
      } else {
        income += amount;
        byMethod[method] = (byMethod[method] ?? 0) + amount;
      }
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Text(
            'Z-отчёт смены #$shiftId',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Открыта: $opened'),
          pw.Text('Закрыта: ${closed.isEmpty ? '—' : closed}'),
          if (note.isNotEmpty) pw.Text('Комментарий: $note'),
          pw.SizedBox(height: 14),
          pw.Text('Кассы', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: const ['Касса', 'Тип', 'Старт', 'Ожид.', 'Факт', 'Δ'],
            data: [
              for (final s in snaps)
                [
                  s['name']?.toString() ?? '',
                  s['money_type']?.toString() ?? '',
                  _money.format((s['opening'] as num?)?.toDouble() ?? 0),
                  _money.format((s['expected'] as num?)?.toDouble() ?? 0),
                  _money.format(
                    (s['fact'] as num?)?.toDouble() ??
                        (s['expected'] as num?)?.toDouble() ??
                        0,
                  ),
                  _money.format(
                    (s['difference'] as num?)?.toDouble() ??
                        (((s['fact'] as num?)?.toDouble() ??
                                (s['expected'] as num?)?.toDouble() ??
                                0) -
                            ((s['expected'] as num?)?.toDouble() ?? 0)),
                  ),
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Итого расхождение смены: ${_money.format(totalDiff)} ₽',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 14),
          pw.Text('Обороты', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Приход: ${_money.format(income)} ₽'),
          pw.Text('Расход: ${_money.format(expense)} ₽'),
          if (byMethod.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('Приход по способам:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            for (final e in byMethod.entries)
              pw.Text('  ${e.key}: ${_money.format(e.value)} ₽'),
          ],
          if (journal.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text(
              'Журнал смены (${journal.length})',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: const ['Время', 'Тип', 'Сумма', 'Описание'],
              data: [
                for (final j in journal.take(40))
                  [
                    AppDateTime.format(j['created_at']),
                    j['type']?.toString() ?? '',
                    _money.format((j['amount'] as num?)?.toDouble() ?? 0),
                    (j['title']?.toString() ?? '').length > 48
                        ? '${(j['title']?.toString() ?? '').substring(0, 48)}…'
                        : (j['title']?.toString() ?? ''),
                  ],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            ),
            if (journal.length > 40)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text('… и ещё ${journal.length - 40} операций'),
              ),
          ],
        ],
      ),
    );
    return doc.save();
  }
}
