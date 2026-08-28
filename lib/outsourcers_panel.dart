import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';
import 'app_toast.dart';
import 'database.dart';
import 'responsive.dart';

/// Справочник подрядчиков (вкладка в «Сотрудники»).
class OutsourcersPanel extends StatefulWidget {
  const OutsourcersPanel({super.key});

  @override
  State<OutsourcersPanel> createState() => _OutsourcersPanelState();
}

class _OutsourcersPanelState extends State<OutsourcersPanel> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  bool _showInactive = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await DatabaseHelper().listOutsourcers(activeOnly: !_showInactive);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final name = _nameCtrl.text.trim();
    if (name.length < 2) {
      showAppToast(context, 'Укажите имя / компанию');
      return;
    }
    await DatabaseHelper().addOutsourcer(name: name, phone: _phoneCtrl.text);
    _nameCtrl.clear();
    _phoneCtrl.clear();
    if (mounted) showAppToast(context, 'Подрядчик добавлен');
    _load();
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final id = (row['id'] as num).toInt();
    final nameCtrl = TextEditingController(text: row['name']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: row['phone']?.toString() ?? '');
    final noteCtrl = TextEditingController(text: row['note']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Подрядчик', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Имя / компания', isDense: true)),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Телефон', isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Заметка', isDense: true)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseHelper().updateOutsourcer(
      id,
      name: nameCtrl.text,
      phone: phoneCtrl.text,
      note: noteCtrl.text,
    );
    _load();
  }

  Future<void> _toggleActive(Map<String, dynamic> row) async {
    final id = (row['id'] as num).toInt();
    final active = (row['is_active'] as num?)?.toInt() != 0;
    await DatabaseHelper().updateOutsourcer(id, isActive: !active);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final mobile = AppResponsive.isMobile(context);
    final hPad = mobile ? 12.0 : 24.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.panelDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('НОВЫЙ ПОДРЯДЧИК', style: AppTheme.sectionLabel),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Имя / компания', isDense: true),
                  onSubmitted: (_) => _add(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Телефон', isDense: true),
                  onSubmitted: (_) => _add(),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: _add,
                    child: Text('Добавить', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
          child: Row(
            children: [
              Text(
                'База аутсорса',
                style: GoogleFonts.manrope(color: AppColors.textDim, fontWeight: FontWeight.w700, fontSize: 12),
              ),
              const Spacer(),
              FilterChip(
                label: Text('Неактивные', style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600)),
                selected: _showInactive,
                onSelected: (v) {
                  setState(() => _showInactive = v);
                  _load();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? Center(
                      child: Text(
                        'Пока пусто — добавьте подрядчика выше',
                        style: GoogleFonts.manrope(color: AppColors.textMuted),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
                      itemCount: _rows.length,
                      itemBuilder: (context, i) {
                        final r = _rows[i];
                        final active = (r['is_active'] as num?)?.toInt() != 0;
                        final phone = r['phone']?.toString() ?? '';
                        final note = r['note']?.toString() ?? '';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                          decoration: BoxDecoration(
                            color: AppColors.surface2.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                            border: Border.all(
                              color: active ? AppColors.borderSoft : AppColors.borderSoft.withOpacity(0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => _edit(r),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r['name']?.toString() ?? '',
                                        style: GoogleFonts.manrope(
                                          color: active ? AppColors.text : AppColors.textDim,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                        ),
                                      ),
                                      if (phone.isNotEmpty)
                                        Text(phone, style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12.5)),
                                      if (note.isNotEmpty)
                                        Text(note, style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12)),
                                      if (!active)
                                        Text(
                                          'неактивен',
                                          style: GoogleFonts.manrope(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w700),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: active ? 'Скрыть' : 'Вернуть',
                                onPressed: () => _toggleActive(r),
                                icon: Icon(
                                  active ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: AppColors.textDim,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
