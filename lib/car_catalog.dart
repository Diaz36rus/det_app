import 'car_brands.dart';

/// Каталог марок/моделей для автоподстановки.
/// В БД по-прежнему одно поле `make_model` = «Марка Модель».
class CarCatalog {
  CarCatalog._();

  static final List<String> brands = () {
    final set = <String>{...CarBrands.allDisplayNames(), ..._extraBrands};
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return List<String>.unmodifiable(list);
  }();

  static const _extraBrands = <String>[
    'Evolute',
    'Skywell',
    'KGM',
    'Sollers',
    'Москвич',
  ];

  /// Популярные модели (RU-рынок / детейлинг). Ключ — нормализованная марка.
  static const Map<String, List<String>> _models = {
    'toyota': [
      'Camry', 'Corolla', 'RAV4', 'Land Cruiser', 'Land Cruiser Prado', 'Highlander',
      'Hilux', 'Fortuner', 'Alphard', 'Yaris', 'C-HR', 'Avalon', 'Sequoia', 'Tundra',
      '4Runner', 'Prius', 'Venza', 'Harrier', 'Crown', 'bZ4X',
    ],
    'bmw': [
      '1 Series', '2 Series', '3 Series', '4 Series', '5 Series', '6 Series', '7 Series', '8 Series',
      'X1', 'X2', 'X3', 'X4', 'X5', 'X6', 'X7', 'XM', 'iX', 'i4', 'iX3', 'i7', 'M3', 'M5', 'Z4',
    ],
    'mercedes': [
      'A-Class', 'B-Class', 'C-Class', 'E-Class', 'S-Class', 'CLA', 'CLS', 'GLA', 'GLB', 'GLC',
      'GLE', 'GLS', 'G-Class', 'V-Class', 'Vito', 'Sprinter', 'EQA', 'EQB', 'EQC', 'EQE', 'EQS',
      'AMG GT', 'Maybach S-Class',
    ],
    'audi': [
      'A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'Q2', 'Q3', 'Q5', 'Q7', 'Q8', 'e-tron', 'Q4 e-tron',
      'e-tron GT', 'TT', 'R8', 'RS6', 'RS7', 'S5', 'SQ7',
    ],
    'volkswagen': [
      'Polo', 'Golf', 'Passat', 'Jetta', 'Arteon', 'Tiguan', 'Touareg', 'Teramont', 'Taos',
      'ID.3', 'ID.4', 'ID.6', 'Multivan', 'Caravelle', 'Transporter', 'Amarok', 'Caddy',
    ],
    'hyundai': [
      'Solaris', 'Elantra', 'Sonata', 'Accent', 'Creta', 'Tucson', 'Santa Fe', 'Palisade',
      'Staria', 'Ioniq 5', 'Ioniq 6', 'Kona', 'Venue', 'H-1', 'Porter', 'Genesis Coupe',
    ],
    'kia': [
      'Rio', 'Cerato', 'K5', 'Optima', 'Stinger', 'Sportage', 'Sorento', 'Mohave', 'Carnival',
      'Seltos', 'Soul', 'EV6', 'EV9', 'Picanto', 'Proceed', 'XCeed',
    ],
    'skoda': [
      'Octavia', 'Rapid', 'Superb', 'Kodiaq', 'Karoq', 'Kamiq', 'Fabia', 'Enyaq', 'Yeti',
    ],
    'nissan': [
      'Almera', 'Sentra', 'Teana', 'Altima', 'Qashqai', 'X-Trail', 'Murano', 'Pathfinder',
      'Patrol', 'Navara', 'Juke', 'Note', 'Leaf', 'Ariya', 'Terrano',
    ],
    'mazda': [
      '2', '3', '6', 'CX-3', 'CX-30', 'CX-5', 'CX-60', 'CX-70', 'CX-9', 'CX-90', 'MX-5', 'BT-50',
    ],
    'honda': [
      'Civic', 'Accord', 'CR-V', 'HR-V', 'Pilot', 'Pilot Hybrid', 'Odyssey', 'Ridgeline',
      'Jazz', 'Fit', 'e:NS1',
    ],
    'mitsubishi': [
      'Lancer', 'Outlander', 'ASX', 'Eclipse Cross', 'Pajero', 'Pajero Sport', 'L200',
      'Montero', 'Delica', 'Xpander',
    ],
    'subaru': [
      'Impreza', 'Legacy', 'Outback', 'Forester', 'XV', 'Crosstrek', 'Ascent', 'BRZ', 'WRX',
    ],
    'volvo': [
      'S60', 'S90', 'V60', 'V90', 'XC40', 'XC60', 'XC90', 'C40', 'EX30', 'EX90',
    ],
    'lexus': [
      'ES', 'IS', 'LS', 'GS', 'UX', 'NX', 'RX', 'GX', 'LX', 'LM', 'RC', 'LC', 'RZ',
    ],
    'infiniti': [
      'Q50', 'Q60', 'QX50', 'QX55', 'QX60', 'QX80', 'FX', 'JX', 'EX',
    ],
    'porsche': [
      '911', 'Cayenne', 'Macan', 'Panamera', 'Taycan', 'Boxster', 'Cayman', '718',
    ],
    'landrover': [
      'Range Rover', 'Range Rover Sport', 'Range Rover Velar', 'Range Rover Evoque',
      'Discovery', 'Discovery Sport', 'Defender', 'Freelander',
    ],
    'jeep': [
      'Wrangler', 'Grand Cherokee', 'Cherokee', 'Compass', 'Renegade', 'Gladiator', 'Wagoneer',
    ],
    'ford': [
      'Focus', 'Fiesta', 'Mondeo', 'Mustang', 'Explorer', 'Escape', 'Kuga', 'Edge',
      'Expedition', 'F-150', 'Ranger', 'Transit', 'Bronco', 'Mach-E',
    ],
    'chevrolet': [
      'Cruze', 'Malibu', 'Aveo', 'Cobalt', 'Lacetti', 'Captiva', 'Tracker', 'Trailblazer',
      'Tahoe', 'Suburban', 'Equinox', 'Traverse', 'Blazer', 'Camaro', 'Corvette', 'Silverado',
      'Niva', 'Orlando', 'Spark', 'Epica',
    ],
    'geely': [
      'Coolray', 'Atlas', 'Atlas Pro', 'Monjaro', 'Okavango', 'Preface', 'Emgrand', 'Cityray',
      'Galaxy L7', 'Tugella', 'Geometry C', 'Xingyue',
    ],
    'chery': [
      'Tiggo 4', 'Tiggo 4 Pro', 'Tiggo 7', 'Tiggo 7 Pro', 'Tiggo 8', 'Tiggo 8 Pro',
      'Tiggo 8 Pro Max', 'Arrizo 8', 'Arrizo 5', 'Exeed TXL',
    ],
    'haval': [
      'Jolion', 'F7', 'F7x', 'H6', 'H9', 'Dargo', 'Dargo X', 'M6', 'H5', 'Cool Dog',
    ],
    'gwm': [
      'Poer', 'Wingle', 'Tank 300', 'Tank 500', 'Ora',
    ],
    'tank': ['300', '400', '500', '700'],
    'changan': [
      'CS35 Plus', 'CS55 Plus', 'CS75 Plus', 'CS95', 'Uni-T', 'Uni-K', 'Uni-V', 'Alsvin', 'Hunter',
    ],
    'exeed': ['TXL', 'VX', 'RX', 'LX'],
    'omoda': ['C5', 'S5', 'E5'],
    'jaecoo': ['J7', 'J8'],
    'byd': [
      'Song Plus', 'Han', 'Tang', 'Seal', 'Sealion 7', 'Atto 3', 'Yuan Plus', 'Dolphin', 'Qin Plus',
    ],
    'zeekr': ['001', '007', '009', 'X', '7X'],
    'li': ['L6', 'L7', 'L8', 'L9', 'Mega'],
    'lada': [
      'Vesta', 'Vesta SW', 'Vesta Cross', 'Granta', 'Granta Cross', 'Niva Travel', 'Niva Legend',
      'Largus', 'XRAY', 'Priora', 'Kalina', '4x4',
    ],
    'uaz': ['Patriot', 'Hunter', 'Pickup', 'Bukhanka', 'Profi', 'SGR'],
    'gaz': ['Gazelle', 'Gazelle Next', 'Sobol', 'Valdai', 'Next'],
    'renault': [
      'Logan', 'Sandero', 'Sandero Stepway', 'Duster', 'Kaptur', 'Arkana', 'Megane', 'Fluence',
      'Koleos', 'Scenic', 'Trafic', 'Master',
    ],
    'peugeot': [
      '208', '308', '408', '508', '2008', '3008', '5008', 'Partner', 'Traveller', 'Boxer',
    ],
    'citroen': [
      'C3', 'C4', 'C5 Aircross', 'Berlingo', 'Jumpy', 'Jumper', 'C-Elysee',
    ],
    'opel': [
      'Astra', 'Corsa', 'Insignia', 'Crossland', 'Grandland', 'Mokka', 'Zafira', 'Vivaro', 'Movano',
    ],
    'suzuki': [
      'Swift', 'Vitara', 'Grand Vitara', 'SX4', 'Jimny', 'S-Cross', 'Baleno', 'Ignis',
    ],
    'ssangyong': [
      'Rexton', 'Kyron', 'Actyon', 'Korando', 'Tivoli', 'Musso', 'Torres',
    ],
    'genesis': ['G70', 'G80', 'G90', 'GV60', 'GV70', 'GV80'],
    'cadillac': ['CT4', 'CT5', 'XT4', 'XT5', 'XT6', 'Escalade', 'Lyriq'],
    'dodge': ['Challenger', 'Charger', 'Durango', 'Ram', 'Hornet'],
    'ram': ['1500', '2500', '3500', 'ProMaster'],
    'tesla': ['Model 3', 'Model Y', 'Model S', 'Model X', 'Cybertruck'],
    'hongqi': ['H5', 'H9', 'HS5', 'HS7', 'E-HS9'],
    'jetour': ['Dashing', 'X70', 'X70 Plus', 'X90 Plus', 'T2'],
    'dongfeng': ['Aeolus', 'Shine', 'Rich', 'Box'],
    'faw': ['Bestune T77', 'Bestune T99', 'Hongqi'],
    'aito': ['M5', 'M7', 'M9'],
    'voyah': ['Free', 'Passion', 'Dream'],
    'nio': ['ET5', 'ET7', 'ES6', 'ES8', 'EC6', 'EC7'],
    'xpeng': ['G6', 'G9', 'P7', 'P5'],
    'leapmotor': ['C10', 'C11', 'T03'],
    'jac': ['JS4', 'JS6', 'T6', 'T8', 'S3'],
    'mg': ['ZS', 'HS', '5', '4', 'Marvel R', 'Cyberster'],
    'mini': ['Cooper', 'Countryman', 'Clubman', 'Paceman'],
    'smart': ['#1', '#3', 'Fortwo', 'Forfour'],
    'jaguar': ['XE', 'XF', 'F-Pace', 'E-Pace', 'I-Pace', 'F-Type'],
    'bentley': ['Continental GT', 'Flying Spur', 'Bentayga'],
    'maserati': ['Ghibli', 'Quattroporte', 'Levante', 'Grecale', 'MC20'],
    'ferrari': ['Roma', 'Portofino', 'F8', 'SF90', '296', 'Purosangue'],
    'lamborghini': ['Urus', 'Huracán', 'Revuelto', 'Aventador'],
    'astonmartin': ['DB11', 'DB12', 'Vantage', 'DBX', 'DBS'],
    'rollsroyce': ['Ghost', 'Phantom', 'Cullinan', 'Spectre', 'Wraith'],
    'mclaren': ['720S', 'Artura', 'GT', '765LT'],
    'lotus': ['Emira', 'Eletre', 'Emeya'],
    'polestar': ['2', '3', '4'],
    'lucid': ['Air', 'Gravity'],
    'rivian': ['R1T', 'R1S'],
    'cupra': ['Formentor', 'Leon', 'Ateca', 'Born', 'Tavascan'],
    'seat': ['Leon', 'Ibiza', 'Ateca', 'Arona', 'Tarraco'],
    'dacia': ['Duster', 'Logan', 'Sandero', 'Jogger', 'Spring'],
    'isuzu': ['D-Max', 'MU-X'],
    'baic': ['X55', 'BJ40', 'BJ60', 'U5'],
    'gac': ['GS3', 'GS8', 'M8', 'Aion'],
    'avatr': ['11', '12'],
    'belgee': ['X50', 'X70'],
    'kaiyi': ['X3', 'X7', 'E5'],
    'livan': ['X3 Pro', 'S6 Pro', '7'],
    'aurus': ['Senat', 'Komendant'],
    'moskvich': ['3', '3e', '6', '8'],
    'evolute': ['i-Joy', 'i-Pro', 'i-Space', 'i-Jet'],
    'skywell': ['ET5', 'HT-i'],
    'hummer': ['H2', 'H3', 'EV'],
    'lincoln': ['Navigator', 'Aviator', 'Nautilus', 'Corsair'],
    'buick': ['Enclave', 'Encore', 'Envision'],
    'gmc': ['Yukon', 'Sierra', 'Terrain', 'Acadia'],
    'chrysler': ['Pacifica', '300'],
    'alfa': ['Giulia', 'Stelvio', 'Tonale'],
    'fiat': ['500', 'Tipo', 'Panda', 'Doblo', 'Ducato'],
    'abarth': ['595', '124 Spider'],
    'lancia': ['Ypsilon', 'Delta'],
    'daihatsu': ['Terios', 'Rocky', 'Sirion'],
    'saab': ['9-3', '9-5'],
    'acura': ['MDX', 'RDX', 'TLX', 'Integra'],
  };

