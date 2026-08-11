import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'cash_catalog.dart';
import 'database.dart';
import 'responsive.dart';

/// Правка / отмена оплаты заказа из кассы.
class PaymentEditDialog extends StatefulWidget {
  final int paymentId;
  final double initialAmount;
  final String initialMethod;
  final int? initialRegisterId;
  final int? orderId;
  final String title;

  const PaymentEditDialog({
    super.key,
    required this.paymentId,
    required this.initialAmount,
    required this.initialMethod,
    this.initialRegisterId,
    this.orderId,
    this.title = 'Оплата заказа',
  });

  static Future<String?> open(
    BuildContext context, {
    required int paymentId,
    required double amount,
    required String method,
    int? registerId,
    int? orderId,
    String title = 'Оплата заказа',
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => PaymentEditDialog(
        paymentId: paymentId,
        initialAmount: amount,
        initialMethod: method,
        initialRegisterId: registerId,
        orderId: orderId,
        title: title,
      ),
    );
  }

  @override
  State<PaymentEditDialog> createState() => _PaymentEditDialogState();
}

class _PaymentEditDialogState extends State<PaymentEditDialog> {
  final _amountCtrl = TextEditingController();
  List<Map<String, dynamic>> _registers = [];
  int? _registerId;
  String _method = CashMethods.cash;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountCtrl.text = widget.initialAmount.toStringAsFixed(
      widget.initialAmount == widget.initialAmount.roundToDouble() ? 0 : 2,
    );
    _method = widget.initialMethod.isNotEmpty ? widget.initialMethod : CashMethods.cash;
    _registerId = widget.initialRegisterId;
    _loadRegisters();
  }

  Future<void> _loadRegisters() async {
    final regs = await DatabaseHelper().getCashRegisters();
    if (!mounted) return;
    setState(() {
      _registers = regs;
      if (_registerId == null && regs.isNotEmpty) {
        Map<String, dynamic>? match;
        for (final r in regs) {
          if (r['money_type']?.toString() == _method) {
            match = r;
            break;
          }
        }
        _registerId = ((match ?? regs.first)['id'] as num).toInt();
      }
    });
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Укажите сумму больше 0');
      return;
    }
    var method = _method;
    if (_registerId != null) {
      for (final r in _registers) {
        if ((r['id'] as num).toInt() == _registerId) {
          method = r['money_type']?.toString() ?? method;
          break;
        }
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await DatabaseHelper().updatePayment(
      widget.paymentId,
      amount: amount,
      method: method,
      registerId: _registerId,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'Не удалось сохранить';
      });
      return;
    }
    Navigator.pop(context, 'saved');
  }

  Future<void> _void() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Отменить оплату?', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: Text(
          'Платёж будет удалён, сумма в заказе пересчитается.',
          style: GoogleFonts.manrope(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger.withOpacity(0.9)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отменить оплату'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    await DatabaseHelper().voidPayment(widget.paymentId);
    if (!mounted) return;
    Navigator.pop(context, 'voided');
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Оплата',
        style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: SizedBox(
        width: AppResponsive.dialogWidth(context, desktop: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              decoration: const InputDecoration(labelText: 'Сумма ₽', isDense: true),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 10),
            if (_registers.isNotEmpty)
              DropdownButtonFormField<int>(
                value: _registers.any((r) => (r['id'] as num).toInt() == _registerId)
                    ? _registerId
                    : (_registers.first['id'] as num).toInt(),
                decoration: const InputDecoration(labelText: 'Касса', isDense: true),
                dropdownColor: AppColors.surface2,
                items: _registers
                    .map(
                      (r) => DropdownMenuItem<int>(
                        value: (r['id'] as num).toInt(),
                        child: Text('${r['name']} · ${r['money_type']}'),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _registerId = v;
                    for (final r in _registers) {
                      if ((r['id'] as num).toInt() == v) {
                        _method = r['money_type']?.toString() ?? _method;
                        break;
                      }
                    }
                  });
                },
              )
            else
              DropdownButtonFormField<String>(
                value: CashMethods.all.contains(_method) ? _method : CashMethods.cash,
                decoration: const InputDecoration(labelText: 'Способ', isDense: true),
                dropdownColor: AppColors.surface2,
                items: CashMethods.all.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _method = v);
                },
              ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: GoogleFonts.manrope(color: AppColors.danger, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _void,
          child: Text('Удалить', style: GoogleFonts.manrope(color: AppColors.danger)),
        ),
        if (widget.orderId != null)
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, 'order'),
            child: const Text('Открыть заказ'),
          ),
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? '…' : 'Сохранить', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
