import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'database.dart';
import 'input_masks.dart';
import 'quick_datetime_picker.dart';
import 'service_category_gallery.dart';
import 'tour_keys.dart';

class OrdersScreen extends StatefulWidget {
  final DateTime? initialDate;
  final TimeOfDay? initialTime;

  const OrdersScreen({super.key, this.initialDate, this.initialTime});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _phoneController = TextEditingController(text: PhonePlus7Formatter.prefix);
  final _nameController = TextEditingController();
  final _carController = TextEditingController();
  final _plateController = TextEditingController();
  final _vinController = TextEditingController();
  final _priceController = TextEditingController(text: "0");
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

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = widget.initialDate ?? DateTime(now.year, now.month, now.day);
    _selectedTime = widget.initialTime ?? const TimeOfDay(hour: 9, minute: 0);
    _endDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    _endTime = const TimeOfDay(hour: 18, minute: 0);
    _ensureEndAfterStart();
    _loadServices();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _carController.dispose();
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

  Future<void> _checkClient(String phone) async {
    final normalized = PhonePlus7Formatter.normalize(phone);
    final digitCount = normalized.replaceAll(RegExp(r'\D'), '').length;
    if (digitCount >= 11) {
      var client = await DatabaseHelper().getClientByPhone(normalized);
      if (client != null) {
        var cars = await DatabaseHelper().getClientCarsForDropdown(normalized);
        setState(() {
          _nameController.text = client['name'];
          _clientCars = cars;
          _carController.clear();
          _plateController.clear();
          _vinController.clear();
          _selectedCarCategory = "1";
          _selectedClientCarId = null;
        });
      } else {
        setState(() {
          _clientCars = [];
          _vinController.clear();
        });
      }
    }
  }

  Future<void> _saveOrder() async {
    final phone = PhonePlus7Formatter.normalize(_phoneController.text);
    final plate = PlateMaskFormatter.normalize(_plateController.text);
    if (phone.length < 12 || _nameController.text.isEmpty || _carController.text.isEmpty) {
      setState(() {
        _statusMessage = "Заполните телефон (+7…), имя и авто";
        _statusColor = AppColors.danger;
      });
      return;
    }

    var client = await DatabaseHelper().getClientByPhone(phone);
    int clientId;

    if (client == null) {
      clientId = await DatabaseHelper().addClient(_nameController.text, phone);
    } else {
      clientId = client['id'];
    }

    int? carId = _selectedClientCarId ?? await DatabaseHelper().getCarId(clientId, plate);
    final vin = _vinController.text.trim();
    if (carId == null) {
      carId = await DatabaseHelper().addCar(
        clientId,
        _carController.text,
        plate,
        vin: vin,
        category: _selectedCarCategory,
      );
    } else {
      await DatabaseHelper().updateCar(
        carId,
        makeModel: _carController.text,
        plate: plate,
        vin: vin,
        category: _selectedCarCategory,
      );
    }

    String dueDateStr =
        "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
    String endDateStr =
        "${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}";
    final startDt = _startDateTime;
    final endDt = _endDateTime;
    String startTimeStr = startDt.toIso8601String();
    String endTimeStr = endDt.toIso8601String();

    await DatabaseHelper().addOrderWithItems(
      clientId,
      carId,
      _cart
          .map((item) => {
                "name": item['name'],
                "price": item['price'],
                "category": item['category'],
                "workshop": item['workshop'],
              })
          .toList(),
      dueDate: dueDateStr,
      startTime: startTimeStr,
      endTime: endTimeStr,
      endDate: endDateStr,
    );

    setState(() {
      _statusMessage = "Заказ создан";
      _statusColor = AppColors.success;
      _phoneController.text = PhonePlus7Formatter.prefix;
      _nameController.clear();
      _carController.clear();
      _plateController.clear();
      _vinController.clear();
      _priceController.text = "0";
      _cart.clear();
      _total = 0;
      _selectedClientCarId = null;
      _clientCars = [];
    });
  }

