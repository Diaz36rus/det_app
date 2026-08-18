import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import 'cloud_board_screen.dart';
import 'crm_api.dart';
import 'crm_models.dart';

/// Календарь по due_date облачных заказов.
class CloudCalendarScreen extends StatefulWidget {
  const CloudCalendarScreen({
    super.key,
    required this.selectedDate,
    required this.onDateChanged,
    this.onCreate,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  final VoidCallback? onCreate;

  @override
  State<CloudCalendarScreen> createState() => _CloudCalendarScreenState();
}

class _CloudCalendarScreenState extends State<CloudCalendarScreen> {
  final _api = CrmApi();
  List<CrmOrder> _orders = [];
  bool _loading = true;
  String? _error;

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant CloudCalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      // list already loaded — just rebuild filter
      setState(() {});
    }
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

  List<CrmOrder> get _dayOrders {
    final key = _ymd(widget.selectedDate);
    return _orders.where((o) {
      final d = o.dueDate;
      if (d.isEmpty) return false;
      return d.startsWith(key) || d == key;
    }).toList();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: widget.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) widget.onDateChanged(d);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMMM yyyy', 'ru');
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: GoogleFonts.manrope(color: AppColors.danger)),
            OutlinedButton(onPressed: _reload, child: const Text('Повторить')),
          ],
        ),
      );
    }
    final day = _dayOrders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(
            children: [
              Expanded(child: Text('Календарь', style: AppTheme.pageTitle)),
              IconButton(
                tooltip: 'Назад',
                onPressed: () => widget.onDateChanged(widget.selectedDate.subtract(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_left),
              ),
              TextButton(
                onPressed: _pickDate,
                child: Text(fmt.format(widget.selectedDate), style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: 'Вперёд',
                onPressed: () => widget.onDateChanged(widget.selectedDate.add(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(onPressed: _reload, icon: const Icon(Icons.refresh, color: AppColors.textMuted)),
              if (widget.onCreate != null)
                ElevatedButton.icon(
                  onPressed: widget.onCreate,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Заказ'),
                ),
            ],
          ),
        ),
        Expanded(
          child: day.isEmpty
              ? Center(
                  child: Text(
                    'Нет заказов на этот день\n(смотрите поле due_date)',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(color: AppColors.textMuted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: day.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final o = day[i];
                    return ListTile(
                      tileColor: AppColors.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      title: Text(
                        '#${o.id} · ${o.clientName ?? 'Клиент'}',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${o.carLabel ?? ''} · ${o.status}',
                        style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12),
                      ),
                      trailing: Text(o.price.toStringAsFixed(0), style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
                      onTap: () async {
                        final changed = await showDialog<bool>(
                          context: context,
                          builder: (_) => _OrderSheetHost(order: o),
                        );
                        if (changed == true) _reload();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Обёртка: переиспользуем _OrderSheet из board через публичный API нельзя —
/// открываем простой диалог статуса здесь же, либо дублируем вызов board sheet.
/// Для простоты — патч статуса прямо.
class _OrderSheetHost extends StatefulWidget {
  const _OrderSheetHost({required this.order});
  final CrmOrder order;
  @override
  State<_OrderSheetHost> createState() => _OrderSheetHostState();
}

class _OrderSheetHostState extends State<_OrderSheetHost> {
  final _api = CrmApi();
  late String _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _status = widget.order.status;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Заказ #${widget.order.id}', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
      content: DropdownButtonFormField<String>(
        value: kCloudStatuses.contains(_status) ? _status : kCloudStatuses[1],
        items: kCloudStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
        onChanged: _busy ? null : (v) => setState(() => _status = v ?? _status),
        decoration: const InputDecoration(labelText: 'Статус'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Закрыть')),
        ElevatedButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await _api.patchOrder(widget.order.id, {'status': _status});
                    if (!mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!mounted) return;
                    setState(() => _busy = false);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.danger));
                  }
                },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class CloudCompletedScreen extends StatefulWidget {
  const CloudCompletedScreen({super.key});

  @override
  State<CloudCompletedScreen> createState() => _CloudCompletedScreenState();
}

class _CloudCompletedScreenState extends State<CloudCompletedScreen> {
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
        _orders = list.where((o) => o.status == 'Выдан').toList();
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: GoogleFonts.manrope(color: AppColors.danger)),
            OutlinedButton(onPressed: _reload, child: const Text('Повторить')),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(
            children: [
              Expanded(child: Text('Завершённые', style: AppTheme.pageTitle)),
              IconButton(onPressed: _reload, icon: const Icon(Icons.refresh, color: AppColors.textMuted)),
            ],
          ),
        ),
        Expanded(
          child: _orders.isEmpty
              ? Center(child: Text('Пока нет выданных', style: GoogleFonts.manrope(color: AppColors.textMuted)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: _orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final o = _orders[i];
                    return ListTile(
                      tileColor: AppColors.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      title: Text('#${o.id} · ${o.clientName ?? ''}', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                      subtitle: Text(o.carLabel ?? '', style: GoogleFonts.manrope(color: AppColors.textMuted)),
                      trailing: Text(o.price.toStringAsFixed(0), style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class CloudWorkshopScreen extends StatefulWidget {
  const CloudWorkshopScreen({super.key, required this.workshop});
  final String workshop;

  @override
  State<CloudWorkshopScreen> createState() => _CloudWorkshopScreenState();
}

class _CloudWorkshopScreenState extends State<CloudWorkshopScreen> {
  final _api = CrmApi();
  List<CrmOrder> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant CloudWorkshopScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workshop != widget.workshop) _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.listOrders();
      final ws = widget.workshop.toLowerCase();
      if (!mounted) return;
      setState(() {
        _orders = list.where((o) {
          if (o.status.toLowerCase().contains(ws)) return true;
          return o.items.any((it) => it.workshop.toLowerCase().contains(ws) || it.name.toLowerCase().contains(ws));
        }).toList();
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: GoogleFonts.manrope(color: AppColors.danger)),
            OutlinedButton(onPressed: _reload, child: const Text('Повторить')),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(
            children: [
              Expanded(child: Text(widget.workshop, style: AppTheme.pageTitle)),
              IconButton(onPressed: _reload, icon: const Icon(Icons.refresh, color: AppColors.textMuted)),
            ],
          ),
        ),
        Expanded(
          child: _orders.isEmpty
              ? Center(child: Text('Нет заказов в цехе', style: GoogleFonts.manrope(color: AppColors.textMuted)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: _orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final o = _orders[i];
                    return ListTile(
                      tileColor: AppColors.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      title: Text('#${o.id} · ${o.clientName ?? ''}', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                      subtitle: Text('${o.status} · ${o.carLabel ?? ''}', style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12)),
                      trailing: Text(o.price.toStringAsFixed(0), style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
