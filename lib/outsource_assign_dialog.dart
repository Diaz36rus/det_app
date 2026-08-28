import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'app_theme.dart';
import 'app_toast.dart';
import 'database.dart';
import 'responsive.dart';

/// Результат назначения аутсорса на работу.
class OutsourceAssignResult {
  const OutsourceAssignResult({
    required this.outsourcerId,
    required this.outsourcerName,
    this.cost,
    this.sentAt,
    this.dueAt,
    this.note = '',
  });

  final int outsourcerId;
  final String outsourcerName;
  final double? cost;
  final String? sentAt;
  final String? dueAt;
  final String note;
}

/// Диалог: выбрать/создать подрядчика + сумма/сроки/заметка.
Future<OutsourceAssignResult?> showOutsourceAssignDialog(
  BuildContext context, {
  int? initialOutsourcerId,
  double? initialCost,
  String? initialSentAt,
  String? initialDueAt,
  String? initialNote,
}) async {
  return showDialog<OutsourceAssignResult>(
    context: context,
    builder: (ctx) => _OutsourceAssignDialog(
      initialOutsourcerId: initialOutsourcerId,
      initialCost: initialCost,
      initialSentAt: initialSentAt,
      initialDueAt: initialDueAt,
      initialNote: initialNote,
    ),
  );
}

class _OutsourceAssignDialog extends StatefulWidget {
  const _OutsourceAssignDialog({
    this.initialOutsourcerId,
    this.initialCost,
    this.initialSentAt,
    this.initialDueAt,
    this.initialNote,
  });

  final int? initialOutsourcerId;
  final double? initialCost;
  final String? initialSentAt;
  final String? initialDueAt;
  final String? initialNote;

  @override
  State<_OutsourceAssignDialog> createState() => _OutsourceAssignDialogState();
}

class _OutsourceAssignDialogState extends State<_OutsourceAssignDialog> {
  List<Map<String, dynamic>> _list = const [];
  bool _loading = true;
  int? _selectedId;
  final _costCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime? _sentAt;
  DateTime? _dueAt;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialOutsourcerId;
    if (widget.initialCost != null) {
      _costCtrl.text = widget.initialCost!.toStringAsFixed(
        widget.initialCost! == widget.initialCost!.roundToDouble() ? 0 : 2,
      );
    }
    _noteCtrl.text = widget.initialNote ?? '';
    _sentAt = _parse(widget.initialSentAt);
    _dueAt = _parse(widget.initialDueAt);
    _load();
  }

  DateTime? _parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.contains('T') ? raw : raw.replaceFirst(' ', 'T'));
  }

  String? _fmt(DateTime? d) {
    if (d == null) return null;
    return DateFormat('yyyy-MM-dd').format(d);
  }

  String _fmtUi(DateTime? d) {
    if (d == null) return 'не задано';
    return DateFormat('dd.MM.yyyy').format(d);
  }

  @override
  void dispose() {
    _costCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper().listOutsourcers();
    if (!mounted) return;
    setState(() {
      _list = rows;
      _loading = false;
      if (_selectedId != null && rows.every((r) => (r['id'] as num).toInt() != _selectedId)) {
        _selectedId = null;
      }
    });
  }

  Future<void> _createNew() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Новый подрядчик', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Имя / компания', isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Телефон', isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Заметка', isDense: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Создать')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.length < 2) {
      if (mounted) showAppToast(context, 'Укажите имя подрядчика');
      return;
    }
    final id = await DatabaseHelper().addOutsourcer(
      name: name,
      phone: phoneCtrl.text,
      note: noteCtrl.text,
    );
    await _load();
    if (mounted) setState(() => _selectedId = id);
  }

  Future<void> _pickDate({required bool sent}) async {
    final initial = (sent ? _sentAt : _dueAt) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (sent) {
        _sentAt = picked;
      } else {
        _dueAt = picked;
      }
    });
  }

  void _submit() {
    if (_selectedId == null) {
      showAppToast(context, 'Выберите подрядчика');
      return;
    }
    Map<String, dynamic>? row;
    for (final r in _list) {
      if ((r['id'] as num).toInt() == _selectedId) {
        row = r;
        break;
      }
    }
    final name = row?['name']?.toString() ?? 'Аутсорс';
    final costRaw = _costCtrl.text.trim().replaceAll(',', '.').replaceAll(' ', '');
    final cost = costRaw.isEmpty ? null : double.tryParse(costRaw);
    Navigator.pop(
      context,
      OutsourceAssignResult(
        outsourcerId: _selectedId!,
        outsourcerName: name,
        cost: cost,
        sentAt: _fmt(_sentAt),
        dueAt: _fmt(_dueAt),
        note: _noteCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Аутсорс', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
      content: SizedBox(
        width: AppResponsive.dialogWidth(context, desktop: 400),
        child: _loading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_list.isEmpty)
                      Text(
                        'Пока нет подрядчиков. Создайте первого.',
                        style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
                      )
                    else
                      ..._list.map((r) {
                        final id = (r['id'] as num).toInt();
                        final phone = r['phone']?.toString() ?? '';
                        return RadioListTile<int>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: id,
                          groupValue: _selectedId,
                          onChanged: (v) => setState(() => _selectedId = v),
                          title: Text(
                            r['name']?.toString() ?? '',
                            style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                          subtitle: phone.isEmpty
                              ? null
                              : Text(phone, style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12)),
                        );
                      }),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _createNew,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text('Новый подрядчик', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _costCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Сумма подрядчику (₽)',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickDate(sent: true),
                            child: Text('Отдали: ${_fmtUi(_sentAt)}', style: GoogleFonts.manrope(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickDate(sent: false),
                            child: Text('Ждём: ${_fmtUi(_dueAt)}', style: GoogleFonts.manrope(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _noteCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Комментарий',
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: _submit,
          child: Text('Назначить', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
