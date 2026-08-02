import 'package:flutter/material.dart';
import 'vehicle_part.dart';

/// Схема тонировки: вид сверху среднего седана (нос сверху).
/// Полигоны совпадают с отрисовкой в [VehicleSchemaView].
class TintTopSchema {
  TintTopSchema._();

  static const List<VehiclePart> parts = [
    // Лобовое — широкая трапеция у A-стоек
    VehiclePart(
      id: 'windshield',
      quoteId: 'windshield',
      label: 'Лобовое',
      path: [
        Offset(0.295, 0.248),
        Offset(0.705, 0.248),
        Offset(0.765, 0.348),
        Offset(0.235, 0.348),
      ],
    ),
    // Передние боковые
    VehiclePart(
      id: 'front_left',
      quoteId: 'front_sides',
      label: 'Переднее левое',
      path: [
        Offset(0.138, 0.358),
        Offset(0.248, 0.358),
        Offset(0.242, 0.508),
        Offset(0.132, 0.508),
      ],
    ),
    VehiclePart(
      id: 'front_right',
      quoteId: 'front_sides',
      label: 'Переднее правое',
      path: [
        Offset(0.752, 0.358),
        Offset(0.862, 0.358),
        Offset(0.868, 0.508),
        Offset(0.758, 0.508),
      ],
    ),
    // Задние боковые
    VehiclePart(
      id: 'rear_left',
      quoteId: 'rear_sides',
      label: 'Заднее левое',
      path: [
        Offset(0.135, 0.528),
        Offset(0.245, 0.528),
        Offset(0.255, 0.668),
        Offset(0.152, 0.668),
      ],
    ),
    VehiclePart(
      id: 'rear_right',
      quoteId: 'rear_sides',
      label: 'Заднее правое',
      path: [
        Offset(0.755, 0.528),
        Offset(0.865, 0.528),
        Offset(0.848, 0.668),
        Offset(0.745, 0.668),
      ],
    ),
    // Заднее стекло
    VehiclePart(
      id: 'rear',
      quoteId: 'rear',
      label: 'Заднее',
      path: [
        Offset(0.265, 0.682),
        Offset(0.735, 0.682),
        Offset(0.685, 0.778),
        Offset(0.315, 0.778),
      ],
    ),
  ];
}