  Widget _sectionCard({required String title, required Widget child, bool expand = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTheme.sectionTitle),
          const SizedBox(height: 12),
          if (expand) Expanded(child: child) else child,
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
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: accent.withOpacity(0.55)),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (label != null)
                      Text(
                        label,
                        style: GoogleFonts.manrope(
                          color: AppColors.textDim,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      value,
                      style: GoogleFonts.manrope(
                        color: AppColors.text,
                        fontSize: label != null ? 16 : 18,
                        fontWeight: FontWeight.w800,
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

  String _fmtDate(DateTime d) =>
      "${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}";

  String _fmtTime(TimeOfDay t) =>
      "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text("Новый заказ", style: AppTheme.pageTitle),
                const Spacer(),
                if (_statusMessage.isNotEmpty)
                  Text(
                    _statusMessage,
                    style: GoogleFonts.manrope(
                      color: _statusColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            KeyedSubtree(
              key: TourKeys.orderClient,
              child: _sectionCard(
              title: "Клиент и авто",
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _phoneController,
                          decoration: const InputDecoration(
                            labelText: "Телефон",
                            hintText: "+7XXXXXXXXXX",
                            isDense: true,
                          ),
                          keyboardType: TextInputType.phone,
                          inputFormatters: [PhonePlus7Formatter()],
                          onChanged: _checkClient,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(labelText: "Имя клиента", isDense: true),
                        ),
                      ),
                    ],
                  ),
                  if (_clientCars.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      value: _selectedClientCarId,
                      decoration: const InputDecoration(labelText: "Авто клиента", isDense: true),
                      dropdownColor: AppColors.surface2,
                      items: _clientCars.map((car) {
                        return DropdownMenuItem<int>(
                          value: car['id'] as int,
                          child: Text(
                            "${car['make_model']} | ${car['plate']}${((car['vin'] ?? '') as String).isNotEmpty ? ' | VIN ${car['vin']}' : ''}",
                            style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        var selectedCar = _clientCars.firstWhere((c) => c['id'] == val);
                        setState(() {
                          _selectedClientCarId = val;
                          _carController.text = selectedCar['make_model'] ?? "";
                          _plateController.text =
                              PlateMaskFormatter.normalize(selectedCar['plate']?.toString() ?? "");
                          _vinController.text = selectedCar['vin']?.toString() ?? "";
                          _selectedCarCategory = selectedCar['category'] ?? "1";
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _carController,
                          decoration: const InputDecoration(labelText: "Авто (марка/модель)", isDense: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _plateController,
                          decoration: const InputDecoration(
                            labelText: "Госномер",
                            hintText: "A123BC777",
                            isDense: true,
                          ),
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [PlateMaskFormatter()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _vinController,
                          decoration: const InputDecoration(labelText: "VIN", isDense: true),
                          textCapitalization: TextCapitalization.characters,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedCarCategory,
                          decoration: const InputDecoration(labelText: "Класс", isDense: true),
                          dropdownColor: AppColors.surface2,
                          items: ['1', '2', '3', '4']
                              .map((v) => DropdownMenuItem(value: v, child: Text("$v кл.")))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedCarCategory = val);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: TourKeys.orderSchedule,
              child: Row(
              children: [
                Expanded(
                  child: _dateTimeChip(
                    icon: Icons.calendar_today_outlined,
                    label: "Приём · дата",
                    value: _fmtDate(_selectedDate),
                    accent: AppColors.primary,
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _dateTimeChip(
                    icon: Icons.access_time,
                    label: "Приём · время",
                    value: _fmtTime(_selectedTime),
                    accent: AppColors.success,
                    onTap: _pickTime,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _dateTimeChip(
                    icon: Icons.event_available_outlined,
                    label: "Выдача · дата",
                    value: _fmtDate(_endDate),
                    accent: const Color(0xFFF59E0B),
                    onTap: _pickEndDate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _dateTimeChip(
                    icon: Icons.schedule,
                    label: "Выдача · время",
                    value: _fmtTime(_endTime),
                    accent: AppColors.danger,
                    onTap: _pickEndTime,
                  ),
                ),
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
                      title: "Категории услуг",
                      expand: true,
                      child: ServiceCategoryGallery(
                        services: _services,
                        carCategory: _selectedCarCategory,
                        selectedNames: _cart
                            .map((e) => e['name']?.toString() ?? '')
                            .where((n) => n.isNotEmpty)
                            .toSet(),
                        onToggle: _toggleCart,
                      ),
                    ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  KeyedSubtree(
                    key: TourKeys.orderCart,
                    child: _sectionCard(
                    title: "Корзина · $_total ₽",
                    expand: false,
                    child: SizedBox(
                      height: 96,
                      child: _cart.isEmpty
                          ? Center(
                              child: Text(
                                "Выберите услуги на картинках выше",
                                style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
                              ),
                            )
                          : ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _cart.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final item = _cart[index];
                                return Container(
                                  constraints: const BoxConstraints(maxWidth: 220),
                                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              item['name']?.toString() ?? '',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.manrope(
                                                color: AppColors.text,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                            Text(
                                              "${item['price']} ₽",
                                              style: GoogleFonts.manrope(
                                                color: AppColors.success,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: "Убрать",
                                        icon: const Icon(Icons.close, size: 18, color: AppColors.textDim),
                                        onPressed: () => _removeFromCart(index),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _saveOrder,
                child: Text(
                  "Создать заказ",
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
