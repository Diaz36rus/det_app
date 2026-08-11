import 'package:flutter_test/flutter_test.dart';
import 'package:det_app/app_version.dart';

void main() {
  test('AppVersion schema is defined', () {
    expect(AppVersion.dbSchema, greaterThan(0));
  });
}
