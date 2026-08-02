import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'cash_catalog.dart';
import 'database.dart';

/// Диалог создания кассовой операции (шаблон / свободная форма).
class CashOperationDialog extends StatefulWidget {
  final CashTemplate? initialTemplate;

  const CashOperationDialog({super.key, this.initialTemplate});

  static Future<bool?> open(BuildContext context, {CashTemplate? template}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => CashOperationDialog(initialTemplate: template),
    );
  }

  @override
  State<CashOperationDialog> createState() => _CashOperationDialogState();
}

class _CashOperationDialogState extends State<CashOperationDialog> {
  late String _type;
  late String _category;
  late String _method;
  late String _templateKey;
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _counterpartyCtrl = TextEditingController();
  final _invQtyCtrl = TextEditingController(text: '1');

  List<Map<String, dynamic>> _masters = [];
  List<Map<String, dynamic>> _inventory = [];
  int? _masterId;
  int? _inventoryId;
  double? _payrollHint;
  bool _saving = false;
  String? _error;

  bool get _needsMaster {
    final t = cashTemplateByKey(_templateKey);
    return t?.needsMaster == true || _category == 'Зарплата' || _category == 'Аванс';
  }

  bool get _needsInventory {
    final t = cashTemplateByKey(_templateKey);
    return t?.needsInventory == true;
  }

  @override
  void initState() {
    super.initState();
    final t = widget.initialTemplate;
    _type = t?.type ?? 'Расход';
    _category = t?.category ?? CashCategories.forType(_type).first;
    _method = t?.method ?? CashMethods.cash;
    _templateKey = t?.key ?? '';
    _descCtrl.text = t?.defaultDescription ?? '';
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    final masters = await DatabaseHelper().getAllMastersFull();
    final inv = await DatabaseHelper().getInventory();
    if (!mounted) return;
    setState(() {
      _masters = masters;
      _inventory = inv;
    });
    if (_needsMaster && _masterId != null) _refreshPayrollHint();
  }

