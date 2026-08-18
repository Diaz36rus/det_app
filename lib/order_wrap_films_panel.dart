import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';
import 'app_toast.dart';
import 'database.dart';
import 'inventory_catalog.dart';

/// Расход плёнки по заказу (м.п.). В цехе «Оклейка» — collapsible для мастера.
class OrderWrapFilmsPanel extends StatefulWidget {
  final int orderId;
  final bool collapsible;
  final bool initiallyExpanded;
  /// Какие складские категории показывать в выборе (оклейка / тонировка).
  /// Пусто = обе плёночные категории.
  final List<String> filmCategories;

  const OrderWrapFilmsPanel({
    super.key,
    required this.orderId,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.filmCategories = const [
      InventoryCategories.filmWrap,
      InventoryCategories.filmTint,
    ],
  });

  @override
  State<OrderWrapFilmsPanel> createState() => _OrderWrapFilmsPanelState();
}

class _FilmRow {
  int filmId;
  int? rollId;
  final TextEditingController metersCtrl;
  final FocusNode metersFocus;
  List<Map<String, dynamic>> rolls = [];

  _FilmRow({required this.filmId, this.rollId, required String metersText})
      : metersCtrl = TextEditingController(text: metersText),
        metersFocus = FocusNode();

  double get meters {
    final t = metersCtrl.text.trim().replaceAll(',', '.');
    return double.tryParse(t) ?? 0;
  }

  void dispose() {
    metersCtrl.dispose();
    metersFocus.dispose();
  }

  Map<String, dynamic> toMap() => {
        'filmId': filmId,
        'rollId': rollId,
        'meters': meters,
      };
}

class _OrderWrapFilmsPanelState extends State<OrderWrapFilmsPanel> {
  List<Map<String, dynamic>> _catalog = [];
  final List<_FilmRow> _rows = [];
  bool _loading = true;
  bool _saving = false;
  late bool _expanded;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _load();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  String _fmtMeters(double m) {
    if (m == m.roundToDouble()) return m.toStringAsFixed(0);
    return m.toStringAsFixed(1);
  }

  void _clearRows() {
    for (final r in _rows) {
      r.dispose();
    }
    _rows.clear();
  }

  int? _inventoryIdForFilm(int filmId) {
    for (final f in _catalog) {
      if ((f['id'] as num).toInt() == filmId) {
        return (f['inventory_id'] as num?)?.toInt();
      }
    }
    return null;
  }

  Future<void> _loadRolls(_FilmRow row) async {
    final invId = _inventoryIdForFilm(row.filmId);
    if (invId == null) {
      row.rolls = [];
      return;
    }
    row.rolls = await DatabaseHelper().listFilmRolls(invId);
  }

  String _filmLabel(Map<String, dynamic> film) {
    final name = film['name']?.toString() ?? '—';
    final cat = film['inventory_category']?.toString() ?? '';
    final multi = widget.filmCategories.length > 1;
    if (!multi) return name;
    if (cat == InventoryCategories.filmTint) return 'Тонировка · $name';
    if (cat == InventoryCategories.filmWrap) return 'Оклейка · $name';
    return name;
  }

