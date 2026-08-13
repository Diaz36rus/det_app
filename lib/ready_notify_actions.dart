import 'package:flutter/material.dart';

import 'app_toast.dart';
import 'database.dart';
import 'debt_reminder.dart';

/// WhatsApp / копирование: «готов к выдаче» + отметка в чек-листе.
class ReadyNotifyActions {
  ReadyNotifyActions._();

  /// Возвращает `true`, если действие выполнено (открыт WA / скопировано).
  static Future<bool> notifyOrder(
    BuildContext context, {
    required Map<String, dynamic> order,
    bool markHandoverNotified = true,
  }) async {
    final orderId = (order['id'] as num?)?.toInt();
    if (orderId == null) {
      if (context.mounted) showAppToast(context, 'Заказ не найден');
      return false;
    }

    final price = (order['price'] as num?)?.toDouble() ?? 0;
    final paid = (order['paid_amount'] as num?)?.toDouble() ?? 0;
    final debt = price - paid;
    final text = DebtReminder.buildReadyText(
      clientName: order['client_name']?.toString() ?? '',
      orderId: orderId,
      plate: order['plate']?.toString(),
      car: order['make_model']?.toString(),
      debt: debt,
    );

    final result = await DebtReminder.share(
      phone: order['client_phone']?.toString(),
      text: text,
    );
    if (!context.mounted) return false;

    switch (result) {
      case 'opened':
        showAppToast(context, 'Открыт WhatsApp');
      case 'copied_link':
        showAppToast(context, 'Ссылка WhatsApp скопирована');
      case 'no_phone':
        showAppToast(context, 'Нет телефона — текст скопирован');
      default:
        showAppToast(context, 'Текст скопирован');
    }

    if (markHandoverNotified) {
      await DatabaseHelper().saveOrderHandover(orderId, {'handover_notified': 1});
      await DatabaseHelper().addOrderEvent(orderId, 'WhatsApp: уведомление о готовности');
    }
    return true;
  }

  static Future<bool> notifyByOrderId(
    BuildContext context, {
    required int orderId,
    bool markHandoverNotified = true,
  }) async {
    final order = await DatabaseHelper().getOrderById(orderId);
    if (order == null) {
      if (context.mounted) showAppToast(context, 'Заказ не найден');
      return false;
    }
    if (!context.mounted) return false;
    return notifyOrder(
      context,
      order: order,
      markHandoverNotified: markHandoverNotified,
    );
  }
}
