import 'package:flutter/material.dart';

import 'app_toast.dart';
import 'app_notifications.dart';
import 'client_notify.dart';
import 'database.dart';

/// Уведомление клиенту «готов к выдаче» + отметка в чек-листе.
class ReadyNotifyActions {
  ReadyNotifyActions._();

  /// Возвращает `true`, если действие выполнено (канал открыт / скопировано / бот).
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

    if (!context.mounted) return false;
    await ClientNotify.sendForOrder(context, order: order, kind: 'ready');

    if (markHandoverNotified) {
      await DatabaseHelper().saveOrderHandover(orderId, {'handover_notified': 1});
      await DatabaseHelper().addOrderEvent(orderId, 'Клиенту: уведомление о готовности');
    }
    await AppNotifications.postClientReadyWa(
      orderId: orderId,
      clientName: order['client_name']?.toString(),
    );
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
