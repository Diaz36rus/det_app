import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';
import 'database.dart';
import 'order_lead_source.dart';
import 'responsive.dart';

/// Inbox лидов студии → создать заказ (R2).
class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key, this.onCreateOrder});

  final void Function(Map<String, dynamic> lead)? onCreateOrder;

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  List<Map<String, dynamic>> _leads = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await DatabaseHelper().getStudioLeads();
    if (!mounted) return;
    setState(() {
      _leads = rows;
      _loading = false;
    });
  }

  Future<void> _addLead() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final carCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var source = OrderLeadSources.avito;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Новый лид', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: AppResponsive.dialogWidth(ctx, desktop: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Имя', isDense: true),
                    autofocus: true,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Телефон', isDense: true),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: carCtrl,
                    decoration: const InputDecoration(labelText: 'Авто', isDense: true),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: source,
                    decoration: const InputDecoration(labelText: 'Источник', isDense: true),
                    dropdownColor: AppColors.surface2,
                    items: OrderLeadSources.all
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setLocal(() => source = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'Комментарий', isDense: true),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    await DatabaseHelper().addStudioLead(
      name: name,
      phone: phoneCtrl.text,
      carLabel: carCtrl.text,
      leadSource: source,
      note: noteCtrl.text,
    );
    await _load();
  }

  Future<void> _markDone(Map<String, dynamic> lead) async {
    final id = (lead['id'] as num).toInt();
    await DatabaseHelper().updateStudioLead(id, status: 'done');
    await _load();
  }

  Future<void> _delete(Map<String, dynamic> lead) async {
    final id = (lead['id'] as num).toInt();
    await DatabaseHelper().deleteStudioLead(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: AppTheme.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Лиды', style: AppTheme.pageTitle)),
                ElevatedButton.icon(
                  onPressed: _addLead,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Добавить'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Заявки до заезда → заказ на доске',
              style: AppTheme.pageSubtitle,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
            else if (_leads.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    'Пока пусто — добавь заявку с Avito / Telegram',
                    style: GoogleFonts.manrope(color: AppColors.textMuted),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _leads.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final l = _leads[i];
                    final status = l['status']?.toString() ?? 'new';
                    final done = status == 'done' || status == 'converted';
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: AppTheme.panelDecoration,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l['name']?.toString() ?? '—',
                                  style: GoogleFonts.manrope(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: AppColors.text,
                                    decoration: done ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  [
                                    if ((l['phone']?.toString() ?? '').isNotEmpty) l['phone'],
                                    if ((l['car_label']?.toString() ?? '').isNotEmpty) l['car_label'],
                                    OrderLeadSources.display(l['lead_source']?.toString()),
                                  ].whereType<String>().join(' · '),
                                  style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12.5),
                                ),
                                if ((l['note']?.toString() ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    l['note'].toString(),
                                    style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (!done) ...[
                            TextButton(
                              onPressed: () {
                                widget.onCreateOrder?.call(l);
                              },
                              child: Text(
                                'В заказ',
                                style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Закрыть',
                              onPressed: () => _markDone(l),
                              icon: const Icon(Icons.check_circle_outline, size: 20),
                            ),
                          ],
                          IconButton(
                            tooltip: 'Удалить',
                            onPressed: () => _delete(l),
                            icon: Icon(Icons.delete_outline, size: 20, color: AppColors.danger.withOpacity(0.85)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
