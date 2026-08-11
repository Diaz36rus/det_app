import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_datetime.dart';
import 'app_theme.dart';
import 'cash_operation_dialog.dart';
import 'database.dart';
import 'order_details_dialog.dart';
import 'payment_edit_dialog.dart';
import 'responsive.dart';

/// Список транзакций одной кассы за период (модалка).
class CashRegisterTxDialog extends StatefulWidget {
  final int registerId;
  final String registerName;
  final String moneyType;
  final double expected;
  final String startDate;
  final String endDate;

  const CashRegisterTxDialog({
    super.key,
    required this.registerId,
    required this.registerName,
    required this.moneyType,
    required this.expected,
    required this.startDate,
    required this.endDate,
  });

  static Future<bool?> open(
    BuildContext context, {
    required int registerId,
    required String registerName,
    required String moneyType,
    required double expected,
    required String startDate,
    required String endDate,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => CashRegisterTxDialog(
        registerId: registerId,
        registerName: registerName,
        moneyType: moneyType,
        expected: expected,
        startDate: startDate,
        endDate: endDate,
      ),
    );
  }

  @override
  State<CashRegisterTxDialog> createState() => _CashRegisterTxDialogState();
}

class _CashRegisterTxDialogState extends State<CashRegisterTxDialog> {
  final _money = NumberFormat('#,##0.##', 'ru_RU');
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _matchesRegister(Map<String, dynamic> row) {
    final rid = row['register_id'];
    if (rid != null) return (rid as num).toInt() == widget.registerId;
    return (row['method']?.toString() ?? '') == widget.moneyType;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final journal = await DatabaseHelper().getCashJournal(widget.startDate, widget.endDate);
    if (!mounted) return;
    setState(() {
      _rows = journal.where(_matchesRegister).toList();
      _loading = false;
    });
  }

  Future<void> _editRow(Map<String, dynamic> row) async {
    final source = row['source']?.toString() ?? '';
    final id = (row['id'] as num?)?.toInt();
    if (id == null) return;

    if (source == 'flow') {
      final ok = await CashOperationDialog.open(context, editFlowId: id);
      if (ok == true) {
        _changed = true;
        await _load();
      }
      return;
    }

    if (source == 'payment') {
      final result = await PaymentEditDialog.open(
        context,
        paymentId: id,
        amount: (row['amount'] as num?)?.toDouble() ?? 0,
        method: row['method']?.toString() ?? '',
        registerId: (row['register_id'] as num?)?.toInt(),
        orderId: (row['order_id'] as num?)?.toInt(),
        title: row['title']?.toString() ?? 'Оплата',
      );
      if (result == 'saved' || result == 'voided') {
        _changed = true;
        await _load();
      } else if (result == 'order') {
        final oid = (row['order_id'] as num?)?.toInt();
        if (oid != null) {
          final order = await DatabaseHelper().getOrderById(oid);
          if (order != null && mounted) {
            final refreshed = await OrderDetailsDialog.open(context, order);
            if (refreshed == true) {
              _changed = true;
              await _load();
            }
          }
        }
      }
    }
  }

  Future<void> _deleteRow(Map<String, dynamic> row) async {
    final source = row['source']?.toString() ?? '';
    final id = (row['id'] as num?)?.toInt();
    if (id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          source == 'payment' ? 'Отменить оплату?' : 'Удалить операцию?',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        ),
        content: Text(
          source == 'payment'
              ? 'Платёж будет удалён, сумма в заказе пересчитается.'
              : 'Операция будет удалена безвозвратно.',
          style: GoogleFonts.manrope(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger.withOpacity(0.9)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(source == 'payment' ? 'Отменить' : 'Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    if (source == 'flow') {
      await DatabaseHelper().deleteCashFlow(id);
    } else {
      await DatabaseHelper().voidPayment(id);
    }
    _changed = true;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.registerName,
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.moneyType} · ${_money.format(widget.expected)} ₽ · ${widget.startDate} — ${widget.endDate}',
            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
          ),
        ],
      ),
      content: SizedBox(
        width: AppResponsive.dialogWidth(context, desktop: 560),
        height: AppResponsive.isMobile(context) ? MediaQuery.sizeOf(context).height * 0.55 : 440,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _rows.isEmpty
                ? Center(
                    child: Text(
                      'Нет транзакций',
                      style: GoogleFonts.manrope(color: AppColors.textDim),
                    ),
                  )
                : ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (_, i) {
                      final row = _rows[i];
                      final isIncome = row['type']?.toString() == 'Приход';
                      final color = isIncome ? AppColors.success : AppColors.danger;
                      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
                      final meta = [
                        row['category']?.toString() ?? '',
                        row['method']?.toString() ?? '',
                      ].where((s) => s.isNotEmpty).join(' · ');
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        title: Text(
                          row['title']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        subtitle: Text(
                          '${AppDateTime.formatShort(row['created_at'])}${meta.isEmpty ? '' : ' · $meta'}',
                          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${isIncome ? '+' : '−'}${_money.format(amount)} ₽',
                              style: GoogleFonts.manrope(
                                color: color,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Изменить',
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _editRow(row),
                            ),
                            IconButton(
                              tooltip: 'Удалить',
                              icon: Icon(Icons.delete_outline, size: 18, color: AppColors.danger.withOpacity(0.9)),
                              onPressed: () => _deleteRow(row),
                            ),
                          ],
                        ),
                        onTap: () => _editRow(row),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _changed),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}
