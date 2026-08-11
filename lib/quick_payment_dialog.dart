import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'app_toast.dart';
import 'cash_catalog.dart';
import 'database.dart';
import 'responsive.dart';

/// Быстрая оплата / предоплата без полного открытия карточки заказа.
class QuickPaymentDialog {
  QuickPaymentDialog._();

  static final _money = NumberFormat('#,##0.##', 'ru_RU');

  /// Возвращает `true`, если оплата проведена.
  /// Для пульса оберните вызов в [PulseHighlightMixin.runWithPulseHighlight].
  static Future<bool> open(
    BuildContext context, {
    required int orderId,
  }) async {
    final order = await DatabaseHelper().getOrderById(orderId);
    if (order == null) {
      if (context.mounted) showAppToast(context, 'Заказ не найден');
      return false;
    }
    final price = (order['price'] as num?)?.toDouble() ?? 0;
    final paid = (order['paid_amount'] as num?)?.toDouble() ?? 0;
    final debt = price - paid;
    if (debt <= 0.01) {
      if (context.mounted) showAppToast(context, 'По заказу нет долга');
      return false;
    }

    final registers = await DatabaseHelper().getCashRegisters();
    if (!context.mounted) return false;

    final amountCtrl = TextEditingController(
      text: debt == debt.roundToDouble() ? debt.toInt().toString() : debt.toStringAsFixed(2),
    );
    var method = CashMethods.cash;
    int? registerId;
    for (final r in registers) {
      if (r['money_type']?.toString() == method) {
        registerId = (r['id'] as num).toInt();
        break;
      }
    }

    Future<bool?> show() {
      return showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              return AlertDialog(
                backgroundColor: AppColors.surface,
                title: Text(
                  'Быстрая оплата · #$orderId',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                ),
                content: SizedBox(
                  width: AppResponsive.dialogWidth(ctx, desktop: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${order['client_name'] ?? ''} · ${order['plate'] ?? ''}',
                        style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Долг: ${_money.format(debt)} ₽',
                        style: GoogleFonts.manrope(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: amountCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Сумма',
                          isDense: true,
                          suffixText: '₽',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: method,
                        decoration: const InputDecoration(labelText: 'Способ', isDense: true),
                        dropdownColor: AppColors.surface2,
                        items: CashMethods.all
                            .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setLocal(() {
                            method = v;
                            registerId = null;
                            for (final r in registers) {
                              if (r['money_type']?.toString() == method) {
                                registerId = (r['id'] as num).toInt();
                                break;
                              }
                            }
                          });
                        },
                      ),
                      if (registers.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<int>(
                          value: registerId != null &&
                                  registers.any((r) => (r['id'] as num).toInt() == registerId)
                              ? registerId
                              : null,
                          decoration: const InputDecoration(labelText: 'Касса', isDense: true),
                          dropdownColor: AppColors.surface2,
                          items: registers
                              .map(
                                (r) => DropdownMenuItem(
                                  value: (r['id'] as num).toInt(),
                                  child: Text('${r['name']} · ${r['money_type']}'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setLocal(() => registerId = v),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Провести'),
                  ),
                ],
              );
            },
          );
        },
      );
    }

    final ok = await show();
    final amount = double.tryParse(amountCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    amountCtrl.dispose();
    if (ok != true || amount <= 0) return false;
    if (!context.mounted) return false;

    if (registers.isNotEmpty && registerId == null) {
      showAppToast(context, 'Выберите кассу');
      return false;
    }

    final shift = await DatabaseHelper().getCurrentShift();
    if (shift == null) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('Смена не открыта', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
            content: Text(
              'Откройте смену в разделе «Касса», затем проведите оплату.\n'
              'Без смены оплата запрещена.',
              style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.35),
            ),
            actions: [
              ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
            ],
          ),
        );
      }
      return false;
    }

    var rid = registerId;
    rid ??= await DatabaseHelper().resolveRegisterIdForMethod(method);

    await DatabaseHelper().addPayment(
      orderId,
      amount,
      method,
      shiftId: (shift['id'] as num).toInt(),
      registerId: rid,
    );
    await DatabaseHelper().updateOrderPaymentMethod(orderId, method);
    await DatabaseHelper().addOrderEvent(
      orderId,
      'Быстрая оплата: $amount руб ($method)',
    );

    if (context.mounted) {
      showAppToast(context, 'Оплата ${_money.format(amount)} ₽ проведена');
    }
    return true;
  }
}
