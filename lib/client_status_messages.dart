import 'package:flutter/material.dart';

import 'app_toast.dart';
import 'debt_reminder.dart';
import 'studio_prefs.dart';

/// Исходящие статусы клиенту (Telegram / WhatsApp / SMS) — R2.
class ClientStatusMessages {
  ClientStatusMessages._();

  static Future<String> buildBooking({
    required String clientName,
    required int orderId,
    String? plate,
    String? car,
    String? when,
  }) async {
    final tpls = await StudioPrefs.loadMessageTemplates();
    final custom = (tpls['booking'] ?? '').trim();
    final who = clientName.trim().isEmpty ? 'Клиент' : clientName.trim();
    final carBit = [
      if ((car ?? '').trim().isNotEmpty) car!.trim(),
      if ((plate ?? '').trim().isNotEmpty) plate!.trim(),
    ].join(' · ');
    if (custom.isNotEmpty) {
      return StudioPrefs.applyTemplate(
        custom,
        name: who,
        order: '#$orderId',
        car: carBit,
        debt: when ?? '',
      );
    }
    final buf = StringBuffer();
    buf.writeln('Здравствуйте, $who!');
    buf.writeln('Вы записаны в студию. Заказ #$orderId');
    if (carBit.isNotEmpty) buf.writeln(carBit);
    if ((when ?? '').trim().isNotEmpty) buf.writeln('Когда: ${when!.trim()}');
    buf.write('Ждём вас!');
    return buf.toString();
  }

  static Future<String> buildTomorrow({
    required String clientName,
    required int orderId,
    String? plate,
    String? car,
    String? when,
  }) async {
    final who = clientName.trim().isEmpty ? 'Клиент' : clientName.trim();
    final carBit = [
      if ((car ?? '').trim().isNotEmpty) car!.trim(),
      if ((plate ?? '').trim().isNotEmpty) plate!.trim(),
    ].join(' · ');
    final buf = StringBuffer();
    buf.writeln('Здравствуйте, $who!');
    buf.writeln('Напоминаем: завтра визит в студию (заказ #$orderId).');
    if (carBit.isNotEmpty) buf.writeln(carBit);
    if ((when ?? '').trim().isNotEmpty) buf.writeln('Время: ${when!.trim()}');
    buf.write('До встречи!');
    return buf.toString();
  }

  static Future<String> buildWarrantyReminder({
    required String clientName,
    required String kind,
    required String endsAt,
    String? car,
  }) async {
    final who = clientName.trim().isEmpty ? 'Клиент' : clientName.trim();
    final buf = StringBuffer();
    buf.writeln('Здравствуйте, $who!');
    buf.writeln('Напоминание о ТО покрытия: $kind');
    if ((car ?? '').trim().isNotEmpty) buf.writeln(car!.trim());
    buf.writeln('Гарантия до $endsAt');
    buf.write('Запишитесь на осмотр в удобное время.');
    return buf.toString();
  }

  static String _titleForKind(String kind) => switch (kind) {
        'tomorrow' => 'Напоминание на завтра',
        'ready' => 'Готов к выдаче',
        'debt' => 'Напоминание о долге',
        _ => 'Подтверждение записи',
      };

  /// Уже собранный текст → выбор канала / канал по умолчанию.
  static Future<void> sharePrepared(
    BuildContext context, {
    required String? phone,
    required String text,
    String title = 'Отправить клиенту',
  }) async {
    if (!context.mounted) return;
    final preferredId = await StudioPrefs.loadClientMsgChannel();
    if (!context.mounted) return;
    final preferred = ClientMsgChannelX.tryParse(preferredId);
    late final String result;
    if (preferred != null) {
      result = await DebtReminder.sendVia(channel: preferred, phone: phone, text: text);
    } else {
      result = await DebtReminder.sharePickChannel(
        context,
        phone: phone,
        text: text,
        title: title,
      );
    }
    if (!context.mounted || result == 'cancelled') return;
    final msg = DebtReminder.toastForResult(result);
    if (msg.isNotEmpty) showAppToast(context, msg);
  }

  static Future<void> shareFromOrder(
    BuildContext context, {
    required Map<String, dynamic> order,
    required String kind, // booking | tomorrow | ready | debt
  }) async {
    final orderId = (order['id'] as num?)?.toInt();
    if (orderId == null) {
      showAppToast(context, 'Заказ не найден');
      return;
    }
    final name = order['client_name']?.toString() ?? '';
    final phone = order['client_phone']?.toString();
    final plate = order['plate']?.toString();
    final car = order['make_model']?.toString();
    final price = (order['price'] as num?)?.toDouble() ?? 0;
    final paid = (order['paid_amount'] as num?)?.toDouble() ?? 0;
    final debt = (price - paid).clamp(0, double.infinity);
    final when = [
      order['due_date']?.toString() ?? '',
      order['start_time']?.toString() ?? '',
    ].where((s) => s.trim().isNotEmpty).join(' ');

    late final String text;
    switch (kind) {
      case 'tomorrow':
        text = await buildTomorrow(
          clientName: name,
          orderId: orderId,
          plate: plate,
          car: car,
          when: when,
        );
      case 'ready':
        text = await DebtReminder.buildReadyTextAsync(
          clientName: name,
          orderId: orderId,
          plate: plate,
          car: car,
          debt: debt.toDouble(),
        );
      case 'debt':
        text = await DebtReminder.buildTextAsync(
          clientName: name,
          orderId: orderId,
          debt: debt.toDouble(),
          plate: plate,
          car: car,
        );
      default:
        text = await buildBooking(
          clientName: name,
          orderId: orderId,
          plate: plate,
          car: car,
          when: when,
        );
    }

    if (!context.mounted) return;
    await sharePrepared(context, phone: phone, text: text, title: _titleForKind(kind));
  }
}
