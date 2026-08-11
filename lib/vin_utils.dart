/// ISO 3779: VIN — 17 символов без I, O, Q.
class VinUtils {
  static const requiredLength = 17;
  static final allowed = RegExp(r'^[A-HJ-NPR-Z0-9]+$');

  static String normalize(String raw) =>
      raw.trim().toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

  /// Пустой VIN допустим. Если введён — строго 17 допустимых символов.
  static String? validate(String raw) {
    final vin = normalize(raw);
    if (vin.isEmpty) return null;
    if (vin.length != requiredLength) {
      return 'VIN введён неправильно: нужно $requiredLength знаков (сейчас ${vin.length})';
    }
    if (!allowed.hasMatch(vin)) {
      return 'VIN введён неправильно: недопустимые символы (нельзя I, O, Q)';
    }
    return null;
  }
}
