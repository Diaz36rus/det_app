import 'package:flutter/services.dart';

/// Временная маска: всегда "+7", дальше только цифры (до 10).
class PhonePlus7Formatter extends TextInputFormatter {
  static const prefix = '+7';

  static String normalize(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('7')) digits = digits.substring(1);
    if (digits.startsWith('8') && digits.length >= 10) {
      // часто вводят 8XXXXXXXXXX
      digits = digits.substring(1);
    }
    if (digits.length > 10) digits = digits.substring(0, 10);
    return '$prefix$digits';
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = normalize(newValue.text);
    // курсор: если пытались стереть префикс — ставим после +7
    var offset = newValue.selection.baseOffset;
    if (offset < prefix.length) offset = prefix.length;
    if (offset > text.length) offset = text.length;
    // при нормализации длина могла сильно измениться
    if (oldValue.text != text && newValue.text.length < oldValue.text.length) {
      offset = text.length;
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset.clamp(prefix.length, text.length)),
    );
  }
}

/// Маска госномера РФ: буква + 3 цифры + 2 буквы + 3 цифры региона (A123BC777).
class PlateMaskFormatter extends TextInputFormatter {
  static final _isLetter = RegExp(r'[A-Za-zА-Яа-яЁё]');
  static final _isDigit = RegExp(r'[0-9]');

  /// Кириллица ↔ латиница для похожих букв госномера (А/A, Х/X …).
  static const _lookalikeToLatin = {
    'А': 'A',
    'В': 'B',
    'Е': 'E',
    'К': 'K',
    'М': 'M',
    'Н': 'H',
    'О': 'O',
    'Р': 'P',
    'С': 'C',
    'Т': 'T',
    'У': 'Y',
    'Х': 'X',
  };

  static String normalize(String raw) {
    final chars = <String>[];
    for (final rune in raw.toUpperCase().runes) {
      final ch = String.fromCharCode(rune);
      final i = chars.length;
      if (i >= 9) break;
      // L D D D L L D D D
      if (i == 0 || i == 4 || i == 5) {
        if (_isLetter.hasMatch(ch)) chars.add(ch);
      } else {
        if (_isDigit.hasMatch(ch)) chars.add(ch);
      }
    }
    return chars.join();
  }

  /// Ключ сравнения номеров: без пробелов, upper, кириллические «двойники» → латиница.
  static String canonicalKey(String raw) {
    final n = normalize(raw);
    final buf = StringBuffer();
    for (final rune in n.runes) {
      final ch = String.fromCharCode(rune);
      buf.write(_lookalikeToLatin[ch] ?? ch);
    }
    return buf.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = normalize(newValue.text);
    var offset = newValue.selection.baseOffset;
    if (offset > text.length) offset = text.length;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset.clamp(0, text.length)),
    );
  }
}
