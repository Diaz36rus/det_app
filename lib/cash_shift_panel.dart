import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_datetime.dart';
import 'app_theme.dart';
import 'cash_catalog.dart';
import 'cash_operation_dialog.dart';
import 'database.dart';

/// Панель смены: несколько касс, открытие/закрытие, добавление кассы.
class CashShiftPanel extends StatelessWidget {
  final Map<String, dynamic>? shift;
  final List<Map<String, dynamic>> registerSnapshots;
  final int? selectedRegisterId;
  final ValueChanged<int?>? onSelectRegister;
  /// Клик по карточке кассы — открыть список транзакций.
  final ValueChanged<Map<String, dynamic>>? onOpenRegister;
  final VoidCallback onChanged;

  const CashShiftPanel({
    super.key,
    required this.shift,
    required this.registerSnapshots,
    required this.onChanged,
    this.selectedRegisterId,
    this.onSelectRegister,
    this.onOpenRegister,
  });

  static final _money = NumberFormat('#,##0.##', 'ru_RU');

  Color _typeColor(String type) {
    switch (type) {
      case CashMethods.cash:
        return AppColors.success;
      case CashMethods.card:
        return AppColors.primary;
      case CashMethods.transfer:
        return const Color(0xFF38BDF8);
      case CashMethods.invoice:
        return const Color(0xFFA78BFA);
      default:
        return AppColors.textMuted;
    }
  }

  Future<void> _addRegister(BuildContext context) async {
    final nameCtrl = TextEditingController();
    var moneyType = CashMethods.cash;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Новая касса', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Название', hintText: 'Например: Касса 2', isDense: true),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: moneyType,
                decoration: const InputDecoration(labelText: 'Вид денег', isDense: true),
                dropdownColor: AppColors.surface2,
                items: CashMethods.all
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setLocal(() => moneyType = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await DatabaseHelper().addCashRegister(nameCtrl.text.trim(), moneyType);
    onChanged();
  }

