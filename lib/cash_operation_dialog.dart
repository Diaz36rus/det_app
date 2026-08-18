import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'cash_catalog.dart';
import 'database.dart';
import 'inventory_catalog.dart';
import 'responsive.dart';

/// Диалог создания / редактирования кассовой операции.
class CashOperationDialog extends StatefulWidget {
  final CashTemplate? initialTemplate;
  final int? initialRegisterId;
  final int? editFlowId;

  const CashOperationDialog({
    super.key,
    this.initialTemplate,
    this.initialRegisterId,
    this.editFlowId,
  });

  static Future<bool?> open(
    BuildContext context, {
    CashTemplate? template,
    int? registerId,
    int? editFlowId,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => CashOperationDialog(
        initialTemplate: template,
        initialRegisterId: registerId,
        editFlowId: editFlowId,
      ),
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
  final _invBrandCtrl = TextEditingController();
  List<String> _brands = [];

  List<Map<String, dynamic>> _masters = [];
  List<Map<String, dynamic>> _inventory = [];
  List<Map<String, dynamic>> _registers = [];
  int? _masterId;
  int? _inventoryId;
  int? _registerId;
  double? _payrollHint;
  bool _saving = false;
  bool _loadingEdit = false;
  String? _error;

  bool get _isEdit => widget.editFlowId != null;

  bool get _needsMaster {
    final t = cashTemplateByKey(_templateKey);
    return t?.needsMaster == true || _category == 'Зарплата' || _category == 'Аванс';
  }

  bool get _needsInventory {
    final t = cashTemplateByKey(_templateKey);
    return t?.needsInventory == true || _inventoryId != null;
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
    _registerId = widget.initialRegisterId;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (_isEdit) setState(() => _loadingEdit = true);
    await _loadLookups();
    if (_isEdit) {
      await _loadExisting();
    }
    if (mounted && _isEdit) setState(() => _loadingEdit = false);
  }

  Future<void> _loadExisting() async {
    final row = await DatabaseHelper().getCashFlowById(widget.editFlowId!);
    if (row == null || !mounted) return;
    final type = row['type']?.toString() ?? 'Расход';
    final cats = CashCategories.forType(type);
    final cat = row['category']?.toString() ?? cats.first;
    setState(() {
      _type = type;
      _category = cats.contains(cat) ? cat : cats.first;
      _method = row['method']?.toString() ?? CashMethods.cash;
      _templateKey = row['template_key']?.toString() ?? '';
      _amountCtrl.text = ((row['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(0);
      _descCtrl.text = row['description']?.toString() ?? '';
      _noteCtrl.text = row['note']?.toString() ?? '';
      _counterpartyCtrl.text = row['counterparty']?.toString() ?? '';
      _masterId = (row['master_id'] as num?)?.toInt();
      _inventoryId = (row['inventory_id'] as num?)?.toInt();
      final qty = (row['inventory_qty'] as num?)?.toDouble() ?? 0;
      _invQtyCtrl.text = qty > 0 ? qty.toString() : '1';
      _registerId = (row['register_id'] as num?)?.toInt() ?? _registerId;
    });
    if (_needsMaster && _masterId != null) _refreshPayrollHint();
  }

  Future<void> _loadLookups() async {
    final masters = await DatabaseHelper().getAllMastersFull();
    final inv = await DatabaseHelper().getInventory();
    final regs = await DatabaseHelper().getCashRegisters();
    final brands = await DatabaseHelper().listInventoryBrands();
    if (!mounted) return;
    setState(() {
      _masters = masters;
      _inventory = inv;
      _registers = regs;
      _brands = brands;
      if (_registerId == null && regs.isNotEmpty) {
        Map<String, dynamic>? match;
        for (final r in regs) {
          if (r['money_type']?.toString() == _method) {
            match = r;
            break;
          }
        }
        _registerId = ((match ?? regs.first)['id'] as num).toInt();
      }
    });
    if (_needsMaster && _masterId != null) _refreshPayrollHint();
  }

  Map<String, dynamic>? _selectedInventory() {
    for (final i in _inventory) {
      if ((i['id'] as num?)?.toInt() == _inventoryId) return i;
    }
    return null;
  }

  bool get _selectedInventoryIsFilm =>
      InventoryCategories.isFilm(_selectedInventory()?['category']?.toString());

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
      for (final r in _registers) {
        if (r['money_type']?.toString() == t.method) {
          _registerId = (r['id'] as num).toInt();
          break;
        }
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

    var method = _method;
    if (_registerId != null) {
      for (final r in _registers) {
        if ((r['id'] as num).toInt() == _registerId) {
          method = r['money_type']?.toString() ?? method;
          break;
        }
      }
    }

    if (_isEdit) {
      await DatabaseHelper().updateCashFlow(
        widget.editFlowId!,
        type: _type,
        amount: amount,
        description: desc,
        category: _category,
        method: method,
        registerId: _registerId,
        counterparty: _counterpartyCtrl.text.trim(),
        masterId: _needsMaster ? _masterId : null,
        inventoryId: (_needsInventory && _inventoryId != null) ? _inventoryId : null,
        inventoryQty: invQty,
        templateKey: _templateKey,
        note: _noteCtrl.text.trim(),
        inventoryBrand: (_needsInventory && !_selectedInventoryIsFilm)
            ? _invBrandCtrl.text
            : '',
      );
    } else {
      await DatabaseHelper().addCashFlow(
        _type,
        amount,
        desc,
        category: _category,
        method: method,
        registerId: _registerId,
        counterparty: _counterpartyCtrl.text.trim(),
        masterId: _needsMaster ? _masterId : null,
        inventoryId: (_needsInventory && _inventoryId != null) ? _inventoryId : null,
        inventoryQty: invQty,
        templateKey: _templateKey,
        note: _noteCtrl.text.trim(),
        inventoryBrand: (_needsInventory && !_selectedInventoryIsFilm)
            ? _invBrandCtrl.text
            : '',
      );
    }

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
    _invBrandCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = CashCategories.forType(_type);

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        _isEdit ? 'Изменить операцию' : 'Операция кассы',
        style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: SizedBox(
        width: AppResponsive.dialogWidth(context, desktop: 440),
        child: _loadingEdit
            ? const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            : SingleChildScrollView(
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
                    Text(
                      'Шаблон',
                      style: GoogleFonts.manrope(
                        color: AppColors.textDim,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: kCashTemplates
                          .where((t) => t.type == _type || t.key.startsWith('other'))
                          .map((t) {
                        final selected = _templateKey == t.key;
                        return FilterChip(
                          label: Text(
                            t.label,
                            style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
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
                    if (_registers.isNotEmpty)
                      DropdownButtonFormField<int>(
                        value: _registers.any((r) => (r['id'] as num).toInt() == _registerId)
                            ? _registerId
                            : (_registers.first['id'] as num).toInt(),
                        decoration: const InputDecoration(labelText: 'Касса', isDense: true),
                        dropdownColor: AppColors.surface2,
                        items: _registers
                            .map(
                              (r) => DropdownMenuItem<int>(
                                value: (r['id'] as num).toInt(),
                                child: Text('${r['name']} · ${r['money_type']}'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _registerId = v;
                            for (final r in _registers) {
                              if ((r['id'] as num).toInt() == v) {
                                _method = r['money_type']?.toString() ?? _method;
                                break;
                              }
                            }
                          });
                        },
                      )
                    else
                      DropdownButtonFormField<String>(
                        value: CashMethods.all.contains(_method) ? _method : CashMethods.cash,
                        decoration: const InputDecoration(labelText: 'Способ', isDense: true),
                        dropdownColor: AppColors.surface2,
                        items: CashMethods.all
                            .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                            .toList(),
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
                          ..._masters.map(
                            (m) => DropdownMenuItem<int?>(
                              value: (m['id'] as num).toInt(),
                              child: Text(m['name']?.toString() ?? ''),
                            ),
                          ),
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
                          ..._inventory.map(
                            (i) => DropdownMenuItem<int?>(
                              value: (i['id'] as num).toInt(),
                              child: Text('${i['name']} (${i['quantity']} ${i['unit']})'),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _inventoryId = v;
                            final inv = _selectedInventory();
                            final last = inv?['last_brand']?.toString() ?? '';
                            if (!InventoryCategories.isFilm(inv?['category']?.toString()) &&
                                _invBrandCtrl.text.trim().isEmpty &&
                                last.isNotEmpty) {
                              _invBrandCtrl.text = last;
                            }
                          });
                        },
                      ),
                      if (_inventoryId != null) ...[
                        const SizedBox(height: 10),
                        Builder(
                          builder: (_) {
                            final inv = _selectedInventory();
                            final cat = inv?['category']?.toString();
                            final unit = inv?['unit']?.toString() ?? '';
                            final film = InventoryCategories.isFilm(cat);
                            final filmUnit = film ? FilmUnits.normalize(unit) : unit;
                            final label = film
                                ? (FilmUnits.isRolls(filmUnit)
                                    ? 'Кол-во рулонов'
                                    : 'Кол-во, м.п.')
                                : 'Кол-во на склад';
                            final helper = film && FilmUnits.isRolls(filmUnit)
                                ? 'Метры возьмутся из «метров в рулоне»'
                                : null;
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  controller: _invQtyCtrl,
                                  decoration: InputDecoration(
                                    labelText: label,
                                    suffixText: film ? filmUnit : (unit.isEmpty ? null : unit),
                                    helperText: helper,
                                    isDense: true,
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                                if (!film) ...[
                                  const SizedBox(height: 10),
                                  Autocomplete<String>(
                                    initialValue: TextEditingValue(text: _invBrandCtrl.text),
                                    optionsBuilder: (tv) {
                                      final q = tv.text.trim().toLowerCase();
                                      if (q.isEmpty) return _brands;
                                      return _brands.where((b) => b.toLowerCase().contains(q));
                                    },
                                    onSelected: (v) => _invBrandCtrl.text = v,
                                    fieldViewBuilder: (context, textCtrl, focusNode, onSubmit) {
                                      return TextField(
                                        controller: textCtrl,
                                        focusNode: focusNode,
                                        decoration: const InputDecoration(
                                          labelText: 'Бренд',
                                          hintText: 'Koch Chemie…',
                                          helperText: 'Остаток по типу · бренд в историю',
                                          isDense: true,
                                        ),
                                        textCapitalization: TextCapitalization.words,
                                        onChanged: (v) => _invBrandCtrl.text = v,
                                        onSubmitted: (_) => onSubmit(),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            );
                          },
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
          onPressed: _saving || _loadingEdit ? null : _save,
          child: Text(
            _saving ? '…' : (_isEdit ? 'Сохранить' : 'Добавить'),
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
