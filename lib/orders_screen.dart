import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'car_catalog.dart';
import 'car_make_model_fields.dart';
import 'app_datetime.dart';
import 'app_menu.dart';
import 'app_theme.dart';
import 'app_toast.dart';
import 'database.dart';
import 'duplicate_guard.dart';
import 'input_masks.dart';
import 'master_picker.dart';
import 'quick_datetime_picker.dart';
import 'responsive.dart';
import 'schedule_conflict.dart';
import 'service_category_gallery.dart';
import 'tour_keys.dart';
import 'ui_kit.dart';
import 'vin_utils.dart';
import 'order_templates.dart';
import 'wrap_catalog.dart';

class OrdersScreen extends StatefulWidget {
  final DateTime? initialDate;
  final TimeOfDay? initialTime;
  final ValueChanged<int>? onNavigateMenu;
  final VoidCallback? onOrderCreated;

  const OrdersScreen({
    super.key,
    this.initialDate,
    this.initialTime,
    this.onNavigateMenu,
    this.onOrderCreated,
  });

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _phoneController = TextEditingController(text: PhonePlus7Formatter.prefix);
  final _nameController = TextEditingController();
  final _plateController = TextEditingController();
  final _vinController = TextEditingController();
  final _priceController = TextEditingController(text: "0");
  String _carMakeModel = '';
  final _carFieldsKey = GlobalKey<CarMakeModelFieldsState>();
  List<String> _extraMakes = const [];
  List<String> _extraModels = const [];
  String _selectedCarCategory = "1";
  List<Map<String, dynamic>> _services = [];
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;

  final List<Map<String, dynamic>> _cart = [];
  double _total = 0;
  String _statusMessage = "";
  Color _statusColor = AppColors.danger;
  List<Map<String, dynamic>> _clientCars = [];
  int? _selectedClientCarId;
  int? _knownClientId;
  String? _vinWarning;
  List<Map<String, dynamic>> _plateHistory = [];
  int _plateLookupGen = 0;

  DateTime get _startDateTime => DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

  DateTime get _endDateTime => DateTime(
        _endDate.year,
        _endDate.month,
        _endDate.day,
        _endTime.hour,
        _endTime.minute,
      );

  void _ensureEndAfterStart() {
    if (_endDateTime.isAfter(_startDateTime)) return;
    var candidate = _startDateTime.add(const Duration(hours: 8));
    _endDate = DateTime(candidate.year, candidate.month, candidate.day);
    _endTime = TimeOfDay(hour: candidate.hour.clamp(0, 22), minute: 0);
    if (!_endDateTime.isAfter(_startDateTime)) {
      candidate = _startDateTime.add(const Duration(days: 1));
      _endDate = DateTime(candidate.year, candidate.month, candidate.day);
      _endTime = const TimeOfDay(hour: 12, minute: 0);
    }
  }

