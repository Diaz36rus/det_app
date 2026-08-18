import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_theme.dart';
import '../cash_cloud/cash_cloud_api.dart';
import 'crm_api.dart';
import 'crm_models.dart';

const kCloudStatuses = [
  'Предварительная запись',
  'Принят в работу',
  'Мойка',
  'Химчистка',
  'Полировка',
  'Подготовка к выдаче',
  'Выдан',
];

/// Облачная доска заказов (C4) — основной экран в cloud-режиме.
class CloudBoardScreen extends StatefulWidget {
  const CloudBoardScreen({super.key});

  @override
  State<CloudBoardScreen> createState() => _CloudBoardScreenState();
}

class _CloudBoardScreenState extends State<CloudBoardScreen> {
  final _api = CrmApi();
  List<CrmOrder> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.listOrders();
      if (!mounted) return;
      setState(() {
        _orders = list;
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

  Future<void> _openCreate() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => const _CreateDialog());
    if (ok == true) _reload();
  }

  Future<void> _openOrder(CrmOrder o) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _OrderSheet(order: o),
    );
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.manrope(color: AppColors.danger)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _reload, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(
            children: [
              Expanded(child: Text('Доска (облако)', style: AppTheme.pageTitle)),
              IconButton(onPressed: _reload, icon: const Icon(Icons.refresh, color: AppColors.textMuted)),
              ElevatedButton.icon(
                onPressed: _openCreate,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Заказ'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              for (final st in kCloudStatuses)
                _StatusColumn(
                  status: st,
                  orders: _orders.where((o) => o.status == st).toList(),
                  onTap: _openOrder,
                ),
              _StatusColumn(
                status: 'Прочее',
                orders: _orders.where((o) => !kCloudStatuses.contains(o.status)).toList(),
                onTap: _openOrder,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusColumn extends StatelessWidget {
  const _StatusColumn({required this.status, required this.orders, required this.onTap});
  final String status;
  final List<CrmOrder> orders;
  final void Function(CrmOrder) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$status (${orders.length})',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final o = orders[i];
                return Material(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => onTap(o),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('#${o.id} ${o.clientName ?? ''}',
                              style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13)),
                          Text(o.carLabel ?? '',
                              style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12)),
                          Text('${o.price.toStringAsFixed(0)} ₽ · долг ${o.debt.toStringAsFixed(0)}',
                              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateDialog extends StatefulWidget {
  const _CreateDialog();
  @override
  State<_CreateDialog> createState() => _CreateDialogState();
}

class _CreateDialogState extends State<_CreateDialog> {
  final _api = CrmApi();
  final _client = TextEditingController();
  final _phone = TextEditingController();
  final _car = TextEditingController();
  final _plate = TextEditingController();
  List<CrmService> _services = [];
  List<CrmMaster> _masters = [];
  CrmService? _svc;
  CrmMaster? _master;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future.wait([_api.listServices(), _api.listMasters()]).then((pair) {
      if (!mounted) return;
      final services = (pair[0] as List<CrmService>).where((e) => e.isActive).toList();
      final masters = (pair[1] as List<CrmMaster>).where((e) => e.isActive).toList();
      setState(() {
        _services = services;
        _masters = masters;
        if (_services.isNotEmpty) _svc = _services.first;
        if (_masters.isNotEmpty) _master = _masters.first;
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _client.dispose();
    _phone.dispose();
    _car.dispose();
    _plate.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = _client.text.trim();
    final make = _car.text.trim();
    if (name.isEmpty || make.isEmpty) return;
    setState(() => _busy = true);
    try {
      final c = await _api.createClient(name: name, phone: _phone.text.trim());
      final car = await _api.createCar(clientId: c.id, makeModel: make, plate: _plate.text.trim());
      final items = <CrmOrderItem>[
        if (_svc != null)
          CrmOrderItem(name: _svc!.name, price: _svc!.price, workshop: _svc!.workshop)
        else
          const CrmOrderItem(name: 'Работа', price: 0),
      ];
      await _api.createOrder(
        clientId: c.id,
        carId: car.id,
        items: items,
        masterIds: _master == null ? const [] : [_master!.id],
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Новый заказ', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _client, decoration: const InputDecoration(labelText: 'Клиент')),
              TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Телефон')),
              TextField(controller: _car, decoration: const InputDecoration(labelText: 'Авто')),
              TextField(controller: _plate, decoration: const InputDecoration(labelText: 'Номер')),
              if (_services.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<CrmService>(
                  value: _svc,
                  items: _services
                      .map((s) => DropdownMenuItem(value: s, child: Text('${s.name} · ${s.price.toStringAsFixed(0)}')))
                      .toList(),
                  onChanged: (v) => setState(() => _svc = v),
                  decoration: const InputDecoration(labelText: 'Услуга'),
                ),
              ],
              if (_masters.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<CrmMaster>(
                  value: _master,
                  items: _masters
                      .map((m) => DropdownMenuItem(value: m, child: Text('${m.name} · ${m.role}')))
                      .toList(),
                  onChanged: (v) => setState(() => _master = v),
                  decoration: const InputDecoration(labelText: 'Мастер'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Отмена')),
        ElevatedButton(onPressed: _busy ? null : _submit, child: const Text('Создать')),
      ],
    );
  }
}

class _OrderSheet extends StatefulWidget {
  const _OrderSheet({required this.order});
  final CrmOrder order;
  @override
  State<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<_OrderSheet> {
  final _api = CrmApi();
  final _cash = CashCloudApi();
  late String _status;
  final _defect = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _status = widget.order.status;
  }

  @override
  void dispose() {
    _defect.dispose();
    super.dispose();
  }

  Future<void> _saveStatus() async {
    setState(() => _busy = true);
    try {
      await _api.patchOrder(widget.order.id, {'status': _status});
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.danger));
    }
  }

  Future<void> _pay() async {
    final debt = widget.order.debt;
    if (debt <= 0) return;
    setState(() => _busy = true);
    try {
      var shift = await _cash.currentShift();
      if (shift == null || !shift.isOpen) {
        await _cash.openShift();
      }
      await _cash.createPayment(orderId: widget.order.id, amount: debt, method: 'Наличные');
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.danger));
    }
  }

  Future<void> _addDefect() async {
    final text = _defect.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _api.addDefect(widget.order.id, description: text);
      if (!mounted) return;
      _defect.clear();
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Дефект добавлен')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Заказ #${o.id}', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${o.clientName}\n${o.carLabel}', style: GoogleFonts.manrope(color: AppColors.textMuted)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: kCloudStatuses.contains(_status) ? _status : kCloudStatuses[1],
                items: kCloudStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: _busy ? null : (v) => setState(() => _status = v ?? _status),
                decoration: const InputDecoration(labelText: 'Статус'),
              ),
              const SizedBox(height: 8),
              Text('Сумма ${o.price.toStringAsFixed(0)} · оплачено ${o.paidAmount.toStringAsFixed(0)}',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(controller: _defect, decoration: const InputDecoration(labelText: 'Дефект / заметка')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Закрыть')),
        TextButton(onPressed: _busy ? null : _addDefect, child: const Text('Дефект')),
        if (o.debt > 0) TextButton(onPressed: _busy ? null : _pay, child: const Text('Оплатить долг')),
        ElevatedButton(onPressed: _busy ? null : _saveStatus, child: const Text('Сохранить')),
      ],
    );
  }
}
