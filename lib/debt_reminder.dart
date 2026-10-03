import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'app_theme.dart';
import 'open_url.dart';
import 'studio_prefs.dart';

/// Канал исходящего сообщения клиенту (РФ: Telegram / WA / SMS).
enum ClientMsgChannel {
  telegram,
  whatsapp,
  sms,
  copy,
}

extension ClientMsgChannelX on ClientMsgChannel {
  String get id => name;

  String get label => switch (this) {
        ClientMsgChannel.telegram => 'Telegram',
        ClientMsgChannel.whatsapp => 'WhatsApp',
        ClientMsgChannel.sms => 'SMS',
        ClientMsgChannel.copy => 'Скопировать',
      };

  String get hint => switch (this) {
        ClientMsgChannel.telegram => 'Чат по номеру · текст в буфере',
        ClientMsgChannel.whatsapp => 'Открыть чат с текстом',
        ClientMsgChannel.sms => 'Стандартные сообщения',
        ClientMsgChannel.copy => 'Вставить вручную в любой мессенджер',
      };

  static ClientMsgChannel? tryParse(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    if (v.isEmpty || v == 'ask') return null;
    for (final c in ClientMsgChannel.values) {
      if (c.id == v) return c;
    }
    return null;
  }
}

/// Тексты клиенту + отправка через каналы, актуальные для РФ.
class DebtReminder {
  DebtReminder._();

  static final _money = NumberFormat('#,##0.##', 'ru_RU');

  static String _carBit(String? plate, String? car) {
    return [
      if ((car ?? '').trim().isNotEmpty) car!.trim(),
      if ((plate ?? '').trim().isNotEmpty) plate!.trim(),
    ].join(' · ');
  }

  static String buildText({
    required String clientName,
    required int orderId,
    required double debt,
    String? plate,
    String? car,
  }) {
    final who = clientName.trim().isEmpty ? 'Клиент' : clientName.trim();
    final carBit = _carBit(plate, car);
    final debtStr = '${_money.format(debt)} ₽';
    final buf = StringBuffer();
    buf.writeln('Здравствуйте, $who!');
    buf.writeln('Напоминаем о задолженности по заказу #$orderId');
    if (carBit.isNotEmpty) buf.writeln(carBit);
    buf.writeln('Сумма: $debtStr');
    buf.write('Ждём вас в студии.');
    return buf.toString();
  }

  static Future<String> buildTextAsync({
    required String clientName,
    required int orderId,
    required double debt,
    String? plate,
    String? car,
  }) async {
    final tpls = await StudioPrefs.loadMessageTemplates();
    final custom = (tpls['debt'] ?? '').trim();
    if (custom.isEmpty) {
      return buildText(clientName: clientName, orderId: orderId, debt: debt, plate: plate, car: car);
    }
    final who = clientName.trim().isEmpty ? 'Клиент' : clientName.trim();
    return StudioPrefs.applyTemplate(
      custom,
      name: who,
      order: '#$orderId',
      debt: '${_money.format(debt)} ₽',
      car: _carBit(plate, car),
    );
  }

  /// Сообщение «автомобиль готов к выдаче» (+ долг, если есть).
  static String buildReadyText({
    required String clientName,
    required int orderId,
    String? plate,
    String? car,
    double debt = 0,
  }) {
    final who = clientName.trim().isEmpty ? 'Клиент' : clientName.trim();
    final carBit = _carBit(plate, car);
    final buf = StringBuffer();
    buf.writeln('Здравствуйте, $who!');
    buf.writeln('Ваш автомобиль готов к выдаче.');
    buf.writeln('Заказ #$orderId');
    if (carBit.isNotEmpty) buf.writeln(carBit);
    if (debt > 0.01) {
      buf.writeln('К оплате: ${_money.format(debt)} ₽');
    }
    buf.write('Ждём вас в студии!');
    return buf.toString();
  }

  static Future<String> buildReadyTextAsync({
    required String clientName,
    required int orderId,
    String? plate,
    String? car,
    double debt = 0,
  }) async {
    final tpls = await StudioPrefs.loadMessageTemplates();
    final custom = (tpls['ready'] ?? '').trim();
    if (custom.isEmpty) {
      return buildReadyText(
        clientName: clientName,
        orderId: orderId,
        plate: plate,
        car: car,
        debt: debt,
      );
    }
    final who = clientName.trim().isEmpty ? 'Клиент' : clientName.trim();
    return StudioPrefs.applyTemplate(
      custom,
      name: who,
      order: '#$orderId',
      debt: debt > 0.01 ? '${_money.format(debt)} ₽' : '',
      car: _carBit(plate, car),
    );
  }

  static Future<void> copyText(String text) => Clipboard.setData(ClipboardData(text: text));

  /// Цифры телефона РФ: 79XXXXXXXXX (только 0–9).
  static String? ruPhoneDigits(String? phone) {
    if (phone == null) return null;
    var d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return null;
    if (d.length == 11 && d.startsWith('8')) d = '7${d.substring(1)}';
    if (d.length == 10) d = '7$d';
    if (d.length < 11) return null;
    return d;
  }

  /// @deprecated alias — раньше только WhatsApp.
  static String? whatsAppDigits(String? phone) => ruPhoneDigits(phone);