  Future<void> _pickDate() async {
    final picked = await QuickDateTimePicker.pickDate(context, initial: _selectedDate);
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _ensureEndAfterStart();
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await QuickDateTimePicker.pickTime(context, initial: _selectedTime);
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
        _ensureEndAfterStart();
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await QuickDateTimePicker.pickDate(context, initial: _endDate);
    if (picked != null) {
      setState(() {
        _endDate = picked;
        _ensureEndAfterStart();
      });
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await QuickDateTimePicker.pickTime(context, initial: _endTime);
    if (picked != null) {
      setState(() {
        _endTime = picked;
        _ensureEndAfterStart();
      });
    }
  }

  void _onVinChanged() {
    final warning = VinUtils.validate(_vinController.text);
    if (warning == _vinWarning) return;
    setState(() => _vinWarning = warning);
  }

  Future<void> _onPlateChanged() async {
    final plate = PlateMaskFormatter.normalize(_plateController.text);
    final gen = ++_plateLookupGen;
    if (plate.length < 6) {
      if (_plateHistory.isNotEmpty) setState(() => _plateHistory = []);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted || gen != _plateLookupGen) return;
    final hist = await DatabaseHelper().getOrdersByPlate(plate);
    if (!mounted || gen != _plateLookupGen) return;
    setState(() => _plateHistory = hist);
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = widget.initialDate ?? DateTime(now.year, now.month, now.day);
    _selectedTime = widget.initialTime ?? const TimeOfDay(hour: 9, minute: 0);
    _endDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    _endTime = const TimeOfDay(hour: 18, minute: 0);
    _ensureEndAfterStart();
    _vinController.addListener(_onVinChanged);
    _plateController.addListener(_onPlateChanged);
    _loadServices();
    _loadCarCatalogExtras();
  }

  Future<void> _loadCarCatalogExtras() async {
    final rows = await DatabaseHelper().distinctCarMakeModels();
    if (!mounted) return;
    final makes = <String>{};
    final models = <String>{};
    for (final row in rows) {
      final parts = CarCatalog.split(row);
      if (parts.make.isNotEmpty) makes.add(parts.make);
      if (parts.model.isNotEmpty) models.add(parts.model);
    }
    setState(() {
      _extraMakes = makes.toList()..sort();
      _extraModels = models.toList()..sort();
    });
  }

  void _setCarMakeModel(String value) {
    _carMakeModel = value.trim();
    _carFieldsKey.currentState?.setMakeModel(_carMakeModel);
  }

  @override
  void dispose() {
    _vinController.removeListener(_onVinChanged);
    _plateController.removeListener(_onPlateChanged);
    _phoneController.dispose();
    _nameController.dispose();
    _plateController.dispose();
    _vinController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    final data = await DatabaseHelper().getAllServices();
    setState(() => _services = data);
  }

  void _addToCart(String name, double price, [String category = ""]) {
    setState(() {
      _cart.add({
        "name": name,
        "price": price,
        "category": category,
        "workshop": workshopForService(category: category, name: name),
      });
      _total += price;
    });
  }

  void _toggleCart(String name, double price, [String category = ""]) {
    final idx = _cart.indexWhere((e) => e['name'] == name);
    if (idx >= 0) {
      _removeFromCart(idx);
    } else {
      _addToCart(name, price, category);
    }
  }

  void _removeFromCart(int index) {
    setState(() {
      _total -= (_cart[index]['price'] as num?)?.toDouble() ?? 0;
      _cart.removeAt(index);
      if (_total < 0) _total = 0;
    });
  }

  void _recalcCartTotal() {
    _total = _cart.fold(0.0, (sum, e) => sum + ((e['price'] as num?)?.toDouble() ?? 0));
  }

  /// Пакет оклейки из оверлея картинки: зоны + одна сумма.
  void _applyWrapPackage(WrapPackageDraft draft) {
    setState(() {
      _cart.removeWhere((e) {
        final name = e['name']?.toString();
        final cat = e['category']?.toString();
        return isWrapPackageHeader(name) ||
            isWrapPackageLine(category: cat, name: name) ||
            e['wrapZones'] != null;
      });
      if (draft.zoneNames.isNotEmpty) {
        _cart.add({
          'name': draft.zoneNames.length == 1
              ? draft.zoneNames.first
              : 'Оклейка · ${draft.zoneNames.length} поз.',
          'price': draft.packagePrice,
          'category': 'Оклейка (Пленка)',
          'workshop': 'Оклейка',
          'wrapZones': List<String>.from(draft.zoneNames),
        });
      }
      _recalcCartTotal();
    });
  }

  Set<String> get _wrapSelectedNames {
    for (final e in _cart) {
      final zones = e['wrapZones'];
      if (zones is List) {
        return zones.map((z) => z.toString()).toSet();
      }
    }
    return {
      for (final e in _cart)
        if (isWrapPackageLine(
          category: e['category']?.toString(),
          name: e['name']?.toString(),
        ))
          e['name'].toString(),
    };
  }

  double get _wrapPackagePrice {
    for (final e in _cart) {
      if (e['wrapZones'] is List) {
        return (e['price'] as num?)?.toDouble() ?? 0;
      }
    }
    return 0;
  }

  int _clientLookupGen = 0;

  Future<void> _checkClient(String phone) async {
    final normalized = PhonePlus7Formatter.normalize(phone);
    final digits = DatabaseHelper.phoneDigits10(normalized);
    if (digits.length < 10) return;

    final gen = ++_clientLookupGen;
    final client = await DatabaseHelper().getClientByPhone(normalized);
    if (!mounted || gen != _clientLookupGen) return;

    if (client != null) {
      final cars = await DatabaseHelper().getClientCarsForDropdown(normalized);
      if (!mounted || gen != _clientLookupGen) return;
      setState(() {
        // Не затираем телефон — только подтягиваем клиента.
        if (_phoneController.text != normalized) {
          _phoneController.value = TextEditingValue(
            text: normalized,
            selection: TextSelection.collapsed(offset: normalized.length),
          );
        }
        _nameController.text = client['name']?.toString() ?? '';
        _knownClientId = (client['id'] as num?)?.toInt();
        _clientCars = cars;
        _setCarMakeModel('');
        _plateController.clear();
        _vinController.clear();
        _selectedCarCategory = "1";
        _selectedClientCarId = null;
      });
    } else {
      setState(() {
        _knownClientId = null;
        _clientCars = [];
      });
    }
  }

  Future<void> _fillFromLastOrder() async {
    var clientId = _knownClientId;
    if (clientId == null) {
      final phone = PhonePlus7Formatter.normalize(_phoneController.text);
      final client = await DatabaseHelper().getClientByPhone(phone);
      clientId = (client?['id'] as num?)?.toInt();
    }
    if (clientId == null) {
      setState(() {
        _statusMessage = 'Сначала укажите телефон существующего клиента';
        _statusColor = AppColors.danger;
      });
      return;
    }
    final lines = await DatabaseHelper().getLastOrderCartLines(
      clientId: clientId,
      carId: _selectedClientCarId,
    );
    if (!mounted) return;
    if (lines.isEmpty) {
      setState(() {
        _statusMessage = 'Предыдущих заказов не найдено';
        _statusColor = AppColors.danger;
      });
      return;
    }
    setState(() {
      _cart
        ..clear()
        ..addAll(lines.map((e) => Map<String, dynamic>.from(e)));
      _recalcCartTotal();
      _priceController.text = _total == _total.roundToDouble()
          ? _total.toInt().toString()
          : _total.toStringAsFixed(0);
      _statusMessage = 'Корзина из прошлого заказа · ${lines.length} поз.';
      _statusColor = AppColors.success;
    });
  }

  Future<void> _saveOrder() async {
    final phone = PhonePlus7Formatter.normalize(_phoneController.text);
    final plate = PlateMaskFormatter.normalize(_plateController.text);
    if (phone.length < 12 || _nameController.text.isEmpty || _carMakeModel.trim().isEmpty) {
      setState(() {
        _statusMessage = "Заполните телефон (+7…), имя и авто";
        _statusColor = AppColors.danger;
      });
      return;
    }

    if (_cart.isEmpty) {
      setState(() {
        _statusMessage = "Добавьте хотя бы одну услугу в корзину";
        _statusColor = AppColors.danger;
      });
      return;
    }

    final vinWarning = VinUtils.validate(_vinController.text);
    if (vinWarning != null) {
      setState(() {
        _vinWarning = vinWarning;
        _statusMessage = vinWarning;
        _statusColor = AppColors.danger;
      });
      return;
    }

    if (plate.isEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Госномер не указан', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
          content: Text(
            'Создать заказ без госномера? Потом будет сложнее найти машину.',
            style: GoogleFonts.manrope(color: AppColors.textMuted),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Создать')),
          ],
        ),
      );
      if (go != true) return;
    }