  static String join(String make, String model) {
    final m = make.trim();
    final mod = model.trim();
    if (m.isEmpty) return mod;
    if (mod.isEmpty) return m;
    return '$m $mod';
  }

  static ({String make, String model}) split(String? makeModel) {
    final raw = (makeModel ?? '').trim();
    if (raw.isEmpty) return (make: '', model: '');

    final slug = CarBrands.slugFor(raw);
    if (slug != null) {
      final aliases = [
        CarBrands.displayNameForSlug(slug),
        ...CarBrands.aliasesForSlug(slug),
      ]..sort((a, b) => b.length.compareTo(a.length));

      final lower = raw.toLowerCase();
      for (final a in aliases) {
        final al = a.toLowerCase().trim();
        if (al.isEmpty) continue;
        if (lower == al) {
          return (make: CarBrands.displayNameForSlug(slug), model: '');
        }
        if (lower.startsWith('$al ') || lower.startsWith('$al-')) {
          final model = raw.substring(al.length).trim().replaceFirst(RegExp(r'^[\s/\-]+'), '');
          return (make: CarBrands.displayNameForSlug(slug), model: model);
        }
      }
    }

    final parts = raw.split(RegExp(r'\s+'));
    if (parts.length == 1) return (make: parts.first, model: '');
    return (make: parts.first, model: parts.skip(1).join(' '));
  }

