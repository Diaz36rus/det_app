import 'package:flutter/material.dart';

/// Часть схемы авто. Координаты [path] нормализованы 0..1 относительно холста.
class VehiclePart {
  final String id;
  final String quoteId;
  final String label;
  final List<Offset> path;

  const VehiclePart({
    required this.id,
    required this.quoteId,
    required this.label,
    required this.path,
  });
}

/// Человекочитаемые названия позиций сметы тонировки.
const Map<String, String> tintQuoteLabels = {
  'windshield': 'Лобовое стекло',
  'front_sides': 'Передние боковые',
  'rear_sides': 'Задние боковые',
  'rear': 'Заднее стекло',
};