    String fmtDb(DateTime dt) =>
        "${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} "
        "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:00";
    final startTimeStr = fmtDb(_startDateTime);
    final endTimeStr = fmtDb(_endDateTime);

    if (!mounted) return;
    final okSlot = await confirmNoScheduleConflict(
      context,
      startTime: startTimeStr,
      endTime: endTimeStr,
    );
    if (!okSlot || !mounted) return;

    final vin = VinUtils.normalize(_vinController.text);
    final identity = await findIdentityMatch(phone: phone, plate: plate, vin: vin);
    int clientId;
    int? carId = _selectedClientCarId;

    if (identity != null) {
      if (!mounted) return;
      final reused = await confirmIdentityReuse(context, identity);
      if (reused == null || !mounted) return;
      clientId = reused.clientId;
      if (reused.carId != null) {
        carId = reused.carId;
      }
      // Подставим имя существующего клиента в заказ (на случай другого ввода).
      if (_nameController.text.trim() != reused.clientName && reused.clientName.isNotEmpty) {
        _nameController.text = reused.clientName;
      }
    } else {
      var client = await DatabaseHelper().getClientByPhone(phone);
      if (client == null) {
        clientId = await DatabaseHelper().addClient(_nameController.text, phone);
      } else {
        clientId = client['id'] as int;
      }
    }

