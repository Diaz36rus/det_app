import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Тексты клиенту + копирование / попытка открыть WhatsApp.
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
    final buf = StringBuffer();
    buf.writeln('Здравствуйте, $who!');
    buf.writeln('Напоминаем о задолженности по заказу #$orderId');
    if (carBit.isNotEmpty) buf.writeln(carBit);
    buf.writeln('Сумма: ${_money.format(debt)} ₽');
    buf.write('Ждём вас в студии.');
    return buf.toString();
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

  static Future<void> copyText(String text) => Clipboard.setData(ClipboardData(text: text));

  /// Цифры для wa.me (только 0–9). Российский +7 → 79…
  static String? whatsAppDigits(String? phone) {
    if (phone == null) return null;
    var d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return null;
    if (d.length == 11 && d.startsWith('8')) d = '7${d.substring(1)}';
    if (d.length == 10) d = '7$d';
    if (d.length < 11) return null;
    return d;
  }

  static String? whatsAppUrl(String? phone, String text) {
    final digits = whatsAppDigits(phone);
    if (digits == null) return null;
    return 'https://wa.me/$digits?text=${Uri.encodeComponent(text)}';
  }

  /// Открывает WhatsApp/браузер по возможности. Иначе копирует ссылку.
  /// Возвращает: `opened` | `copied_link` | `copied_text` | `no_phone`.
  static Future<String> share({
    required String? phone,
    required String text,
  }) async {
    final url = whatsAppUrl(phone, text);
    if (url == null) {
      await copyText(text);
      return 'no_phone';
    }
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', url], runInShell: true);
        return 'opened';
      }
      if (Platform.isMacOS) {
        await Process.start('open', [url]);
        return 'opened';
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [url]);
        return 'opened';
      }
      if (Platform.isAndroid || Platform.isIOS) {
        // Без url_launcher: копируем ссылку — пользователь откроет вручную.
        await copyText(url);
        return 'copied_link';
      }
    } catch (_) {}
    await copyText(text);
    return 'copied_text';
  }
}
