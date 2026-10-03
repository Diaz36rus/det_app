import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';
import 'app_toast.dart';
import 'auth/auth_controller.dart';
import 'client_status_messages.dart';
import 'crm/crm_api.dart';
import 'debt_reminder.dart';
import 'open_url.dart';

/// Каскад клиенту: облачный Telegram-бот → SMS → ручной выбор канала.
class ClientNotify {
  ClientNotify._();

  static bool get cloudReady =>
      (AuthController.instance.accessToken ?? '').trim().isNotEmpty;

  /// Отправка по заказу. [kind]: booking | tomorrow | ready | debt.
  static Future<void> sendForOrder(
    BuildContext context, {
    required Map<String, dynamic> order,
    required String kind,
  }) async {
    final orderId = (order['id'] as num?)?.toInt();
    if (orderId == null) {
      showAppToast(context, 'Заказ не найден');
      return;
    }

    if (cloudReady) {
      try {
        final res = await CrmApi().notifyOrderClient(orderId, kind: kind);
        if (!context.mounted) return;
        if (res.ok) {
          final label = switch (res.channel) {
            'telegram' => 'Отправлено в Telegram',
            'sms' => 'Отправлено SMS',
            _ => res.detail.isNotEmpty ? res.detail : 'Отправлено',
          };
          showAppToast(context, label);
          return;
        }
        if (res.bindUrl != null && res.bindUrl!.trim().isNotEmpty) {
          final action = await _showBindOrManual(
            context,
            detail: res.detail,
          );
          if (!context.mounted) return;
          if (action == 'bind') {
            await Clipboard.setData(ClipboardData(text: res.bindUrl!));
            final opened = await openExternalUrl(res.bindUrl!);
            if (context.mounted) {
              showAppToast(
                context,
                opened ? 'Ссылка бота открыта · скопирована' : 'Ссылка бота скопирована',
              );
            }
            return;
          }
          if (action == 'manual') {
            final text = res.text.isNotEmpty ? res.text : await _buildLocalText(order, kind);
            if (!context.mounted) return;
            await ClientStatusMessages.sharePrepared(
              context,
              phone: order['client_phone']?.toString(),
              text: text,
              title: _title(kind),
            );
            return;
          }
          return;
        }
        final text = res.text.isNotEmpty ? res.text : await _buildLocalText(order, kind);
        if (!context.mounted) return;
        await ClientStatusMessages.sharePrepared(
          context,
          phone: order['client_phone']?.toString(),
          text: text,
          title: _title(kind),
        );
        return;
      } catch (_) {
        // офлайн / старый API
      }
    }

    if (!context.mounted) return;
    await ClientStatusMessages.shareFromOrder(context, order: order, kind: kind);
  }

  static Future<String> _buildLocalText(Map<String, dynamic> order, String kind) async {
    final orderId = (order['id'] as num).toInt();
    final name = order['client_name']?.toString() ?? '';
    final plate = order['plate']?.toString();
    final car = order['make_model']?.toString();
    final price = (order['price'] as num?)?.toDouble() ?? 0;
    final paid = (order['paid_amount'] as num?)?.toDouble() ?? 0;
    final debt = (price - paid).clamp(0, double.infinity).toDouble();
    final when = [
      order['due_date']?.toString() ?? '',
      order['start_time']?.toString() ?? '',
    ].where((s) => s.trim().isNotEmpty).join(' ');
    switch (kind) {
      case 'tomorrow':
        return ClientStatusMessages.buildTomorrow(
          clientName: name,
          orderId: orderId,
          plate: plate,
          car: car,
          when: when,
        );
      case 'ready':
        return DebtReminder.buildReadyTextAsync(
          clientName: name,
          orderId: orderId,
          plate: plate,
          car: car,
          debt: debt,
        );
      case 'debt':
        return DebtReminder.buildTextAsync(
          clientName: name,
          orderId: orderId,
          debt: debt,
          plate: plate,
          car: car,
        );
      default:
        return ClientStatusMessages.buildBooking(
          clientName: name,
          orderId: orderId,
          plate: plate,
          car: car,
          when: when,
        );
    }
  }

  static String _title(String kind) => switch (kind) {
        'tomorrow' => 'Напоминание на завтра',
        'ready' => 'Готов к выдаче',
        'debt' => 'Напоминание о долге',
        _ => 'Подтверждение записи',
      };

  static Future<String?> _showBindOrManual(
    BuildContext context, {
    required String detail,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Клиент ещё не в Telegram-боте',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                detail.isNotEmpty
                    ? detail
                    : 'Отправьте ссылку — клиент нажмёт Start, дальше уведомления пойдут сами.',
                style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'bind'),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text('Ссылка на бота', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, 'manual'),
                child: Text(
                  'Отправить вручную (TG / WA / SMS)',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Отмена', style: GoogleFonts.manrope(color: AppColors.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> copyBindLink(
    BuildContext context, {
    required int clientId,
  }) async {
    if (!cloudReady) {
      showAppToast(context, 'Нужен вход в облако для Telegram-бота');
      return;
    }
    try {
      final res = await CrmApi().telegramBindLink(clientId);
      final url = res['bind_url']?.toString() ?? '';
      if (url.isEmpty) {
        if (context.mounted) showAppToast(context, 'Бот не настроен на сервере');
        return;
      }
      await Clipboard.setData(ClipboardData(text: url));
      await openExternalUrl(url);
      if (context.mounted) showAppToast(context, 'Ссылка бота скопирована');
    } catch (_) {
      if (context.mounted) showAppToast(context, 'Не удалось получить ссылку');
    }
  }
}
