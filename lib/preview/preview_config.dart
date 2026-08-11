import 'package:flutter/material.dart';

/// Ракурс камеры. Те же id потом станут позициями орбиты в 3D.
enum PreviewCamera {
  side,
  rearQuarter,
  frontQuarter,
}

extension PreviewCameraX on PreviewCamera {
  String get id => switch (this) {
        PreviewCamera.side => 'side',
        PreviewCamera.rearQuarter => 'rear_quarter',
        PreviewCamera.frontQuarter => 'front_quarter',
      };

  String get label => switch (this) {
        PreviewCamera.side => 'Бок',
        PreviewCamera.rearQuarter => '¾ сзади',
        PreviewCamera.frontQuarter => '¾ спереди',
      };
}

/// Обработка хрома (не путать с % тонировки стёкол).
enum PreviewChrome {
  stock,
  antichrome,
  tint50,
  tint35,
}

extension PreviewChromeX on PreviewChrome {
  String get id => switch (this) {
        PreviewChrome.stock => 'stock',
        PreviewChrome.antichrome => 'antichrome',
        PreviewChrome.tint50 => 'tint50',
        PreviewChrome.tint35 => 'tint35',
      };

  String get label => switch (this) {
        PreviewChrome.stock => 'Оригинал',
        PreviewChrome.antichrome => 'Антихром',
        PreviewChrome.tint50 => 'Притемнение 50%',
        PreviewChrome.tint35 => 'Притемнение 35%',
      };

  String get shortLabel => switch (this) {
        PreviewChrome.stock => 'Оригинал',
        PreviewChrome.antichrome => 'Антихром',
        PreviewChrome.tint50 => '50%',
        PreviewChrome.tint35 => '35%',
      };

  /// 0 = без затемнения (stock), 1 = полный антихром.
  double get darkenAmount => switch (this) {
        PreviewChrome.stock => 0,
        PreviewChrome.tint35 => 0.35,
        PreviewChrome.tint50 => 0.50,
        PreviewChrome.antichrome => 1.0,
      };
}

/// Единый конфиг превью — общий для 2D-ракурсов и будущего GLB-рендера.
class PreviewConfig {
  /// Тип кузова: generic_sedan → позже sedan/suv/…
  final String bodyStyleId;

  /// Конкретная модель: null = generic, позже toyota_camry и т.п.
  final String? vehicleId;

  final Color bodyColor;
  final PreviewChrome chrome;
  final PreviewCamera camera;

  const PreviewConfig({
    this.bodyStyleId = 'generic_sedan',
    this.vehicleId,
    required this.bodyColor,
    this.chrome = PreviewChrome.stock,
    this.camera = PreviewCamera.side,
  });

  PreviewConfig copyWith({
    String? bodyStyleId,
    String? vehicleId,
    bool clearVehicleId = false,
    Color? bodyColor,
    PreviewChrome? chrome,
    PreviewCamera? camera,
  }) {
    return PreviewConfig(
      bodyStyleId: bodyStyleId ?? this.bodyStyleId,
      vehicleId: clearVehicleId ? null : (vehicleId ?? this.vehicleId),
      bodyColor: bodyColor ?? this.bodyColor,
      chrome: chrome ?? this.chrome,
      camera: camera ?? this.camera,
    );
  }

  /// Каталог ассетов: assets/preview/vehicles/{bodyStyleId}/…
  String get assetRoot => 'assets/preview/vehicles/$bodyStyleId';
}

/// Стартовая палитра «вау»-цветов плёнки/кузова.
const List<({String name, Color color})> kPreviewBodyColors = [
  (name: 'Чёрный', color: Color(0xFF1A1A1A)),
  (name: 'Белый', color: Color(0xFFF2F2F2)),
  (name: 'Серый', color: Color(0xFF6B7280)),
  (name: 'Серебро', color: Color(0xFFC0C4CC)),
  (name: 'Синий', color: Color(0xFF1E3A8A)),
  (name: 'Красный', color: Color(0xFFB91C1C)),
  (name: 'Зелёный', color: Color(0xFF166534)),
  (name: 'Бордо', color: Color(0xFF7F1D1D)),
  (name: 'Бежевый', color: Color(0xFFD6C3A8)),
  (name: 'Оранжевый', color: Color(0xFFEA580C)),
];
