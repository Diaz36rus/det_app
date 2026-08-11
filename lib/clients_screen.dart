import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_datetime.dart';
import 'app_theme.dart';
import 'app_toast.dart';
import 'database.dart';
import 'db_refresh_mixin.dart';
import 'input_masks.dart';
import 'order_details_dialog.dart';
import 'responsive.dart';
import 'vin_utils.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

enum _ClientSort { name, phone, car, plate, vip }

class _ClientsScreenState extends State<ClientsScreen> with DbRefreshMixin {
  @override
  void onDatabaseChanged() => _loadClients(_searchController.text);
  List<Map<String, dynamic>> _clients = [];
  final Map<int, List<Map<String, dynamic>>> _carsByClient = {};
  bool _isLoading = true;
  bool _mobileNewClientOpen = false;
  _ClientSort _sort = _ClientSort.name;

  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController(text: PhonePlus7Formatter.prefix);
  final _carController = TextEditingController();
  final _plateController = TextEditingController();
  final _vinController = TextEditingController();
  String _newCarCategory = '1';

  static const _vipAccent = Color(0xFFD4A017);

  @override
  void initState() {
    super.initState();
    _loadClients("");
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _carController.dispose();
    _plateController.dispose();
    _vinController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _sortedClients {
    final list = List<Map<String, dynamic>>.from(_clients);
    int cmpStr(dynamic a, dynamic b) =>
        (a?.toString() ?? '').toLowerCase().compareTo((b?.toString() ?? '').toLowerCase());

    String firstCarField(int clientId, String key) {
      final cars = _carsByClient[clientId] ?? const [];
      if (cars.isEmpty) return '';
      return cars.first[key]?.toString() ?? '';
    }

    list.sort((a, b) {
      final idA = a['id'] as int;
      final idB = b['id'] as int;
      switch (_sort) {
        case _ClientSort.name:
          return cmpStr(a['name'], b['name']);
        case _ClientSort.phone:
          return cmpStr(a['phone'], b['phone']);
        case _ClientSort.car:
          return cmpStr(firstCarField(idA, 'make_model'), firstCarField(idB, 'make_model'));
        case _ClientSort.plate:
          return cmpStr(firstCarField(idA, 'plate'), firstCarField(idB, 'plate'));
        case _ClientSort.vip:
          final v = (b['is_vip'] == 1 ? 1 : 0).compareTo(a['is_vip'] == 1 ? 1 : 0);
          return v != 0 ? v : cmpStr(a['name'], b['name']);
      }
    });
    return list;
  }

  Future<void> _loadClients(String query) async {
    setState(() => _isLoading = true);
    final clients = query.isEmpty
        ? await DatabaseHelper().getClientsList()
        : await DatabaseHelper().searchClients(query);

    final carsMap = <int, List<Map<String, dynamic>>>{};
    for (final c in clients) {
      final id = c['id'] as int;
      carsMap[id] = await DatabaseHelper().getClientCars(id);
    }

    if (!mounted) return;
    setState(() {
      _clients = clients;
      _carsByClient
        ..clear()
        ..addAll(carsMap);
      _isLoading = false;
    });
  }

  Future<void> _addClient() async {
    final phone = PhonePlus7Formatter.normalize(_phoneController.text);
    if (_nameController.text.isEmpty || phone.length < 12) return;

    final vinWarning = VinUtils.validate(_vinController.text);
    if (vinWarning != null) {
      if (mounted) showAppToast(context, vinWarning);
      return;
    }

    final clientId = await DatabaseHelper().addClient(_nameController.text.trim(), phone);
    final make = _carController.text.trim();
    final plate = PlateMaskFormatter.normalize(_plateController.text);
    final vin = VinUtils.normalize(_vinController.text);
    if (make.isNotEmpty || plate.isNotEmpty || vin.isNotEmpty) {
      await DatabaseHelper().addCar(
        clientId,
        make.isEmpty ? '—' : make,
        plate,
        vin: vin,
        category: _newCarCategory,
      );
    }

    _nameController.clear();
    _phoneController.text = PhonePlus7Formatter.prefix;
    _carController.clear();
    _plateController.clear();
    _vinController.clear();
    setState(() => _newCarCategory = '1');
    _loadClients(_searchController.text);
  }

  void _showAddCarDialog(int clientId) {
    _showCarDialog(clientId: clientId);
  }

  void _showEditCarDialog(Map<String, dynamic> car) {
    _showCarDialog(
      clientId: car['client_id'] as int,
      carId: car['id'] as int,
      make: car['make_model']?.toString() ?? "",
      plate: car['plate']?.toString() ?? "",
      vin: car['vin']?.toString() ?? "",
      category: car['category']?.toString() ?? "1",
    );
  }

  void _showCarDialog({
    required int clientId,
    int? carId,
    String make = "",
    String plate = "",
    String vin = "",
    String category = "1",
  }) {
    final makeCtrl = TextEditingController(text: make);
    final plateCtrl = TextEditingController(text: PlateMaskFormatter.normalize(plate));
    final vinCtrl = TextEditingController(text: vin);
    var selectedCategory = ['1', '2', '3', '4'].contains(category) ? category : '1';
    final isEdit = carId != null;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              title: Text(
                isEdit ? "Редактировать авто" : "Добавить авто",
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: makeCtrl, decoration: const InputDecoration(labelText: "Марка/Модель")),
                  TextField(
                    controller: plateCtrl,
                    decoration: const InputDecoration(labelText: "Госномер", hintText: "A123BC777"),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [PlateMaskFormatter()],
                  ),
                  TextField(
                    controller: vinCtrl,
                    decoration: const InputDecoration(labelText: "VIN код"),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: const InputDecoration(labelText: "Класс авто", isDense: true),
                    dropdownColor: AppColors.surface,
                    items: ['1', '2', '3', '4']
                        .map((v) => DropdownMenuItem(value: v, child: Text("$v класс")))
                        .toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      setDialogState(() => selectedCategory = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Отмена")),
                ElevatedButton(
                  onPressed: () async {
                    if (makeCtrl.text.isEmpty) return;
                    final vinWarning = VinUtils.validate(vinCtrl.text);
                    if (vinWarning != null) {
                      showAppToast(context, vinWarning);
                      return;
                    }
                    final plateNorm = PlateMaskFormatter.normalize(plateCtrl.text);
                    final vinNorm = VinUtils.normalize(vinCtrl.text);
                    if (isEdit) {
                      await DatabaseHelper().updateCar(
                        carId,
                        makeModel: makeCtrl.text,
                        plate: plateNorm,
                        vin: vinNorm,
                        category: selectedCategory,
                      );
                    } else {
                      await DatabaseHelper().addCar(
                        clientId,
                        makeCtrl.text,
                        plateNorm,
                        vin: vinNorm,
                        category: selectedCategory,
                      );
                    }
                    if (context.mounted) Navigator.pop(context);
                    _loadClients(_searchController.text);
                  },
                  child: Text(isEdit ? "Сохранить" : "Добавить"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openHistoryOrder(int orderId) async {
    final full = await DatabaseHelper().getOrderById(orderId);
    if (full == null || !mounted) return;
    await OrderDetailsDialog.open(context, full);
  }

  void _showHistory(int clientId, String name) async {
    final history = await DatabaseHelper().getClientHistory(clientId);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text("История: $name", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: AppResponsive.dialogWidth(context, desktop: 480),
          height: AppResponsive.isMobile(context) ? MediaQuery.sizeOf(context).height * 0.55 : 420,
          child: history.isEmpty
              ? Center(child: Text("Нет истории", style: GoogleFonts.manrope(color: AppColors.textMuted)))
              : ListView.separated(
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final h = history[index];
                    final id = h['id'] as int;
                    final notes = (h['notes']?.toString().isNotEmpty == true)
                        ? h['notes'].toString()
                        : "Без услуг";
                    return InkWell(
                      onTap: () async {
                        Navigator.pop(context);
                        await _openHistoryOrder(id);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "#$id · ${h['status']}",
                                    style: GoogleFonts.manrope(
                                      color: AppColors.text,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${h['make_model'] ?? ''} · ${h['plate'] ?? ''}",
                                    style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    notes,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${AppDateTime.format(h['created_at'])} · ${h['price']} ₽",
                                    style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: AppColors.textMuted),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Закрыть")),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> client) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text("Удалить клиента?", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: Text(
          "${client['name']} будет удалён из базы.",
          style: GoogleFonts.manrope(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Отмена")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Удалить"),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DatabaseHelper().deleteClient(client['id']);
      _loadClients(_searchController.text);
    }
  }

  Widget _buildToolbar() {
    final mobile = AppResponsive.isMobile(context);
    return Container(
      margin: EdgeInsets.fromLTRB(mobile ? 12 : 24, 0, mobile ? 12 : 24, 12),
      padding: EdgeInsets.all(mobile ? 12 : 16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: "Поиск",
              hintText: "Имя, телефон, авто, VIN…",
              prefixIcon: Icon(Icons.search, color: AppColors.textMuted, size: 20),
              isDense: true,
            ),
            onChanged: (val) => _loadClients(val),
          ),
          if (!mobile) ...[
            const SizedBox(height: 14),
            Text(
              "НОВЫЙ КЛИЕНТ",
              style: GoogleFonts.manrope(
                color: AppColors.textDim,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 10),
          if (mobile) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _mobileNewClientOpen = !_mobileNewClientOpen),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _mobileNewClientOpen ? 'Скрыть форму' : 'Добавить клиента',
                          style: GoogleFonts.manrope(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Icon(
                        _mobileNewClientOpen ? Icons.expand_less : Icons.expand_more,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_mobileNewClientOpen) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "Имя", isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: "Телефон", hintText: "+7XXXXXXXXXX", isDense: true),
                keyboardType: TextInputType.phone,
                inputFormatters: [PhonePlus7Formatter()],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _carController,
                decoration: const InputDecoration(labelText: "Авто (марка/модель)", isDense: true),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _plateController,
                decoration: const InputDecoration(labelText: "Госномер", hintText: "A123BC777", isDense: true),
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [PlateMaskFormatter()],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _vinController,
                decoration: const InputDecoration(labelText: "VIN", hintText: "необязательно", isDense: true),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _newCarCategory,
                decoration: const InputDecoration(labelText: "Класс", isDense: true),
                dropdownColor: AppColors.surface2,
                items: ['1', '2', '3', '4']
                    .map((v) => DropdownMenuItem(value: v, child: Text("$v кл.")))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _newCarCategory = v);
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _addClient,
                  child: Text("Добавить", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: "Имя", isDense: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: "Телефон", hintText: "+7XXXXXXXXXX", isDense: true),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [PhonePlus7Formatter()],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _carController,
                    decoration: const InputDecoration(labelText: "Авто (марка/модель)", isDense: true),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _plateController,
                    decoration: const InputDecoration(labelText: "Госномер", hintText: "A123BC777", isDense: true),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [PlateMaskFormatter()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _vinController,
                    decoration: const InputDecoration(labelText: "VIN", hintText: "необязательно", isDense: true),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _newCarCategory,
                    decoration: const InputDecoration(labelText: "Класс", isDense: true),
                    dropdownColor: AppColors.surface2,
                    items: ['1', '2', '3', '4']
                        .map((v) => DropdownMenuItem(value: v, child: Text("$v кл.")))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _newCarCategory = v);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(child: SizedBox()),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _addClient,
                    child: Text("Добавить", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSortBar() {
    final mobile = AppResponsive.isMobile(context);
    Widget chip(_ClientSort value, String label) {
      final on = _sort == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          selected: on,
          label: Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: on ? Colors.white : AppColors.textMuted,
            ),
          ),
          selectedColor: AppColors.primary,
          backgroundColor: AppColors.surface2,
          checkmarkColor: Colors.white,
          side: BorderSide(color: on ? AppColors.primary : AppColors.border),
          onSelected: (_) => setState(() => _sort = value),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(mobile ? 12 : 24, 12, mobile ? 12 : 24, 0),
      child: Row(
        children: [
          Text(
            'Сортировка',
            style: GoogleFonts.manrope(
              color: AppColors.textDim,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  chip(_ClientSort.name, 'Имя'),
                  chip(_ClientSort.phone, 'Телефон'),
                  chip(_ClientSort.car, 'Авто'),
                  chip(_ClientSort.plate, 'Госномер'),
                  chip(_ClientSort.vip, 'VIP'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientCard(Map<String, dynamic> c) {
    final id = c['id'] as int;
    final isVip = c['is_vip'] == 1;
    final cars = _carsByClient[id] ?? [];
    final accent = isVip ? _vipAccent : AppColors.primary;
    final mobile = AppResponsive.isMobile(context);

    final actions = [
      IconButton(
        tooltip: isVip ? "Снять VIP" : "Сделать VIP",
        visualDensity: mobile ? VisualDensity.compact : null,
        icon: Icon(
          isVip ? Icons.star : Icons.star_border,
          color: isVip ? _vipAccent : AppColors.textDim,
          size: 22,
        ),
        onPressed: () async {
          await DatabaseHelper().updateClientVip(id, isVip ? 0 : 1);
          _loadClients(_searchController.text);
        },
      ),
      IconButton(
        tooltip: "История",
        visualDensity: mobile ? VisualDensity.compact : null,
        icon: const Icon(Icons.history, color: AppColors.primary, size: 22),
        onPressed: () => _showHistory(id, c['name']?.toString() ?? ""),
      ),
      IconButton(
        tooltip: "Добавить авто",
        visualDensity: mobile ? VisualDensity.compact : null,
        icon: const Icon(Icons.directions_car, color: AppColors.success, size: 22),
        onPressed: () => _showAddCarDialog(id),
      ),
      IconButton(
        tooltip: "Удалить",
        visualDensity: mobile ? VisualDensity.compact : null,
        icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 22),
        onPressed: () => _confirmDelete(c),
      ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: isVip ? _vipAccent.withOpacity(0.4) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radius)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        "${c['name'] ?? ''}",
                        style: GoogleFonts.manrope(
                          color: AppColors.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isVip) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _vipAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _vipAccent.withOpacity(0.5)),
                        ),
                        child: Text(
                          "VIP",
                          style: GoogleFonts.manrope(
                            color: _vipAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "${c['phone'] ?? ''}",
                  style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 4),
                if (mobile)
                  Wrap(spacing: 0, runSpacing: 0, children: actions)
                else
                  Row(children: actions),
                const SizedBox(height: 12),
                Text(
                  cars.isEmpty ? "АВТО · нет" : "АВТО · ${cars.length}",
                  style: GoogleFonts.manrope(
                    color: AppColors.textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 8),
                if (cars.isEmpty)
                  Text(
                    "Добавьте автомобиль клиента",
                    style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
                  )
                else
                  ...cars.map((car) {
                    final vin = (car['vin'] ?? '').toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _showEditCarDialog(car),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.directions_car_outlined, color: AppColors.textMuted, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "${car['make_model']}",
                                        style: GoogleFonts.manrope(
                                          color: AppColors.text,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "${car['plate']}",
                                        style: GoogleFonts.manrope(
                                          color: AppColors.text,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        [
                                          "${car['category'] ?? '1'} кл.",
                                          vin.isEmpty ? "VIN не указан" : "VIN $vin",
                                        ].join(" · "),
                                        style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.edit_outlined, color: AppColors.textDim, size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = AppResponsive.isMobile(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mobile)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Row(
                children: [
                  Text("Клиенты", style: AppTheme.pageTitle),
                  const Spacer(),
                  Text(
                    "${_clients.length}",
                    style: GoogleFonts.manrope(
                      color: AppColors.textDim,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          _buildToolbar(),
          if (!_isLoading && _clients.isNotEmpty) _buildSortBar(),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _clients.isEmpty
                    ? Center(
                        child: Text(
                          "Клиентов пока нет",
                          style: GoogleFonts.manrope(color: AppColors.textDim),
                        ),
                      )
                    : Builder(
                        builder: (context) {
                          final sorted = _sortedClients;
                          return ListView.builder(
                            padding: EdgeInsets.fromLTRB(mobile ? 12 : 24, 16, mobile ? 12 : 24, 24),
                            itemCount: sorted.length,
                            itemBuilder: (context, index) => _buildClientCard(sorted[index]),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