  Future<void> _openShift(BuildContext context) async {
    final registers = await DatabaseHelper().getCashRegisters();
    if (!context.mounted) return;
    if (registers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала добавьте хотя бы одну кассу')),
      );
      return;
    }
    final ctrls = <int, TextEditingController>{};
    for (final r in registers) {
      final rid = (r['id'] as num).toInt();
      final isCash = r['money_type']?.toString() == CashMethods.cash;
      ctrls[rid] = TextEditingController(text: isCash ? '0' : '0');
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Открыть смену', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Укажите стартовый остаток по каждой кассе',
                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
                ),
                const SizedBox(height: 12),
                for (final r in registers) ...[
                  TextField(
                    controller: ctrls[(r['id'] as num).toInt()],
                    decoration: InputDecoration(
                      labelText: '${r['name']} · ${r['money_type']}',
                      isDense: true,
                      suffixText: '₽',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Открыть')),
        ],
      ),
    );
    if (ok != true) return;
    final openings = <int, double>{};
    for (final e in ctrls.entries) {
      openings[e.key] = double.tryParse(e.value.text.replaceAll(',', '.')) ?? 0;
    }
    var cashOpening = 0.0;
    for (final r in registers) {
      if (r['money_type']?.toString() != CashMethods.cash) continue;
      cashOpening += openings[(r['id'] as num).toInt()] ?? 0;
    }
    await DatabaseHelper().openCashShift(cashOpening, openings: openings);
    for (final c in ctrls.values) {
      c.dispose();
    }
    onChanged();
  }

  Future<void> _closeShift(BuildContext context) async {
    if (shift == null) return;
    final shiftId = (shift!['id'] as num).toInt();
    final snaps = registerSnapshots.isNotEmpty
        ? registerSnapshots
        : await DatabaseHelper().getShiftRegisterSnapshots(shiftId);
    if (!context.mounted) return;

    final ctrls = <int, TextEditingController>{};
    for (final s in snaps) {
      final rid = (s['id'] as num).toInt();
      final expected = (s['expected'] as num?)?.toDouble() ?? 0;
      ctrls[rid] = TextEditingController(
        text: expected == expected.roundToDouble() ? expected.toInt().toString() : expected.toStringAsFixed(2),
      );
    }
    final noteCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Закрыть смену', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in snaps) ...[
                  Text(
                    '${s['name']} · ожид. ${_money.format((s['expected'] as num?)?.toDouble() ?? 0)} ₽',
                    style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: ctrls[(s['id'] as num).toInt()],
                    decoration: InputDecoration(
                      labelText: 'Факт · ${s['money_type']}',
                      isDense: true,
                      suffixText: '₽',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Комментарий', isDense: true),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger.withOpacity(0.9)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Закрыть смену'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final facts = <int, double>{};
    for (final e in ctrls.entries) {
      facts[e.key] = double.tryParse(e.value.text.replaceAll(',', '.')) ?? 0;
    }
    var cashFact = 0.0;
    for (final s in snaps) {
      if (s['money_type']?.toString() == CashMethods.cash) {
        cashFact += facts[(s['id'] as num).toInt()] ?? 0;
      }
    }
    await DatabaseHelper().closeCashShift(
      shiftId,
      cashFact,
      note: noteCtrl.text.trim(),
      facts: facts,
    );
    for (final c in ctrls.values) {
      c.dispose();
    }
    noteCtrl.dispose();
    onChanged();
  }

  Future<void> _collection(BuildContext context) async {
    final t = cashTemplateByKey('collect');
    final saved = await CashOperationDialog.open(
      context,
      template: t,
      registerId: selectedRegisterId,
    );
    if (saved == true) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final open = shift != null;
    final openedAt = AppDateTime.format(shift?['opened_at']);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: open ? AppColors.success.withOpacity(0.45) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Смена', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (open ? AppColors.success : AppColors.danger).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (open ? AppColors.success : AppColors.danger).withOpacity(0.45),
                  ),
                ),
                child: Text(
                  open
                      ? (openedAt.isEmpty ? 'открыта' : 'открыта · $openedAt')
                      : 'закрыта',
                  style: GoogleFonts.manrope(
                    color: open ? AppColors.success : AppColors.danger,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _addRegister(context),
                icon: const Icon(Icons.add, size: 16),
                label: Text('Касса', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
              if (open) ...[
                const SizedBox(width: 4),
                OutlinedButton(
                  onPressed: () => _collection(context),
                  child: Text('Инкассация', style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 12)),
                ),
                const SizedBox(width: 6),
                ElevatedButton(
                  onPressed: () => _closeShift(context),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger.withOpacity(0.9)),
                  child: Text('Закрыть', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ] else
                ElevatedButton(
                  onPressed: () => _openShift(context),
                  child: Text('Открыть смену', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (registerSnapshots.isEmpty)
            Text(
              'Касс пока нет — нажмите «+ Касса»',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final cardW = w < 700 ? (w - 8) / 2 : (w - 24) / 4;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in registerSnapshots)
                      SizedBox(
                        width: cardW.clamp(140.0, 280.0),
                        child: _registerCard(s, open),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _registerCard(Map<String, dynamic> s, bool shiftOpen) {
    final rid = (s['id'] as num).toInt();
    final type = s['money_type']?.toString() ?? '';
    final color = _typeColor(type);
    final selected = selectedRegisterId == rid;
    final opening = (s['opening'] as num?)?.toDouble() ?? 0;
    final expected = (s['expected'] as num?)?.toDouble() ?? opening;
    final delta = expected - opening;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (onOpenRegister != null) {
            onOpenRegister!(s);
          } else if (onSelectRegister != null) {
            onSelectRegister!(rid);
          }
        },
        onLongPress: onSelectRegister == null ? null : () => onSelectRegister!(rid),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.surface.withOpacity(0.75),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : color.withOpacity(0.4),
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      s['name']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: AppColors.textDim.withOpacity(0.8)),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                type,
                style: GoogleFonts.manrope(color: color, fontSize: 11, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                '${_money.format(shiftOpen ? expected : opening)} ₽',
                style: GoogleFonts.manrope(
                  color: AppColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (shiftOpen)
                Text(
                  delta >= 0 ? 'Δ смены +${_money.format(delta)}' : 'Δ смены ${_money.format(delta)}',
                  style: GoogleFonts.manrope(
                    color: delta >= 0 ? AppColors.success : AppColors.danger,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                Text(
                  'вне смены',
                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11),
                ),
              const SizedBox(height: 4),
              Text(
                'нажмите — транзакции',
                style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
