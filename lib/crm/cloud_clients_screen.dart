import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_theme.dart';
import 'crm_api.dart';
import 'crm_models.dart';

class CloudClientsScreen extends StatefulWidget {
  const CloudClientsScreen({super.key});

  @override
  State<CloudClientsScreen> createState() => _CloudClientsScreenState();
}

class _CloudClientsScreenState extends State<CloudClientsScreen> {
  final _api = CrmApi();
  final _query = TextEditingController();
  List<CrmClient> _all = [];
  Map<int, List<CrmCar>> _cars = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<CrmClient> get _filtered {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((c) {
      return c.name.toLowerCase().contains(q) || c.phone.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final clients = await _api.listClients();
      final cars = await _api.listCars();
      final map = <int, List<CrmCar>>{};
      for (final car in cars) {
        map.putIfAbsent(car.clientId, () => []).add(car);
      }
      if (!mounted) return;
      setState(() {
        _all = clients;
        _cars = map;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _addClient() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final car = TextEditingController();
    final plate = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Новый клиент', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Имя')),
              TextField(controller: phone, decoration: const InputDecoration(labelText: 'Телефон')),
              TextField(controller: car, decoration: const InputDecoration(labelText: 'Авто (необяз.)')),
              TextField(controller: plate, decoration: const InputDecoration(labelText: 'Номер')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Создать')),
        ],
      ),
    );
    final n = name.text.trim();
    final p = phone.text.trim();
    final make = car.text.trim();
    final pl = plate.text.trim();
    name.dispose();
    phone.dispose();
    car.dispose();
    plate.dispose();
    if (ok != true || n.isEmpty) return;
    try {
      final c = await _api.createClient(name: n, phone: p);
      if (make.isNotEmpty) {
        await _api.createCar(clientId: c.id, makeModel: make, plate: pl);
      }
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.danger));
    }
  }

  Future<void> _editClient(CrmClient c) async {
    final name = TextEditingController(text: c.name);
    final phone = TextEditingController(text: c.phone);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Клиент', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Имя')),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'Телефон')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    final n = name.text.trim();
    final p = phone.text.trim();
    name.dispose();
    phone.dispose();
    if (ok != true || n.isEmpty) return;
    try {
      await _api.patchClient(c.id, {'name': n, 'phone': p});
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.danger));
    }
  }

  Future<void> _addCar(CrmClient c) async {
    final make = TextEditingController();
    final plate = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Авто · ${c.name}', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: make, decoration: const InputDecoration(labelText: 'Марка / модель')),
            TextField(controller: plate, decoration: const InputDecoration(labelText: 'Номер')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Добавить')),
        ],
      ),
    );
    final m = make.text.trim();
    final p = plate.text.trim();
    make.dispose();
    plate.dispose();
    if (ok != true || m.isEmpty) return;
    try {
      await _api.createCar(clientId: c.id, makeModel: m, plate: p);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: GoogleFonts.manrope(color: AppColors.danger)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _reload, child: const Text('Повторить')),
          ],
        ),
      );
    }
    final list = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(
            children: [
              Expanded(child: Text('Клиенты', style: AppTheme.pageTitle)),
              IconButton(onPressed: _reload, icon: const Icon(Icons.refresh, color: AppColors.textMuted)),
              ElevatedButton.icon(
                onPressed: _addClient,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Клиент'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Поиск по имени или телефону',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text('Нет клиентов', style: GoogleFonts.manrope(color: AppColors.textMuted)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final c = list[i];
                    final cars = _cars[c.id] ?? const <CrmCar>[];
                    return Material(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _editClient(c),
                        onLongPress: () => _addCar(c),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      c.name,
                                      style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 15),
                                    ),
                                  ),
                                  if (c.isVip)
                                    Text('VIP', style: GoogleFonts.manrope(color: AppColors.primary, fontWeight: FontWeight.w700)),
                                  IconButton(
                                    tooltip: 'Добавить авто',
                                    onPressed: () => _addCar(c),
                                    icon: const Icon(Icons.directions_car_outlined, size: 20),
                                  ),
                                ],
                              ),
                              if (c.phone.isNotEmpty)
                                Text(c.phone, style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13)),
                              if (cars.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  cars.map((e) => e.label).join(' · '),
                                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