  static String? _slugKey(String make) {
    final slug = CarBrands.slugFor(make.trim());
    if (slug != null) return slug;
    final n = make.toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r'[^a-zа-я0-9]+'), '');
    return n.isEmpty ? null : n;
  }

  static List<String> modelsFor(String make, {Iterable<String> extra = const []}) {
    final key = _slugKey(make);
    final base = key == null ? const <String>[] : (_models[key] ?? const <String>[]);
    final set = <String>{...base, ...extra.where((e) => e.trim().isNotEmpty)};
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  /// Ключ для карты «марка → модели из заказов»: slug или нормализованное имя.
  static String extrasKey(String make) {
    final slug = CarBrands.slugFor(make.trim());
    if (slug != null) return slug;
    return make
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[^a-zа-я0-9]+'), '');
  }

  /// Из строк `make_model` собирает марки и модели **по маркам** (не общий пул).
  static ({List<String> makes, Map<String, List<String>> modelsByMake}) extrasFromMakeModels(
    Iterable<String> rows,
  ) {
    final makes = <String>{};
    final byMake = <String, Set<String>>{};
    for (final row in rows) {
      final parts = split(row);
      if (parts.make.isEmpty) continue;
      makes.add(parts.make);
      if (parts.model.isEmpty) continue;
      final key = extrasKey(parts.make);
      if (key.isEmpty) continue;
      byMake.putIfAbsent(key, () => <String>{}).add(parts.model);
    }
    final map = <String, List<String>>{
      for (final e in byMake.entries) e.key: (e.value.toList()..sort()),
    };
    return (makes: makes.toList()..sort(), modelsByMake: map);
  }

  static List<String> extrasForMake(
    String make,
    Map<String, List<String>> modelsByMake,
  ) {
    if (make.trim().isEmpty || modelsByMake.isEmpty) return const [];
    final key = extrasKey(make);
    if (key.isEmpty) return const [];
    return modelsByMake[key] ?? const [];
  }

  static bool modelBelongsToMake(
    String make,
    String model, {
    Map<String, List<String>> modelsByMake = const {},
  }) {
    final m = model.trim();
    if (m.isEmpty) return true;
    final list = modelsFor(make, extra: extrasForMake(make, modelsByMake));
    final lower = m.toLowerCase();
    return list.any((e) => e.toLowerCase() == lower);
  }

  static List<String> filterBrands(String query, {Iterable<String> extra = const []}) {
    final q = query.trim().toLowerCase();
    final all = <String>{...brands, ...extra};
    final list = all.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (q.isEmpty) return list; // полный список — скролл в выпадашке
    final starts = list.where((b) => b.toLowerCase().startsWith(q)).toList();
    final contains = list
        .where((b) => !b.toLowerCase().startsWith(q) && b.toLowerCase().contains(q))
        .toList();
    return [...starts, ...contains];
  }

  static List<String> filterModels(
    String make,
    String query, {
    Iterable<String> extra = const [],
    Map<String, List<String>> modelsByMake = const {},
  }) {
    if (make.trim().isEmpty) return const [];
    final fromDb = extrasForMake(make, modelsByMake);
    final mergedExtra = <String>{...extra, ...fromDb};
    final q = query.trim().toLowerCase();
    final list = modelsFor(make, extra: mergedExtra);
    if (q.isEmpty) return list;
    final starts = list.where((m) => m.toLowerCase().startsWith(q)).toList();
    final contains = list
        .where((m) => !m.toLowerCase().startsWith(q) && m.toLowerCase().contains(q))
        .toList();
    return [...starts, ...contains];
  }

  /// Короткий hint только из моделей этой марки (без чужих вроде X5 у Toyota).
  static String modelHintFor(String make) {
    if (make.trim().isEmpty) return 'Сначала марка';
    final all = modelsFor(make);
    if (all.isEmpty) return 'выберите или введите';
    // Предпочитаем «знакомые» модели, иначе первые две по алфавиту.
    const preferred = {
      'toyota': ['Camry', 'RAV4'],
      'bmw': ['X5', '3 Series'],
      'mercedes': ['E-Class', 'GLE'],
      'audi': ['A6', 'Q5'],
      'hyundai': ['Solaris', 'Tucson'],
      'kia': ['Rio', 'Sportage'],
      'lada': ['Vesta', 'Granta'],
      'haval': ['Jolion', 'F7'],
    };
    final key = _slugKey(make);
    final pick = <String>[];
    for (final p in preferred[key] ?? const <String>[]) {
      if (all.any((m) => m.toLowerCase() == p.toLowerCase())) pick.add(p);
      if (pick.length >= 2) break;
    }
    if (pick.isEmpty) pick.addAll(all.take(2));
    return 'напр. ${pick.join(', ')}';
  }
}
