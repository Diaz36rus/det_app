import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:det_app/car_brands.dart';
import 'package:det_app/car_catalog.dart';

void main() {
  group('CarCatalog join/split', () {
    test('join make+model', () {
      expect(CarCatalog.join('Toyota', 'Camry'), 'Toyota Camry');
      expect(CarCatalog.join('BMW', ''), 'BMW');
      expect(CarCatalog.join('', 'X5'), 'X5');
    });

    test('split known multi-word brands', () {
      final lr = CarCatalog.split('Land Rover Discovery');
      expect(lr.make, 'Land Rover');
      expect(lr.model, 'Discovery');

      final rr = CarCatalog.split('Range Rover Sport');
      expect(rr.make, 'Land Rover');
      expect(rr.model.toLowerCase(), contains('sport'));

      final li = CarCatalog.split('Li Auto L9');
      expect(CarBrands.slugFor(li.make), 'li');
      expect(li.model, 'L9');

      final bmw = CarCatalog.split('BMW X5');
      expect(bmw.make, 'BMW');
      expect(bmw.model, 'X5');

      final toyota = CarCatalog.split('Toyota Camry');
      expect(toyota.make, 'Toyota');
      expect(toyota.model, 'Camry');
    });

    test('split unknown falls back to first word', () {
      final u = CarCatalog.split('MyCustomBrand Super');
      expect(u.make, 'MyCustomBrand');
      expect(u.model, 'Super');
    });

    test('round-trip known brands', () {
      for (final raw in [
        'Toyota Camry',
        'BMW X5',
        'Mercedes C-Class',
        'Audi Q7',
        'Haval Jolion',
        'Zeekr 001',
        'Lada Vesta',
      ]) {
        final p = CarCatalog.split(raw);
        final joined = CarCatalog.join(p.make, p.model);
        expect(CarBrands.slugFor(joined), CarBrands.slugFor(raw), reason: raw);
      }
    });
  });

  group('CarCatalog filter', () {
    test('brands filter by prefix', () {
      final hits = CarCatalog.filterBrands('toy');
      expect(hits.any((b) => b.toLowerCase().startsWith('toy')), isTrue);
    });

    test('models for toyota include Camry', () {
      final models = CarCatalog.modelsFor('Toyota');
      expect(models, contains('Camry'));
      expect(models, contains('RAV4'));
    });

    test('manual extra make/model allowed', () {
      final brands = CarCatalog.filterBrands('uniq', extra: ['UniqBrand']);
      expect(brands, contains('UniqBrand'));
      final models = CarCatalog.modelsFor('Toyota', extra: ['MySpecial']);
      expect(models, contains('MySpecial'));
    });
  });

  group('CarBrands', () {
    test('slugFor Cyrillic aliases', () {
      expect(CarBrands.slugFor('Тойота Camry'), 'toyota');
      expect(CarBrands.slugFor('БМВ X5'), 'bmw');
      expect(CarBrands.slugFor('Хавал Jolion'), 'haval');
    });

    test('assetPathFor returns existing file', () {
      final brandsDir = Directory('assets/brands');
      expect(brandsDir.existsSync(), isTrue);

      final samples = [
        'Toyota',
        'BMW',
        'Mercedes',
        'Audi',
        'Haval',
        'Tank',
        'Zeekr',
        'Li Auto',
        'Jaecoo',
        'Changan',
      ];
      for (final name in samples) {
        final path = CarBrands.assetPathFor(name);
        expect(path, isNotNull, reason: name);
        final file = File(path!);
        expect(file.existsSync(), isTrue, reason: '$name → $path');
      }
    });

    test('all mapped asset files exist', () {
      final missing = <String>[];
      for (final name in CarBrands.allDisplayNames()) {
        final path = CarBrands.assetPathFor(name);
        if (path == null) {
          missing.add('$name (no path)');
          continue;
        }
        if (!File(path).existsSync()) {
          missing.add('$name → $path');
        }
      }
      expect(missing, isEmpty, reason: 'missing assets:\n${missing.join('\n')}');
    });
  });
}