  static String? whatsAppUrl(String? phone, String text) {
    final digits = ruPhoneDigits(phone);
    if (digits == null) return null;
    return 'https://wa.me/$digits?text=${Uri.encodeComponent(text)}';
  }

  static String? telegramResolveUrl(String? phone) {
    final digits = ruPhoneDigits(phone);
    if (digits == null) return null;
    // Открывает чат по номеру (если Telegram установлен). Текст — отдельно в буфер.
    return 'tg://resolve?phone=$digits';
  }

  static String telegramShareUrl(String text) {
    return 'https://t.me/share/url?url=&text=${Uri.encodeComponent(text)}';
  }

  static String? smsUrl(String? phone, String text) {
    final digits = ruPhoneDigits(phone);
    if (digits == null) return null;
    // Android: sms:+79...?body=  iOS: sms:+79...&body=
    final body = Uri.encodeComponent(text);
    if (Platform.isIOS) {
      return 'sms:+$digits&body=$body';
    }
    return 'sms:+$digits?body=$body';
  }

  static Future<bool> _openUrl(String url) async {
    final ok = await openExternalUrl(url);
    if (ok) return true;
    // Desktop fallback без url_launcher quirks
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', url], runInShell: true);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [url]);
        return true;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [url]);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Результат: `opened_telegram` | `opened_whatsapp` | `opened_sms` |
  /// `copied_link` | `copied_text` | `no_phone` | `cancelled`.
  static Future<String> sendVia({
    required ClientMsgChannel channel,
    required String? phone,
    required String text,
  }) async {
    switch (channel) {
      case ClientMsgChannel.copy:
        await copyText(text);
        return phone == null || phone.trim().isEmpty ? 'no_phone' : 'copied_text';

      case ClientMsgChannel.whatsapp:
        final url = whatsAppUrl(phone, text);
        if (url == null) {
          await copyText(text);
          return 'no_phone';
        }
        if (await _openUrl(url)) return 'opened_whatsapp';
        await copyText(url);
        return 'copied_link';

      case ClientMsgChannel.sms:
        final url = smsUrl(phone, text);
        if (url == null) {
          await copyText(text);
          return 'no_phone';
        }
        if (await _openUrl(url)) return 'opened_sms';
        await copyText(text);
        return 'copied_text';

      case ClientMsgChannel.telegram:
        final resolve = telegramResolveUrl(phone);
        if (resolve == null) {
          // Нет телефона — share sheet Telegram с текстом
          await copyText(text);
          if (await _openUrl(telegramShareUrl(text))) return 'opened_telegram';
          return 'no_phone';
        }
        // Текст в буфер: tg://resolve не передаёт body.
        await copyText(text);
        if (await _openUrl(resolve)) return 'opened_telegram';
        // Fallback: системный share в Telegram
        if (await _openUrl(telegramShareUrl(text))) return 'opened_telegram';
        return 'copied_text';
    }
  }

  /// Совместимость: открывает канал по умолчанию или WhatsApp.
  static Future<String> share({
    required String? phone,
    required String text,
  }) async {
    final preferred = ClientMsgChannelX.tryParse(await StudioPrefs.loadClientMsgChannel()) ??
        ClientMsgChannel.telegram;
    return sendVia(channel: preferred, phone: phone, text: text);
  }

  static String toastForResult(String result) {
    return switch (result) {
      'opened_telegram' => 'Telegram · текст в буфере — вставьте в чат',
      'opened_whatsapp' => 'Открыт WhatsApp',
      'opened_sms' => 'Открыты SMS',
      'copied_link' => 'Ссылка скопирована',
      'no_phone' => 'Нет телефона — текст скопирован',
      'cancelled' => '',
      _ => 'Текст скопирован',
    };
  }

  /// Показать выбор канала (РФ) и отправить.
  static Future<String> sharePickChannel(
    BuildContext context, {
    required String? phone,
    required String text,
    String title = 'Отправить клиенту',
  }) async {
    final preferredId = await StudioPrefs.loadClientMsgChannel();
    final preferred = ClientMsgChannelX.tryParse(preferredId);

    if (!context.mounted) return 'cancelled';

    final chosen = await showModalBottomSheet<ClientMsgChannel>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        Widget tile(ClientMsgChannel ch, {IconData? icon}) {
          final isPref = preferred == ch;
          return ListTile(
            leading: Icon(icon ?? Icons.send_rounded, color: AppColors.primary),
            title: Text(
              ch.label + (isPref ? ' · по умолчанию' : ''),
              style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: AppColors.text),
            ),
            subtitle: Text(
              ch.hint,
              style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textDim),
            ),
            onTap: () => Navigator.pop(ctx, ch),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: AppColors.text,
                    ),
                  ),
                ),
                tile(ClientMsgChannel.telegram, icon: Icons.send_rounded),
                tile(ClientMsgChannel.whatsapp, icon: Icons.chat_rounded),
                tile(ClientMsgChannel.sms, icon: Icons.sms_rounded),
                tile(ClientMsgChannel.copy, icon: Icons.copy_rounded),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Отмена', style: GoogleFonts.manrope(color: AppColors.textMuted)),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (chosen == null) return 'cancelled';
    return sendVia(channel: chosen, phone: phone, text: text);
  }
}
