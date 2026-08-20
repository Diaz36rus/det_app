import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_datetime.dart';
import 'app_theme.dart';
import 'database.dart';
import 'db_refresh_mixin.dart';
import 'inventory_catalog.dart';
import 'pulse_anchor.dart';
import 'responsive.dart';
import 'warehouse_category_gallery.dart';

class WarehouseScreen extends StatefulWidget {
  const WarehouseScreen({super.key});

  @override
  State<WarehouseScreen> createState() => _WarehouseScreenState();
}

class _WarehouseScreenState extends State<WarehouseScreen>
    with SingleTickerProviderStateMixin, DbRefreshMixin, PulseHighlightMixin {
  @override
  void onDatabaseChanged() => _load(showSpinner: false);

  late final TabController _tabs;
  static const _pulseAdd = 'wh_add';

  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _moves = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _query = '';
  bool _lowOnly = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner && mounted) setState(() => _isLoading = true);
    await DatabaseHelper().seedStandardInventoryIfNeeded();
    await DatabaseHelper().applyInventoryUnitDefaultsIfNeeded();
    final items = await DatabaseHelper().getInventory();
    final moves = await DatabaseHelper().getInventoryMoves(limit: 200);
    if (!mounted) return;
    setState(() {
      _items = items;
      _moves = moves;
      _isLoading = false;
    });
  }

  bool _isLowStock(Map<String, dynamic> item) {
    final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
    final min = (item['min_qty'] as num?)?.toDouble() ?? 0;
    return qty <= (min > 0 ? min : 0);
  }

  bool _isFilm(Map<String, dynamic> item) =>
      InventoryCategories.isFilm(item['category']?.toString());

  String _fmtQty(double q) {
    if (q == q.roundToDouble()) return q.toStringAsFixed(0);
    return q.toStringAsFixed(2);
  }

  List<Map<String, dynamic>> _itemsForCategory(String category) {
    final q = _query.trim().toLowerCase();
    final list = _items.where((item) {
      final cat = item['category']?.toString() ?? InventoryCategories.other;
      if (cat != category) return false;
      final name = item['name']?.toString() ?? '';
      if (q.isNotEmpty && !name.toLowerCase().contains(q)) return false;
      if (_lowOnly && !_isLowStock(item)) return false;
      return true;
    }).toList();
    list.sort((a, b) {
      final la = _isLowStock(a);
      final lb = _isLowStock(b);
      if (la != lb) return la ? -1 : 1;
      return (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? '');
    });
    return list;
  }

  int _lowCountInCategory(String category) {
    return _items.where((i) {
      final cat = i['category']?.toString() ?? InventoryCategories.other;
      return cat == category && _isLowStock(i);
    }).length;
  }

  Future<void> _openCategory(String category) async {
    await showWarehouseCategoryExpand(
      context: context,
      category: category,
      itemsProvider: () => _itemsForCategory(category),
      emptyHint: _lowOnly ? 'Нет позиций с низким остатком' : 'Пока пусто — добавь позицию',
      onAdd: () => _showItemEditor(initialCategory: category),
      itemBuilder: (item, refresh) => _buildItemCard(
        item,
        afterChange: refresh,
        compact: true,
      ),
    );
    if (mounted) await _load(showSpinner: false);
  }

  Future<void> _showItemEditor({Map<String, dynamic>? item, String? initialCategory}) async {
    final editing = item != null;
    final nameCtrl = TextEditingController(text: item?['name']?.toString() ?? '');
    final qtyCtrl = TextEditingController(text: '${item?['quantity'] ?? 0}');
    final minCtrl = TextEditingController(text: '${item?['min_qty'] ?? 0}');
    final mprCtrl = TextEditingController(
      text: '${item?['meters_per_roll'] ?? 0}',
    );
    var category = item?['category']?.toString() ??
        initialCategory ??
        InventoryCategories.other;
    if (!InventoryCategories.all.contains(category)) {
      category = InventoryCategories.other;
    }
    var unit = InventoryUnits.normalize(
      item?['unit']?.toString(),
      category: category,
    );
    if (!editing) {
      unit = InventoryUnits.defaultFor(category: category, name: nameCtrl.text);
    }

    final pulseId = editing ? (item['id'] as num).toInt() : _pulseAdd;
    final ok = await runWithPulseHighlight(
      pulseId,
      () => showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              final film = InventoryCategories.isFilm(category);
              final unitChoices = InventoryUnits.choicesForCategory(category);
              if (!unitChoices.contains(unit)) {
                unit = unitChoices.first;
              }
              return AlertDialog(
                backgroundColor: AppColors.surface,
                title: Text(
                  editing ? 'Редактировать' : 'Новая позиция',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                ),
                content: SizedBox(
                  width: AppResponsive.dialogWidth(ctx, desktop: 420),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(labelText: 'Название', isDense: true),
                          autofocus: !editing,
                          onChanged: (v) {
                            if (editing) return;
                            setLocal(() {
                              unit = InventoryUnits.defaultFor(category: category, name: v);
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: category,
                          decoration: const InputDecoration(labelText: 'Категория', isDense: true),
                          dropdownColor: AppColors.surface2,
                          items: InventoryCategories.all
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(
                                    c,
                                    style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setLocal(() {
                              category = v;
                              unit = InventoryUnits.defaultFor(
                                category: v,
                                name: nameCtrl.text,
                              );
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: unit,
                          decoration: InputDecoration(
                            labelText: 'Единица учёта',
                            helperText: InventoryUnits.helperFor(unit, category: category),
                            isDense: true,
                          ),
                          dropdownColor: AppColors.surface2,
                          items: unitChoices
                              .map(
                                (u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(
                                    InventoryUnits.menuLabel(u),
                                    style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setLocal(() => unit = v);
                          },
                        ),
                        const SizedBox(height: 10),
                        if (film) ...[
                          TextField(
                            controller: mprCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Метров в полном рулоне',
                              helperText: 'Для прихода и расхода в цехе',
                              isDense: true,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: minCtrl,
                            decoration: InputDecoration(
                              labelText: 'Мин. остаток',
                              suffixText: unit,
                              helperText: '0 = алерт только при нуле',
                              isDense: true,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                          if (editing) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Остаток считается по рулонам ($unit).',
                              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                            ),
                          ],
                        ] else ...[
                          TextField(
                            controller: qtyCtrl,
                            decoration: InputDecoration(
                              labelText: 'Количество',
                              suffixText: unit,
                              isDense: true,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: minCtrl,
                            decoration: InputDecoration(
                              labelText: 'Мин. остаток',
                              suffixText: unit,
                              helperText: '0 = алерт только при нуле',
                              isDense: true,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(editing ? 'Сохранить' : 'Добавить'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
    final minQty = double.tryParse(minCtrl.text.replaceAll(',', '.')) ?? 0;
    final mpr = double.tryParse(mprCtrl.text.replaceAll(',', '.')) ?? 0;
    final film = InventoryCategories.isFilm(category);
    final resolvedUnit = InventoryUnits.normalize(unit, category: category);

    if (editing) {
      await DatabaseHelper().updateInventoryItem(
        (item['id'] as num).toInt(),
        name: name,
        quantity: film ? null : qty,
        unit: resolvedUnit,
        minQty: minQty,
        category: category,
        metersPerRoll: film ? mpr : 0,
      );
    } else {
      await DatabaseHelper().addInventoryItem(
        name,
        film ? 0 : qty,
        resolvedUnit,
        minQty: minQty,
        category: category,
        metersPerRoll: film ? mpr : 0,
      );
    }
    await _load(showSpinner: false);
  }

  /// Приход плёнки = новый рулон (номер UPPERCASE + метры).
  Future<void> _addRollDialog(Map<String, dynamic> item) async {
    final invId = (item['id'] as num).toInt();
    final mpr = (item['meters_per_roll'] as num?)?.toDouble() ?? 0;
    final rollCtrl = TextEditingController();
    final metersCtrl = TextEditingController(
      text: mpr > 0
          ? (mpr == mpr.roundToDouble() ? mpr.toStringAsFixed(0) : mpr.toStringAsFixed(2))
          : '',
    );
    final ok = await runWithPulseHighlight(
      invId,
      () => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Приход · рулон',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: AppResponsive.dialogWidth(ctx, desktop: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item['name']?.toString() ?? '',
                  style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: rollCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Номер рулона',
                    hintText: 'например A12',
                    isDense: true,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [UpperCaseTextFormatter()],
                  autofocus: true,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: metersCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Метров в рулоне',
                    suffixText: 'м',
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Приход'),
            ),
          ],
        ),
      ),
    );
    final rollNo = normalizeRollNumber(rollCtrl.text);
    final meters = double.tryParse(metersCtrl.text.replaceAll(',', '.'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      rollCtrl.dispose();
      metersCtrl.dispose();
    });
    if (ok != true || rollNo.isEmpty) return;
    try {
      await DatabaseHelper().addFilmRoll(
        inventoryId: invId,
        rollNumber: rollNo,
        metersInitial: meters != null && meters > 0 ? meters : null,
      );
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e', style: GoogleFonts.manrope()),
          backgroundColor: AppColors.surface2,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _adjustDialog(Map<String, dynamic> item, {required bool income}) async {
    final invId = (item['id'] as num).toInt();
    // Плёнка: приход = новый рулон (номер + метры). Бренд тут не нужен.
    if (income && _isFilm(item)) {
      await _addRollDialog(item);
      return;
    }
    final qtyCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var brandValue = income ? (item['last_brand']?.toString() ?? '') : '';
    final brands = income ? await DatabaseHelper().listInventoryBrands() : const <String>[];
    if (!mounted) return;
    final ok = await runWithPulseHighlight(
      invId,
      () => showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(
              income ? 'Приход' : 'Списание',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
            ),
            content: SizedBox(
              width: AppResponsive.dialogWidth(ctx, desktop: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item['name']?.toString() ?? '',
                    style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyCtrl,
                    decoration: InputDecoration(
                      labelText: income ? 'Количество (+)' : 'Количество (−)',
                      suffixText: item['unit']?.toString() ?? '',
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                  ),
                  if (income) ...[
                    const SizedBox(height: 10),
                    Autocomplete<String>(
                      initialValue: TextEditingValue(text: brandValue),
                      optionsBuilder: (tv) {
                        final q = tv.text.trim().toLowerCase();
                        if (q.isEmpty) return brands;
                        return brands.where((b) => b.toLowerCase().contains(q));
                      },
                      onSelected: (v) => setLocal(() => brandValue = v),
                      fieldViewBuilder: (context, textCtrl, focusNode, onSubmit) {
                        return TextField(
                          controller: textCtrl,
                          focusNode: focusNode,
                          decoration: const InputDecoration(
                            labelText: 'Бренд',
                            hintText: 'Koch Chemie, CarPro…',
                            helperText: 'Выбрать или ввести новый · остаток по типу',
                            isDense: true,
                          ),
                          textCapitalization: TextCapitalization.words,
                          onChanged: (v) => brandValue = v,
                          onSubmitted: (_) => onSubmit(),
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        final list = options.toList();
                        if (list.isEmpty) return const SizedBox.shrink();
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 6,
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(10),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 340),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: list.length,
                                itemBuilder: (context, i) {
                                  final opt = list[i];
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      opt,
                                      style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13),
                                    ),
                                    onTap: () => onSelected(opt),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'Комментарий', isDense: true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
              ElevatedButton(
                style: income
                    ? null
                    : ElevatedButton.styleFrom(backgroundColor: AppColors.danger.withOpacity(0.9)),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(income ? 'Приход' : 'Списать'),
              ),
            ],
          ),
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      qtyCtrl.dispose();
      noteCtrl.dispose();
    });
    if (ok != true) return;
    final raw = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
    if (raw <= 0) return;
    final delta = income ? raw : -raw;
    await DatabaseHelper().adjustInventoryQuantity(
      invId,
      delta,
      reason: InventoryMoveReasons.manual,
      note: noteCtrl.text.trim().isEmpty
          ? (income ? 'Приход' : 'Списание')
          : noteCtrl.text.trim(),
      brand: income ? brandValue : '',
    );
    await _load(showSpinner: false);
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final invId = (item['id'] as num).toInt();
    final ok = await runWithPulseHighlight(
      invId,
      () => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Удалить позицию?', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          content: Text(
            '${item['name']} будет удалена вместе с движениями и рулонами.',
            style: GoogleFonts.manrope(color: AppColors.textMuted),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await DatabaseHelper().deleteInventoryItem(invId);
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _openRollsDialog(Map<String, dynamic> item) async {
    final invId = (item['id'] as num).toInt();
    await runWithPulseHighlight(
      invId,
      () => showDialog<void>(
        context: context,
        builder: (ctx) => _FilmRollsDialog(
          inventoryId: invId,
          itemName: item['name']?.toString() ?? '',
          metersPerRoll: (item['meters_per_roll'] as num?)?.toDouble() ?? 0,
          onChanged: () => _load(showSpinner: false),
        ),
      ),
    );
    await _load(showSpinner: false);
  }

  Widget _buildStockTab() {
    final mobile = AppResponsive.isMobile(context);
    final pad = mobile ? 12.0 : 24.0;
    final q = _query.trim().toLowerCase();

    // Поиск: плоский список совпадений; иначе — карточки категорий.
    final searchHits = <Map<String, dynamic>>[];
    if (q.isNotEmpty) {
      searchHits.addAll(
        _items.where((item) {
          final name = item['name']?.toString().toLowerCase() ?? '';
          if (!name.contains(q)) return false;
          if (_lowOnly && !_isLowStock(item)) return false;
          return true;
        }),
      );
      searchHits.sort((a, b) {
        final la = _isLowStock(a);
        final lb = _isLowStock(b);
        if (la != lb) return la ? -1 : 1;
        return (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? '');
      });
    }

    final counts = <String, int>{
      for (final c in InventoryCategories.all) c: _itemsForCategory(c).length,
    };
    final lowCounts = <String, int>{
      for (final c in InventoryCategories.all) c: _lowCountInCategory(c),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: AppTheme.panelDecoration,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Поиск по позициям',
                    hintText: 'Название…',
                    prefixIcon: Icon(Icons.search, color: AppColors.textMuted, size: 20),
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: (val) => setState(() => _query = val),
                ),
                const Divider(height: 16, color: AppColors.borderSoft),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        q.isEmpty
                            ? '${_items.length} позиций · ${InventoryCategories.all.length} категорий'
                            : 'Найдено: ${searchHits.length}',
                        style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12.5),
                      ),
                    ),
                    FilterChip(
                      label: Text(
                        'Мало',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: _lowOnly ? AppColors.text : AppColors.textMuted,
                        ),
                      ),
                      selected: _lowOnly,
                      onSelected: (v) => setState(() => _lowOnly = v),
                      selectedColor: AppColors.danger.withOpacity(0.35),
                      backgroundColor: AppColors.bg.withOpacity(0.35),
                      side: BorderSide(color: _lowOnly ? AppColors.danger : AppColors.border),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: q.isNotEmpty
              ? (searchHits.isEmpty
                  ? Center(
                      child: Text(
                        'Ничего не найдено',
                        style: GoogleFonts.manrope(color: AppColors.textDim),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(pad, 0, pad, 28),
                      itemCount: searchHits.length,
                      itemBuilder: (context, i) => _buildItemCard(searchHits[i]),
                    ))
              : Padding(
                  padding: EdgeInsets.fromLTRB(pad, 0, pad, 16),
                  child: WarehouseCategoryGallery(
                    counts: counts,
                    lowCounts: lowCounts,
                    onOpenCategory: _openCategory,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildItemCard(
    Map<String, dynamic> item, {
    VoidCallback? afterChange,
    bool compact = false,
  }) {
    final invId = (item['id'] as num).toInt();
    final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
    final minQty = (item['min_qty'] as num?)?.toDouble() ?? 0;
    final unitRaw = item['unit']?.toString() ?? 'шт';
    final low = _isLowStock(item);
    final film = _isFilm(item);
    final rollsCount = (item['rolls_count'] as num?)?.toInt() ?? 0;
    final rollsMeters = (item['rolls_meters'] as num?)?.toDouble() ?? 0;
    final mpr = (item['meters_per_roll'] as num?)?.toDouble() ?? 0;
    final filmUnit = film ? FilmUnits.normalize(unitRaw) : unitRaw;
    final primaryQty = film
        ? (FilmUnits.isRolls(filmUnit) ? rollsCount.toDouble() : rollsMeters)
        : qty;
    final unit = film ? filmUnit : unitRaw;
    final lastBrand = item['last_brand']?.toString().trim() ?? '';

    final qtyLine = low
        ? '${_fmtQty(primaryQty)} $unit · мало (мин ${_fmtQty(minQty)})'
        : minQty > 0
            ? '${_fmtQty(primaryQty)} $unit · мин ${_fmtQty(minQty)}'
            : '${_fmtQty(primaryQty)} $unit';

    final subtitleParts = <String>[
      qtyLine,
      if (!film && lastBrand.isNotEmpty) lastBrand,
      if (film && FilmUnits.isRolls(filmUnit)) '${_fmtQty(rollsMeters)} м.п.',
      if (film && !FilmUnits.isRolls(filmUnit)) '$rollsCount рул.',
      if (film && mpr > 0) '${_fmtQty(mpr)} м/рул.',
    ];

    final titleColor = compact ? Colors.white : AppColors.text;
    final subColor = low
        ? (compact ? const Color(0xFFFCA5A5) : AppColors.danger)
        : (compact ? Colors.white70 : AppColors.textMuted);
    final bg = compact
        ? (low ? Colors.red.withOpacity(0.18) : Colors.black.withOpacity(0.38))
        : (low ? AppColors.danger.withOpacity(0.06) : AppColors.surface2.withOpacity(0.92));

    Future<void> run(Future<void> Function() action) async {
      await action();
      afterChange?.call();
    }

    return PulseAnchor(
      active: isPulseActive(invId),
      accent: low ? AppColors.danger : AppColors.primary,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(compact ? 12 : AppTheme.radiusLg),
          border: Border(
            left: BorderSide(
              color: (low ? AppColors.danger : AppColors.primary).withOpacity(compact ? 0.9 : 0.75),
              width: 3,
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, compact ? 8 : 10, 6, compact ? 4 : 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['name']?.toString() ?? '',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                            fontSize: compact ? 14 : 15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitleParts.join(' · '),
                          style: GoogleFonts.manrope(
                            color: subColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 0,
                runSpacing: 0,
                alignment: WrapAlignment.end,
                children: [
                  if (film)
                    TextButton(
                      onPressed: () => run(() => _openRollsDialog(item)),
                      child: Text(
                        'Рулоны',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: compact ? Colors.white : null,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Приход',
                    onPressed: () => run(() => _adjustDialog(item, income: true)),
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: compact ? const Color(0xFF93C5FD) : AppColors.primary,
                      size: 22,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Списание',
                    onPressed: () => run(() => _adjustDialog(item, income: false)),
                    icon: Icon(
                      Icons.remove_circle_outline,
                      color: compact ? Colors.white70 : AppColors.textMuted,
                      size: 22,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Изменить',
                    onPressed: () => run(() => _showItemEditor(item: item)),
                    icon: Icon(
                      Icons.edit_outlined,
                      color: compact ? Colors.white54 : AppColors.textDim,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Удалить',
                    onPressed: () => run(() => _deleteItem(item)),
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMovesTab() {
    final mobile = AppResponsive.isMobile(context);
    final pad = mobile ? 12.0 : 24.0;

    if (_moves.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Пока нет складских движений.\nЗдесь приход, закупка и ручные правки — не расход по заказам.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(color: AppColors.textDim, height: 1.35),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(pad, 12, pad, 24),
      itemCount: _moves.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
      itemBuilder: (context, index) {
        final m = _moves[index];
        final delta = (m['delta'] as num?)?.toDouble() ?? 0;
        final income = delta >= 0;
        final color = income ? AppColors.success : AppColors.danger;
        final unit = m['unit']?.toString() ?? '';
        final reason = InventoryMoveReasons.label(m['reason']?.toString() ?? '');
        final roll = m['roll_number']?.toString().trim() ?? '';
        final brand = m['brand']?.toString().trim() ?? '';
        var note = m['note']?.toString().trim() ?? '';
        // Номер рулона уже в meta — убираем дубль из заметки («Рулон A12»).
        if (roll.isNotEmpty && note.isNotEmpty) {
          final esc = RegExp.escape(roll);
          note = note
              .replaceAll(RegExp('рулон\\s+$esc', caseSensitive: false), '')
              .replaceAll(RegExp('рул\\.?\\s*$esc', caseSensitive: false), '')
              .replaceAll(RegExp(r'\s*[·•]\s*[·•]\s*'), ' · ')
              .replaceAll(RegExp(r'^\s*[·•]\s*|\s*[·•]\s*$'), '')
              .trim();
        }
        final when = AppDateTime.formatShort(m['created_at']?.toString());
        final bal = (m['balance_after'] as num?)?.toDouble();

        final meta = [
          reason,
          if (brand.isNotEmpty) brand,
          if (roll.isNotEmpty) 'рул. $roll',
          if (note.isNotEmpty) note,
          when,
        ].where((s) => s.isNotEmpty).join(' · ');

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          title: Text(
            m['inventory_name']?.toString() ?? '—',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 14),
          ),
          subtitle: Text(
            meta,
            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${income ? '+' : ''}${_fmtQty(delta)} $unit',
                style: GoogleFonts.manrope(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              if (bal != null)
                Text(
                  'ост. ${_fmtQty(bal)}',
                  style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 11),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = AppResponsive.isMobile(context);
    final pad = mobile ? 12.0 : 24.0;
    final count = _tabs.index == 0 ? _items.length : _moves.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _tabs.index == 0
          ? PulseAnchor(
              active: isPulseActive(_pulseAdd),
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              child: FloatingActionButton.extended(
                onPressed: () => _showItemEditor(),
                icon: const Icon(Icons.add),
                label: Text('Добавить', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              ),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 8),
            child: Row(
              children: [
                Text('Склад', style: AppTheme.pageTitle),
                const Spacer(),
                Text(
                  '$count',
                  style: GoogleFonts.manrope(
                    color: AppColors.textDim,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: TabBar(
              controller: _tabs,
              onTap: (_) => setState(() {}),
              labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 14),
              unselectedLabelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w500, fontSize: 14),
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textMuted,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'Остатки'),
                Tab(text: 'Движения'),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _buildStockTab(),
                      _buildMovesTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilmRollsDialog extends StatefulWidget {
  final int inventoryId;
  final String itemName;
  final double metersPerRoll;
  final VoidCallback onChanged;

  const _FilmRollsDialog({
    required this.inventoryId,
    required this.itemName,
    required this.metersPerRoll,
    required this.onChanged,
  });

  @override
  State<_FilmRollsDialog> createState() => _FilmRollsDialogState();
}

class _FilmRollsDialogState extends State<_FilmRollsDialog> {
  List<Map<String, dynamic>> _rolls = [];
  bool _loading = true;
  final _rollCtrl = TextEditingController();
  late final TextEditingController _metersCtrl;

  @override
  void initState() {
    super.initState();
    final def = widget.metersPerRoll > 0 ? widget.metersPerRoll : 0;
    _metersCtrl = TextEditingController(
      text: def > 0 ? (def == def.roundToDouble() ? def.toStringAsFixed(0) : def.toStringAsFixed(2)) : '',
    );
    _load();
  }

  @override
  void dispose() {
    _rollCtrl.dispose();
    _metersCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rolls = await DatabaseHelper().listFilmRolls(widget.inventoryId);
    if (!mounted) return;
    setState(() {
      _rolls = rolls;
      _loading = false;
    });
  }

  Future<void> _addRoll() async {
    final num = normalizeRollNumber(_rollCtrl.text);
    if (num.isEmpty) return;
    final meters = double.tryParse(_metersCtrl.text.replaceAll(',', '.'));
    try {
      await DatabaseHelper().addFilmRoll(
        inventoryId: widget.inventoryId,
        rollNumber: num,
        metersInitial: meters,
      );
      _rollCtrl.clear();
      if (widget.metersPerRoll > 0) {
        final def = widget.metersPerRoll;
        _metersCtrl.text =
            def == def.roundToDouble() ? def.toStringAsFixed(0) : def.toStringAsFixed(2);
      }
      widget.onChanged();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e', style: GoogleFonts.manrope()),
          backgroundColor: AppColors.surface2,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _fmt(double q) {
    if (q == q.roundToDouble()) return q.toStringAsFixed(0);
    return q.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Рулоны · ${widget.itemName}',
        style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 16),
      ),
      content: SizedBox(
        width: AppResponsive.dialogWidth(context, desktop: 420),
        child: _loading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_rolls.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Рулонов нет',
                        style: GoogleFonts.manrope(color: AppColors.textDim),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _rolls.length,
                        itemBuilder: (context, index) {
                          final r = _rolls[index];
                          final left = (r['meters_left'] as num?)?.toDouble() ?? 0;
                          final initial = (r['meters_initial'] as num?)?.toDouble() ?? 0;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(
                              r['roll_number']?.toString() ?? '—',
                              style: GoogleFonts.manrope(
                                color: AppColors.text,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              'осталось ${_fmt(left)} м · из ${_fmt(initial)} м',
                              style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12),
                            ),
                          );
                        },
                      ),
                    ),
                  const Divider(height: 20),
                  Text(
                    'Добавить рулон',
                    style: GoogleFonts.manrope(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _rollCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Номер',
                            isDense: true,
                          ),
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [UpperCaseTextFormatter()],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _metersCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Метры',
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Добавить рулон',
                        onPressed: _addRoll,
                        icon: const Icon(Icons.add_circle, color: AppColors.primary),
                      ),
                    ],
                  ),
                ],
              ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Готово'),
        ),
      ],
    );
  }
}
