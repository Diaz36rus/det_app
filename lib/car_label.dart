/// Подпись авто: марка · номер · год (если задан).
String carYearBit(Object? year) {
  final y = year is num ? year.toInt() : int.tryParse('$year') ?? 0;
  return y > 0 ? ' · $y' : '';
}

String formatCarMakePlate(
  Map<String, dynamic> car, {
  String sep = ' · ',
}) {
  final make = car['make_model']?.toString() ?? '';
  final plate = car['plate']?.toString() ?? '';
  return '$make$sep$plate${carYearBit(car['year'])}';
}