    carId ??= await DatabaseHelper().getCarId(clientId, plate);
    if (carId == null) {
      // Повторная страховка: госномер мог появиться у другого клиента между проверками.
      final plateHit = plate.isEmpty
          ? null
          : await findIdentityMatch(plate: plate, excludeClientId: clientId);
      if (plateHit != null) {
        if (!mounted) return;
        final reused = await confirmIdentityReuse(context, plateHit);
        if (reused == null || reused.carId == null) return;
        clientId = reused.clientId;
        carId = reused.carId;
      } else {
        carId = await DatabaseHelper().addCar(
          clientId,
          _carMakeModel.trim(),
          plate,
          vin: vin,
          category: _selectedCarCategory,
        );
      }
    } else {
      await DatabaseHelper().updateCar(
        carId,
        makeModel: _carMakeModel.trim(),
        plate: plate,
        vin: vin,
        category: _selectedCarCategory,
      );
    }
    final resolvedCarId = carId;
    if (resolvedCarId == null) return;

    String dueDateStr =
        "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
    String endDateStr =
        "${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}";

    // Пакет оклейки разворачиваем: зоны (price 0) + цена на первой / через накопление на шапке.
    final orderItems = <Map<String, dynamic>>[];
    for (final item in _cart) {
      final zones = item['wrapZones'];
      if (zones is List && zones.isNotEmpty) {
        final pkgPrice = (item['price'] as num?)?.toDouble() ?? 0;
        for (var i = 0; i < zones.length; i++) {
          orderItems.add({
            'name': zones[i].toString(),
            'price': i == 0 ? pkgPrice : 0,
            'category': 'Оклейка (Пленка)',
            'workshop': 'Оклейка',
          });
        }
      } else {
        orderItems.add({
          'name': item['name'],
          'price': item['price'],
          'category': item['category'],
          'workshop': item['workshop'],
        });
      }
    }

    await DatabaseHelper().addOrderWithItems(
      clientId,
      resolvedCarId,
      orderItems,
      dueDate: dueDateStr,
      startTime: startTimeStr,
      endTime: endTimeStr,
      endDate: endDateStr,
    );

    if (mounted) {
      final masters = await DatabaseHelper().getAllMastersFull();
      final missing = workshopsWithoutMasters(
        orderItems.map((i) => i['workshop']?.toString()),
        masters,
      );
      if (mounted && missing.isNotEmpty) {
        showAppToast(context, missingMastersMessage(missing));
      }
    }

