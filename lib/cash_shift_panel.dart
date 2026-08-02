import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'cash_catalog.dart';
import 'cash_operation_dialog.dart';
import 'database.dart';

/// Панель кассовой смены: открытие, ожидаемый нал, закрытие, инкассация.
class CashShiftPanel extends StatelessWidget {
  final Map<String, dynamic>? shift;
  final double? expectedCash;
  final VoidCallback onChanged;

  const CashShiftPanel({
    super.key,
    required this.shift,
    required this.expectedCash,
    required this.onChanged,
  });

  static final _money = NumberFormat('#,##0.##', 'ru_RU');

  Future<void> _openShift(BuildContext context) async {
    final ctrl = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Открыть смену', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Остаток наличных в ящике, ₽', isDense: true),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Открыть'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final amount = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
    await DatabaseHelper().openCashShift(amount);
    onChanged();
  }

  Future<void> _closeShift(BuildContext context) async {
    if (shift == null) return;
    final shiftId = (shift!['id'] as num).toInt();
    final expected = expectedCash ?? await DatabaseHelper().getShiftExpectedCash(shiftId);
    if (!context.mounted) return;
    final factCtrl = TextEditingController(text: expected.toStringAsFixed(0));
    final noteCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Закрыть смену', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ожидается в ящике: ${_money.format(expected)} ₽',
              style: GoogleFonts.manrope(color: AppColors.textMuted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: factCtrl,
              decoration: const InputDecoration(labelText: 'Фактически наличных, ₽', isDense: true),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'Комментарий', isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Закрыть смену'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final fact = double.tryParse(factCtrl.text.replaceAll(',', '.')) ?? expected;
    await DatabaseHelper().closeCashShift(shiftId, fact, note: noteCtrl.text.trim());
    onChanged();
  }

  Future<void> _collection(BuildContext context) async {
    final t = cashTemplateByKey('collect');
    final saved = await CashOperationDialog.open(context, template: t);
    if (saved == true) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final open = shift != null;
    final opening = (shift?['opening_cash'] as num?)?.toDouble() ?? 0;

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: open ? AppColors.success.withOpacity(0.45) : AppColors.border),
      ),
      child: open
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Смена', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 13)),
                    const SizedBox(width: 6),
                    Text(
                      'открыта',
                      style: GoogleFonts.manrope(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(
                      expectedCash != null ? '${_money.format(expectedCash)} ₽' : '${_money.format(opening)} ₽',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 30,
                        child: OutlinedButton(
                          onPressed: () => _collection(context),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text('Инкассация', style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 11)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SizedBox(
                        height: 30,
                        child: ElevatedButton(
                          onPressed: () => _closeShift(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.danger.withOpacity(0.85),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text('Закрыть', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 11)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Смена', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 13)),
                    const Spacer(),
                    Text(
                      'закрыта',
                      style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  height: 32,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _openShift(context),
                    style: ElevatedButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text('Открыть смену', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ),
              ],
            ),
    );
  }
}