  Future<void> _load() async {
    try {
      final allow = widget.filmCategories
          .where(InventoryCategories.isFilm)
          .toList();
      final all = await DatabaseHelper().listWrapFilms();
      final current = await DatabaseHelper().getOrderWrapFilms(widget.orderId);
      final keepIds = current.map((r) => (r['film_id'] as num).toInt()).toSet();
      final catalog = all.where((f) {
        final id = (f['id'] as num).toInt();
        if (keepIds.contains(id)) return true;
        final cat = f['inventory_category']?.toString();
        if (allow.isEmpty) return InventoryCategories.isFilm(cat);
        return allow.contains(cat);
      }).toList();
      if (!mounted) return;
      _clearRows();
      _catalog = catalog;
      for (final r in current) {
        final meters = (r['meters'] as num?)?.toDouble() ?? 0;
        final row = _FilmRow(
          filmId: (r['film_id'] as num).toInt(),
          rollId: (r['roll_id'] as num?)?.toInt(),
          metersText: meters > 0 ? _fmtMeters(meters) : '',
        );
        row.metersFocus.addListener(() => _onMetersFocus(row));
        await _loadRolls(row);
        _rows.add(row);
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppToast(context, 'Плёнки: не удалось загрузить — $e');
    }
  }

  void _onMetersFocus(_FilmRow row) {
    if (!row.metersFocus.hasFocus) {
      unawaited(_save(showOk: false));
    }
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_save(showOk: false));
    });
  }

  Future<void> _save({bool showOk = false}) async {
    if (_saving) return;
    _saving = true;
    try {
      final payload = _rows.map((r) => r.toMap()).toList();
      final warnings = await DatabaseHelper().setOrderWrapFilms(widget.orderId, payload);
      if (!mounted) return;
      if (warnings.isNotEmpty) {
        showAppToast(context, warnings.first);
      } else if (showOk) {
        showAppToast(context, 'Расход плёнки сохранён');
      }
      setState(() {});
    } catch (e) {
      if (mounted) showAppToast(context, 'Не сохранилось: $e');
    } finally {
      _saving = false;
    }
  }

  double get _totalMeters => _rows.fold<double>(0, (s, r) => s + r.meters);

  Future<void> _addFilmToCatalog() async {
    final nameCtrl = TextEditingController();
    final mprCtrl = TextEditingController(text: '15');
    final allowedCats = widget.filmCategories.where(InventoryCategories.isFilm).toList();
    var category = allowedCats.contains(InventoryCategories.filmWrap)
        ? InventoryCategories.filmWrap
        : (allowedCats.isNotEmpty ? allowedCats.first : InventoryCategories.filmWrap);
    var unit = FilmUnits.meters;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Новая плёнка', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Название',
                    hintText: 'например HAUT Titan',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Категория', isDense: true),
                  items: [
                    if (allowedCats.isEmpty || allowedCats.contains(InventoryCategories.filmWrap))
                      const DropdownMenuItem(
                        value: InventoryCategories.filmWrap,
                        child: Text('Плёнка оклейка'),
                      ),
                    if (allowedCats.isEmpty || allowedCats.contains(InventoryCategories.filmTint))
                      const DropdownMenuItem(
                        value: InventoryCategories.filmTint,
                        child: Text('Плёнка тонировка'),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setLocal(() => category = v);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: unit,
                  decoration: const InputDecoration(
                    labelText: 'Единица учёта на складе',
                    helperText: 'Расход в заказе — всегда м.п.',
                    isDense: true,
                  ),
                  items: FilmUnits.choices
                      .map(
                        (u) => DropdownMenuItem(
                          value: u,
                          child: Text(u == FilmUnits.rolls ? 'Рулоны (рул.)' : 'Метры погонные (м.п.)'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setLocal(() => unit = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: mprCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Метров в полном рулоне',
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, {
                'name': nameCtrl.text,
                'category': category,
                'mpr': mprCtrl.text,
                'unit': unit,
              }),
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameCtrl.dispose();
      mprCtrl.dispose();
    });
    if (result == null) return;
    final trimmed = (result['name']?.toString() ?? '').trim();
    if (trimmed.isEmpty) return;
    final mpr = double.tryParse((result['mpr']?.toString() ?? '').replaceAll(',', '.')) ?? 0;
    try {
      final id = await DatabaseHelper().addWrapFilm(
        trimmed,
        category: result['category']?.toString() ?? InventoryCategories.filmWrap,
        metersPerRoll: mpr,
        unit: result['unit']?.toString() ?? FilmUnits.meters,
      );
      final catalog = await DatabaseHelper().listWrapFilms();
      if (!mounted) return;
      final row = _FilmRow(filmId: id, metersText: '');
      row.metersFocus.addListener(() => _onMetersFocus(row));
      await _loadRolls(row);
      setState(() {
        _catalog = catalog;
        _rows.add(row);
        _expanded = true;
      });
      await _save(showOk: true);
    } catch (e) {
      if (mounted) showAppToast(context, 'Плёнка не добавлена: $e');
    }
  }

  Future<void> _addRollForRow(_FilmRow row) async {
    final invId = _inventoryIdForFilm(row.filmId);
    if (invId == null) {
      showAppToast(context, 'Плёнка не связана со складом');
      return;
    }
    final rollCtrl = TextEditingController();
    final mpr = (_catalog.cast<Map<String, dynamic>?>().firstWhere(
              (f) => f != null && (f['id'] as num).toInt() == row.filmId,
              orElse: () => null,
            )?['meters_per_roll'] as num?)
            ?.toDouble() ??
        0;
    final metersCtrl = TextEditingController(text: mpr > 0 ? _fmtMeters(mpr) : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Новый рулон', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: rollCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [UpperCaseTextFormatter()],
              decoration: const InputDecoration(
                labelText: 'Номер рулона',
                hintText: 'A-14',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: metersCtrl,
              decoration: const InputDecoration(labelText: 'Метров в рулоне', isDense: true),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Добавить')),
        ],
      ),
    );
    final rollNo = normalizeRollNumber(rollCtrl.text);
    final meters = double.tryParse(metersCtrl.text.replaceAll(',', '.')) ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      rollCtrl.dispose();
      metersCtrl.dispose();
    });
    if (ok != true || rollNo.isEmpty) return;
    try {
      final rollId = await DatabaseHelper().addFilmRoll(
        inventoryId: invId,
        rollNumber: rollNo,
        metersInitial: meters > 0 ? meters : null,
      );
      await _loadRolls(row);
      if (!mounted) return;
      setState(() => row.rollId = rollId);
      await _save(showOk: false);
      if (!mounted) return;
      showAppToast(context, 'Рулон $rollNo добавлен на склад');
    } catch (e) {
      if (mounted) showAppToast(context, 'Рулон не добавлен: $e');
    }
  }

  Future<void> _addRow() async {
    if (_catalog.isEmpty) {
      await _addFilmToCatalog();
      return;
    }
    final row = _FilmRow(
      filmId: (_catalog.first['id'] as num).toInt(),
      metersText: '',
    );
    row.metersFocus.addListener(() => _onMetersFocus(row));
    await _loadRolls(row);
    setState(() {
      _rows.add(row);
      _expanded = true;
    });
    await _save(showOk: false);
  }

  Widget _headerButton() {
    final n = _rows.length;
    final meters = _totalMeters;
    final subtitle = n == 0
        ? 'Не заполнено — плёнка, рулон, расход'
        : '$n поз. · ${meters.toStringAsFixed(1)} м.п.';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(
                Icons.layers_outlined,
                size: 20,
                color: n == 0 ? AppColors.primary : AppColors.success,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Плёнки · расход',
                      style: GoogleFonts.manrope(
                        color: AppColors.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.manrope(
                        color: n == 0 ? AppColors.textMuted : AppColors.success,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (_saving)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                )
              else
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rowCard(int index) {
    final row = _rows[index];
    final filmValue = _catalog.any((f) => (f['id'] as num).toInt() == row.filmId) ? row.filmId : null;
    final rollValue = row.rolls.any((r) => (r['id'] as num).toInt() == row.rollId) ? row.rollId : null;
    final stock = (_catalog.cast<Map<String, dynamic>?>().firstWhere(
              (f) => f != null && (f['id'] as num).toInt() == row.filmId,
              orElse: () => null,
            )?['stock_meters'] as num?)
            ?.toDouble();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<int>(
            value: filmValue,
            isDense: true,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Плёнка',
              isDense: true,
              helperText: stock == null ? null : 'На складе: ${_fmtMeters(stock)} м',
            ),
            items: _catalog
                .map(
                  (film) => DropdownMenuItem<int>(
                    value: (film['id'] as num).toInt(),
                    child: Text(_filmLabel(film), overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (id) async {
              if (id == null) return;
              setState(() {
                row.filmId = id;
                row.rollId = null;
              });
              await _loadRolls(row);
              setState(() {});
              await _save(showOk: false);
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: rollValue,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Рулон №', isDense: true),
                  items: row.rolls
                      .map(
                        (r) => DropdownMenuItem<int>(
                          value: (r['id'] as num).toInt(),
                          child: Text(
                            '${r['roll_number']} · ${_fmtMeters((r['meters_left'] as num?)?.toDouble() ?? 0)} м',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (id) async {
                    setState(() => row.rollId = id);
                    await _save(showOk: false);
                  },
                ),
              ),
              IconButton(
                tooltip: 'Новый рулон на склад',
                onPressed: () => _addRollForRow(row),
                icon: const Icon(Icons.qr_code_2_outlined, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.metersCtrl,
                  focusNode: row.metersFocus,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Расход, м.п.',
                    hintText: 'например 12.5',
                    isDense: true,
                  ),
                  onChanged: (_) => _scheduleSave(),
                  onSubmitted: (_) => _save(showOk: true),
                ),
              ),
              IconButton(
                tooltip: 'Удалить',
                onPressed: () async {
                  setState(() {
                    row.dispose();
                    _rows.removeAt(index);
                  });
                  await _save(showOk: false);
                },
                icon: const Icon(Icons.remove_circle_outline, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body() {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, widget.collapsible ? 4 : 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ElevatedButton.icon(
                onPressed: _addRow,
                icon: const Icon(Icons.add, size: 18),
                label: Text('Строка', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              ),
              OutlinedButton(
                onPressed: _addFilmToCatalog,
                child: Text('Новая плёнка', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: () => _save(showOk: true),
                child: Text('Сохранить', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (_catalog.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Сначала «Новая плёнка» — попадёт на склад, затем рулон и расход.',
                style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
              ),
            )
          else
            ...List.generate(_rows.length, _rowCard),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (!widget.collapsible) {
      return Container(
        decoration: AppTheme.panelDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Text(
                'Плёнки · расход',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
            _body(),
          ],
        ),
      );
    }

    return Container(
      decoration: AppTheme.panelDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headerButton(),
          if (_expanded) ...[
            const Divider(height: 1),
            _body(),
          ],
        ],
      ),
    );
  }
}