    setState(() {
      _statusMessage = "Заказ создан";
      _statusColor = AppColors.success;
      _phoneController.text = PhonePlus7Formatter.prefix;
      _nameController.clear();
      _setCarMakeModel('');
      _plateController.clear();
      _vinController.clear();
      _vinWarning = null;
      _priceController.text = "0";
      _cart.clear();
      _total = 0;
      _selectedClientCarId = null;
      _clientCars = [];
    });
    _loadCarCatalogExtras();
    if (!mounted) return;
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Заказ создан', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: Text(
          'Что дальше?',
          style: GoogleFonts.manrope(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'stay'), child: const Text('Ещё заказ')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'calendar'), child: const Text('Календарь')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, 'kanban'), child: const Text('На доску')),
        ],
      ),
    );
    if (!mounted) return;
    if (next == 'kanban') widget.onNavigateMenu?.call(AppMenuIds.board);
    if (next == 'calendar') widget.onNavigateMenu?.call(AppMenuIds.calendar);
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
    IconData? icon,
    String? subtitle,
    Widget? trailing,
    bool expand = false,
    EdgeInsetsGeometry bodyPadding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  }) {
    return Container(
      decoration: AppTheme.panelDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 20, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTheme.sectionTitle),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle, style: AppTheme.pageSubtitle),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
          if (expand)
            Expanded(child: Padding(padding: bodyPadding, child: child))
          else
            Padding(padding: bodyPadding, child: child),
        ],
      ),
    );
  }

  Widget _dateTimeChip({
    required IconData icon,
    required String value,
    required Color accent,
    required VoidCallback onTap,
    String? label,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: AppTheme.interactiveDecoration(accent: accent, emphasized: true),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (label != null)
                      Text(label.toUpperCase(), style: AppTheme.sectionLabel),
                    Text(
                      value,
                      style: GoogleFonts.manrope(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
          decoration: BoxDecoration(
            color: AppColors.bg.withOpacity(0.55),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.manrope(
                  color: AppColors.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      "${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}";

  String _fmtTime(TimeOfDay t) =>
      "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";

  Widget _phoneField() => TextField(
        key: const ValueKey('order_client_phone'),
        controller: _phoneController,
        decoration: const InputDecoration(
          labelText: "Телефон",
          hintText: "+7XXXXXXXXXX",
          isDense: true,
        ),
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.telephoneNumber],
        inputFormatters: [PhonePlus7Formatter()],
        onChanged: _checkClient,
        onEditingComplete: () {
          _checkClient(_phoneController.text);
          FocusScope.of(context).nextFocus();
        },
      );

  Widget _nameField() => TextField(
        key: const ValueKey('order_client_name'),
        controller: _nameController,
        decoration: const InputDecoration(labelText: "Имя клиента", isDense: true),
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
      );

  Widget _carField({bool stacked = false}) => CarMakeModelFields(
        key: _carFieldsKey,
        initialMakeModel: _carMakeModel,
        stacked: stacked,
        extraMakes: _extraMakes,
        extraModels: _extraModels,
        makeFieldKey: const ValueKey('order_client_make'),
        modelFieldKey: const ValueKey('order_client_model'),
        onChanged: (v) {
          if (_carMakeModel == v) return;
          setState(() => _carMakeModel = v);
        },
      );

  Widget _plateField() => TextField(
        key: const ValueKey('order_client_plate'),
        controller: _plateController,
        decoration: const InputDecoration(
          labelText: "Госномер",
          hintText: "A123BC777",
          isDense: true,
        ),
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.next,
        inputFormatters: [PlateMaskFormatter()],
        onChanged: (_) => setState(() {}),
      );

  Widget _vinField() => TextField(
        key: const ValueKey('order_client_vin'),
        controller: _vinController,
        decoration: InputDecoration(
          labelText: "VIN",
          isDense: true,
          hintText: "17 символов (ISO)",
          errorText: _vinWarning,
        ),
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.next,
        maxLength: VinUtils.requiredLength,
        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
      );

  Widget _classField() => DropdownButtonFormField<String>(
        value: _selectedCarCategory,
        decoration: const InputDecoration(labelText: "Класс", isDense: true),
        dropdownColor: AppColors.surface2,
        items: ['1', '2', '3', '4'].map((v) => DropdownMenuItem(value: v, child: Text("$v кл."))).toList(),
        onChanged: (val) {
          if (val != null) setState(() => _selectedCarCategory = val);
        },
      );

  Widget _clientCarsDropdown() => DropdownButtonFormField<int>(
        value: _selectedClientCarId,
        decoration: const InputDecoration(labelText: "Авто клиента", isDense: true),
        dropdownColor: AppColors.surface2,
        items: _clientCars.map((car) {
          return DropdownMenuItem<int>(
            value: car['id'] as int,
            child: Text(
              "${car['make_model']} | ${car['plate']}${((car['vin'] ?? '') as String).isNotEmpty ? ' | VIN ${car['vin']}' : ''}",
              style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: (val) {
          if (val == null) return;
          var selectedCar = _clientCars.firstWhere((c) => c['id'] == val);
          setState(() {
            _selectedClientCarId = val;
            _setCarMakeModel(selectedCar['make_model']?.toString() ?? "");
            _plateController.text = PlateMaskFormatter.normalize(selectedCar['plate']?.toString() ?? "");
            _vinController.text = selectedCar['vin']?.toString() ?? "";
            _selectedCarCategory = selectedCar['category'] ?? "1";
          });
        },
      );

  Widget _clientSection({required bool mobile}) {
    final make = _carMakeModel.trim();
    final plate = PlateMaskFormatter.normalize(_plateController.text);
    final showPreview = make.isNotEmpty || plate.length >= 4;

    return KeyedSubtree(
      key: TourKeys.orderClient,
      child: _sectionCard(
        title: "Клиент и авто",
        subtitle: "Телефон, машина и класс для прайса",
        icon: Icons.person_outline_rounded,
        child: Column(
          children: [
            if (showPreview) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: AppColors.bg.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  border: Border.all(color: AppColors.borderSoft),
                ),
                child: Row(
                  children: [
                    CarBrandMark(make.isEmpty ? null : make, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (plate.isNotEmpty) ...[
                            PlateBadge(plate),
                            const SizedBox(height: 4),
                          ],
                          Text(
                            make.isEmpty ? 'Марка / модель' : make,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              color: make.isEmpty ? AppColors.textDim : AppColors.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                          Text(
                            '$_selectedCarCategory кл.',
                            style: GoogleFonts.manrope(
                              color: AppColors.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (mobile) ...[
              _phoneField(),
              const SizedBox(height: 10),
              _nameField(),
            ] else
              Row(
                children: [
                  Expanded(child: _phoneField()),
                  const SizedBox(width: 10),
                  Expanded(child: _nameField()),
                ],
              ),
            if (_clientCars.isNotEmpty) ...[
              const SizedBox(height: 10),
              _clientCarsDropdown(),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_knownClientId != null)
                    _quickActionChip(
                      icon: Icons.history_rounded,
                      label: 'Как в прошлый раз',
                      onTap: _fillFromLastOrder,
                    ),
                  _quickActionChip(
                    icon: Icons.bookmark_outline_rounded,
                    label: 'Шаблоны',
                    onTap: _showTemplates,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (mobile) ...[
              _carField(stacked: true),
              const SizedBox(height: 10),
              _plateField(),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: _carField()),
                  const SizedBox(width: 10),
                  Expanded(child: _plateField()),
                ],
              ),
            const SizedBox(height: 10),
            if (mobile) ...[
              _vinField(),
              const SizedBox(height: 10),
              _classField(),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _vinField()),
                  const SizedBox(width: 10),
                  Expanded(child: _classField()),
                ],
              ),
            if (_plateHistory.isNotEmpty) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('ИСТОРИЯ ПО ГОСНОМЕРУ', style: AppTheme.sectionLabel),
              ),
              const SizedBox(height: 8),
              ..._plateHistory.take(5).map((o) {
                final st = o['status']?.toString() ?? '';
                final whenRaw = (o['start_time']?.toString().isNotEmpty == true)
                    ? o['start_time']
                    : o['created_at'];
                final when = AppDateTime.format(whenRaw);
                final client = o['client_name']?.toString() ?? '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.bg.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderSoft),
                  ),
                  child: Text(
                    '#${o['id']} · $st · $when${client.isEmpty ? '' : ' · $client'}',
                    style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
              if (_plateHistory.length > 5)
                Text(
                  'ещё ${_plateHistory.length - 5}…',
                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _scheduleColumn({
    required String title,
    required Widget dateChip,
    required Widget timeChip,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: AppTheme.sectionLabel),
        const SizedBox(height: 8),
        dateChip,
        const SizedBox(height: 8),
        timeChip,
      ],
    );
  }

  Widget _scheduleSection({required bool mobile}) {
    final reception = _scheduleColumn(
      title: 'Приём',
      dateChip: _dateTimeChip(
        icon: Icons.calendar_today_outlined,
        label: "Дата",
        value: _fmtDate(_selectedDate),
        accent: AppColors.success,
        onTap: _pickDate,
      ),
      timeChip: _dateTimeChip(
        icon: Icons.access_time_rounded,
        label: "Время",
        value: _fmtTime(_selectedTime),
        accent: AppColors.success,
        onTap: _pickTime,
      ),
    );
    final delivery = _scheduleColumn(
      title: 'Выдача',
      dateChip: _dateTimeChip(
        icon: Icons.event_available_outlined,
        label: "Дата",
        value: _fmtDate(_endDate),
        accent: AppColors.danger,
        onTap: _pickEndDate,
      ),
      timeChip: _dateTimeChip(
        icon: Icons.schedule_rounded,
        label: "Время",
        value: _fmtTime(_endTime),
        accent: AppColors.danger,
        onTap: _pickEndTime,
      ),
    );

    final body = mobile
        ? Column(
            children: [
              reception,
              const SizedBox(height: 14),
              delivery,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: reception),
              const SizedBox(width: 12),
              Expanded(child: delivery),
            ],
          );

    return KeyedSubtree(
      key: TourKeys.orderSchedule,
      child: _sectionCard(
        title: "Слот",
        subtitle: "Когда принять и когда отдать",
        icon: Icons.schedule_rounded,
        child: body,
      ),
    );
  }

  Future<void> _showTemplates() async {
    final templates = await OrderTemplatesStore.load();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Шаблоны записи', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 420,
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_cart.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _saveCartAsTemplate();
                    },
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(
                      'Сохранить текущую корзину',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              Expanded(
                child: templates.isEmpty
                    ? Center(
                        child: Text(
                          'Шаблонов пока нет.\nСоберите корзину и сохраните.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(color: AppColors.textDim),
                        ),
                      )
                    : ListView.separated(
                        itemCount: templates.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (_, i) {
                          final t = templates[i];
                          return ListTile(
                            dense: true,
                            title: Text(
                              t.name,
                              style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              '${t.items.length} поз.',
                              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                            ),
                            trailing: IconButton(
                              tooltip: 'Удалить',
                              icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                              onPressed: () async {
                                await OrderTemplatesStore.delete(t.id);
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) _showTemplates();
                              },
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              setState(() {
                                _cart
                                  ..clear()
                                  ..addAll(t.items.map((e) => Map<String, dynamic>.from(e)));
                                _recalcCartTotal();
                                _priceController.text = _total == _total.roundToDouble()
                                    ? _total.toInt().toString()
                                    : _total.toStringAsFixed(0);
                                _statusMessage = 'Шаблон «${t.name}» · ${t.items.length} поз.';
                                _statusColor = AppColors.success;
                              });
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
        ],
      ),
    );
  }

  Future<void> _saveCartAsTemplate() async {
    if (_cart.isEmpty) return;
    final nameCtrl = TextEditingController(
      text: _cart.length == 1
          ? (_cart.first['name']?.toString() ?? 'Шаблон')
          : 'Шаблон · ${_cart.length} поз.',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Сохранить шаблон', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Название', isDense: true),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok != true || name.isEmpty) return;
    await OrderTemplatesStore.saveFromCart(name: name, cart: _cart);
    if (!mounted) return;
    setState(() {
      _statusMessage = 'Шаблон «$name» сохранён';
      _statusColor = AppColors.success;
    });
  }

  Widget _cartBlock() {
    final totalLabel = _total == _total.roundToDouble()
        ? _total.toInt().toString()
        : _total.toStringAsFixed(0);

    return KeyedSubtree(
      key: TourKeys.orderCart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _sectionCard(
            title: "Корзина",
            subtitle: _cart.isEmpty
                ? "Выберите услуги на картинках выше"
                : "${_cart.length} поз. · $totalLabel ₽",
            icon: Icons.shopping_bag_outlined,
            trailing: _cart.isEmpty
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 4, top: 4),
                    child: Text(
                      "$totalLabel ₽",
                      style: GoogleFonts.manrope(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
            child: SizedBox(
              height: _cart.isEmpty ? 72 : 104,
              child: _cart.isEmpty
                  ? Center(
                      child: Text(
                        "Пока пусто",
                        style: GoogleFonts.manrope(
                          color: AppColors.textDim,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _cart.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final item = _cart[index];
                        final zones = item['wrapZones'];
                        final isWrapPkg = zones is List && zones.isNotEmpty;
                        final title = isWrapPkg
                            ? 'Оклейка · ${zones.length} поз.'
                            : (item['name']?.toString() ?? '');
                        final cat = item['category']?.toString() ?? '';
                        return Container(
                          constraints: BoxConstraints(maxWidth: isWrapPkg ? 280 : 220),
                          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                          decoration: AppTheme.listTileDecoration(
                            accent: AppColors.primary.withOpacity(0.55),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (cat.isNotEmpty)
                                      Text(
                                        cat,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.manrope(
                                          color: AppColors.textDim,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 10.5,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.manrope(
                                        color: AppColors.text,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                        height: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "${item['price']} ₽",
                                      style: GoogleFonts.manrope(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: "Убрать",
                                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textDim),
                                onPressed: () => _removeFromCart(index),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radius),
                gradient: _cart.isEmpty
                    ? null
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, AppColors.primaryDeep],
                      ),
                color: _cart.isEmpty ? AppColors.borderSoft : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _cart.isEmpty ? null : _saveOrder,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  child: Center(
                    child: Text(
                      "Создать заказ",
                      style: GoogleFonts.manrope(
                        color: _cart.isEmpty ? AppColors.textMuted : AppColors.onPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gallery() {
    return ServiceCategoryGallery(
      services: _services,
      carCategory: _selectedCarCategory,
      selectedNames: _cart
          .where((e) => e['wrapZones'] == null)
          .map((e) => e['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toSet(),
      onToggle: _toggleCart,
      onWrapPackage: _applyWrapPackage,
      wrapSelectedNames: _wrapSelectedNames,
      wrapPackagePrice: _wrapPackagePrice,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = AppResponsive.isMobile(context);
    final pad = mobile ? const EdgeInsets.fromLTRB(12, 12, 12, 16) : const EdgeInsets.fromLTRB(24, 20, 24, 18);

    Widget statusBanner() {
      if (_statusMessage.isEmpty) return const SizedBox.shrink();
      final ok = _statusColor == AppColors.success;
      return Container(
        margin: EdgeInsets.only(bottom: mobile ? 12 : 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: (ok ? AppColors.success : AppColors.danger).withOpacity(0.12),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: (ok ? AppColors.success : AppColors.danger).withOpacity(0.35)),
        ),
        child: Text(
          _statusMessage,
          style: GoogleFonts.manrope(color: _statusColor, fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
      );
    }

    if (mobile) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: ListView(
          padding: pad,
          children: [
            statusBanner(),
            _clientSection(mobile: true),
            const SizedBox(height: 12),
            _scheduleSection(mobile: true),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: TourKeys.orderGallery,
              child: _sectionCard(
                title: "Услуги",
                subtitle: "Категории прайса",
                icon: Icons.grid_view_rounded,
                child: SizedBox(
                  height: (MediaQuery.sizeOf(context).height * 0.38).clamp(260.0, 420.0),
                  child: _gallery(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _cartBlock(),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Новый заказ", style: AppTheme.pageTitle),
                      const SizedBox(height: 4),
                      Text('Клиент · слот · услуги', style: AppTheme.pageSubtitle),
                    ],
                  ),
                ),
                if (_statusMessage.isNotEmpty) Flexible(child: statusBanner()),
              ],
            ),
            const SizedBox(height: 16),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: _clientSection(mobile: false)),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: _scheduleSection(mobile: false)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: KeyedSubtree(
                      key: TourKeys.orderGallery,
                      child: _sectionCard(
                        title: "Услуги",
                        subtitle: "Нажмите категорию, чтобы добавить в корзину",
                        icon: Icons.grid_view_rounded,
                        expand: true,
                        child: _gallery(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _cartBlock(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