  Future<void> _refreshPayrollHint() async {
    if (_masterId == null) {
      setState(() => _payrollHint = null);
      return;
    }
    final now = DateTime.now();
    final start = DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month, 1));
    final end = DateFormat('yyyy-MM-dd').format(now);
    final hint = await DatabaseHelper().suggestMasterPayroll(_masterId!, start, end);
    if (!mounted) return;
    setState(() => _payrollHint = hint);
  }

  void _applyTemplate(CashTemplate t) {
    setState(() {
      _templateKey = t.key;
      _type = t.type;
      _category = t.category;
      _method = t.method;
      if (_descCtrl.text.trim().isEmpty ||
          kCashTemplates.any((x) => x.defaultDescription == _descCtrl.text.trim())) {
        _descCtrl.text = t.defaultDescription;
      }
      _error = null;
    });
    if (t.needsMaster) _refreshPayrollHint();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Укажите сумму больше 0');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Укажите описание');
      return;
    }
    if (_needsMaster && _masterId == null) {
      setState(() => _error = 'Выберите мастера');
      return;
    }

    double invQty = 0;
    if (_needsInventory && _inventoryId != null) {
      invQty = double.tryParse(_invQtyCtrl.text.trim().replaceAll(',', '.')) ?? 0;
      if (invQty <= 0) {
        setState(() => _error = 'Укажите количество для склада');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    String desc = _descCtrl.text.trim();
    if (_needsMaster && _masterId != null) {
      String? name;
      for (final m in _masters) {
        if ((m['id'] as num).toInt() == _masterId) {
          name = m['name']?.toString();
          break;
        }
      }
      if (name != null && name.isNotEmpty && !desc.contains(name)) {
        desc = '$desc · $name';
      }
    }

    await DatabaseHelper().addCashFlow(
      _type,
      amount,
      desc,
      category: _category,
      method: _method,
      counterparty: _counterpartyCtrl.text.trim(),
      masterId: _needsMaster ? _masterId : null,
      inventoryId: (_needsInventory && _inventoryId != null) ? _inventoryId : null,
      inventoryQty: invQty,
      templateKey: _templateKey,
      note: _noteCtrl.text.trim(),
    );

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _noteCtrl.dispose();
    _counterpartyCtrl.dispose();
    _invQtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = CashCategories.forType(_type);

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Операция кассы',
        style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Приход', label: Text('Приход')),
                  ButtonSegment(value: 'Расход', label: Text('Расход')),
                ],
                selected: {_type},
                onSelectionChanged: (s) {
                  final next = s.first;
                  setState(() {
                    _type = next;
                    final cats = CashCategories.forType(next);
                    if (!cats.contains(_category)) _category = cats.first;
                  });
                },
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return _type == 'Приход'
                          ? AppColors.success.withOpacity(0.35)
                          : AppColors.danger.withOpacity(0.35);
                    }
                    return AppColors.surface2;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return _type == 'Приход' ? AppColors.success : AppColors.danger;
                    }
                    return AppColors.textMuted;
                  }),
                  side: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return BorderSide(
                        color: _type == 'Приход' ? AppColors.success : AppColors.danger,
                      );
                    }
                    return const BorderSide(color: AppColors.border);
                  }),
                ),
              ),
              const SizedBox(height: 12),
              Text('Шаблон', style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: kCashTemplates.where((t) => t.type == _type || t.key.startsWith('other')).map((t) {
                  final selected = _templateKey == t.key;
                  return FilterChip(
                    label: Text(t.label, style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600)),
                    selected: selected,
                    onSelected: (_) => _applyTemplate(t),
                    selectedColor: AppColors.primary.withOpacity(0.35),
                    backgroundColor: AppColors.surface2,
                    side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: categories.contains(_category) ? _category : categories.first,
                decoration: const InputDecoration(labelText: 'Категория', isDense: true),
                dropdownColor: AppColors.surface2,
                items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _category = v);
                  if (v == 'Зарплата') _refreshPayrollHint();
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: CashMethods.all.contains(_method) ? _method : CashMethods.cash,
                decoration: const InputDecoration(labelText: 'Способ', isDense: true),
                dropdownColor: AppColors.surface2,
                items: CashMethods.all.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _method = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _amountCtrl,
                decoration: const InputDecoration(labelText: 'Сумма ₽', isDense: true),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              if (_needsMaster) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  value: _masterId,
                  decoration: const InputDecoration(labelText: 'Мастер', isDense: true),
                  dropdownColor: AppColors.surface2,
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('— выберите —')),
                    ..._masters.map((m) => DropdownMenuItem<int?>(
                          value: (m['id'] as num).toInt(),
                          child: Text(m['name']?.toString() ?? ''),
                        )),
                  ],
                  onChanged: (v) {
                    setState(() => _masterId = v);
                    _refreshPayrollHint();
                  },
                ),
                if (_payrollHint != null && _payrollHint! > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    'По работам за месяц ≈ ${NumberFormat('#,##0.##', 'ru_RU').format(_payrollHint)} ₽ — подсказка, не авто',
                    style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        _amountCtrl.text = _payrollHint!.toStringAsFixed(0);
                      },
                      child: const Text('Подставить'),
                    ),
                  ),
                ],
              ],
              if (_needsInventory) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  value: _inventoryId,
                  decoration: const InputDecoration(labelText: 'На склад (опционально)', isDense: true),
                  dropdownColor: AppColors.surface2,
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('— без склада —')),
                    ..._inventory.map((i) => DropdownMenuItem<int?>(
                          value: (i['id'] as num).toInt(),
                          child: Text('${i['name']} (${i['quantity']} ${i['unit']})'),
                        )),
                  ],
                  onChanged: (v) => setState(() => _inventoryId = v),
                ),
                if (_inventoryId != null) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _invQtyCtrl,
                    decoration: const InputDecoration(labelText: 'Кол-во на склад', isDense: true),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Описание', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _counterpartyCtrl,
                decoration: const InputDecoration(labelText: 'Контрагент (необяз.)', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(labelText: 'Заметка (необяз.)', isDense: true),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: GoogleFonts.manrope(color: AppColors.danger, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '…' : 'Добавить', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
