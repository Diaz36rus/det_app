import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';
import 'database.dart';
import 'input_masks.dart';
import 'vin_utils.dart';

/// Найденное совпадение по телефону / госномеру / VIN.
class IdentityMatch {
  const IdentityMatch({
    required this.kind,
    required this.clientId,
    required this.clientName,
    required this.clientPhone,
    this.carId,
    this.carLabel,
    this.plate,
    this.vin,
  });

  /// phone | plate | vin
  final String kind;
  final int clientId;
  final String clientName;
  final String clientPhone;
  final int? carId;
  final String? carLabel;
  final String? plate;
  final String? vin;

  String get title {
    switch (kind) {
      case 'plate':
        return 'Госномер уже есть в базе';
      case 'vin':
        return 'VIN уже есть в базе';
      default:
        return 'Телефон уже есть в базе';
    }
  }

  String get message {
    final car = (carLabel != null && carLabel!.trim().isNotEmpty)
        ? '\nАвто: $carLabel${plate != null && plate!.isNotEmpty ? ' · $plate' : ''}'
        : (plate != null && plate!.isNotEmpty ? '\nГосномер: $plate' : '');
    final vinLine = (vin != null && vin!.isNotEmpty) ? '\nVIN: $vin' : '';
    return 'Клиент: $clientName\nТелефон: $clientPhone$car$vinLine\n\n'
        'Использовать существующую карточку? Новый дубль создавать нельзя.';
  }
}

/// Ищет конфликты идентичности. Приоритет: plate → vin → phone.
Future<IdentityMatch?> findIdentityMatch({
  String? phone,
  String? plate,
  String? vin,
  int? excludeClientId,
  int? excludeCarId,
}) async {
  final db = DatabaseHelper();
  final plateKey = plate == null || plate.trim().isEmpty
      ? ''
      : PlateMaskFormatter.canonicalKey(plate);
  final vinKey = vin == null || vin.trim().isEmpty ? '' : VinUtils.normalize(vin);
  final phoneDigits = phone == null || phone.trim().isEmpty
      ? ''
      : DatabaseHelper.phoneDigits10(phone);

  if (plateKey.isNotEmpty) {
    final car = await db.findCarByPlateKey(plateKey);
    if (car != null) {
      final carId = (car['id'] as num).toInt();
      if (excludeCarId == null || carId != excludeCarId) {
        final clientId = (car['client_id'] as num).toInt();
        final client = await db.getClientById(clientId);
        return IdentityMatch(
          kind: 'plate',
          clientId: clientId,
          clientName: client?['name']?.toString() ?? '—',
          clientPhone: client?['phone']?.toString() ?? '',
          carId: carId,
          carLabel: car['make_model']?.toString(),
          plate: car['plate']?.toString(),
          vin: car['vin']?.toString(),
        );
      }
    }
  }

  if (vinKey.isNotEmpty) {
    final car = await db.findCarByVin(vinKey);
    if (car != null) {
      final carId = (car['id'] as num).toInt();
      if (excludeCarId == null || carId != excludeCarId) {
        final clientId = (car['client_id'] as num).toInt();
        final client = await db.getClientById(clientId);
        return IdentityMatch(
          kind: 'vin',
          clientId: clientId,
          clientName: client?['name']?.toString() ?? '—',
          clientPhone: client?['phone']?.toString() ?? '',
          carId: carId,
          carLabel: car['make_model']?.toString(),
          plate: car['plate']?.toString(),
          vin: car['vin']?.toString(),
        );
      }
    }
  }

  if (phoneDigits.length == 10) {
    final client = await db.getClientByPhone('+7$phoneDigits');
    if (client != null) {
      final clientId = (client['id'] as num).toInt();
      if (excludeClientId == null || clientId != excludeClientId) {
        return IdentityMatch(
          kind: 'phone',
          clientId: clientId,
          clientName: client['name']?.toString() ?? '—',
          clientPhone: client['phone']?.toString() ?? '',
        );
      }
    }
  }

  return null;
}

/// Диалог: использовать существующее / отмена.
/// Возвращает match если пользователь согласен, null если отмена.
Future<IdentityMatch?> confirmIdentityReuse(
  BuildContext context,
  IdentityMatch match,
) async {
  final use = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(match.title, style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
      content: Text(
        match.message,
        style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.35),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Использовать'),
        ),
      ],
    ),
  );
  return use == true ? match : null;
}
