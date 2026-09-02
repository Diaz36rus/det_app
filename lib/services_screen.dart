import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'app_toast.dart';
import 'database.dart';
import 'pulse_anchor.dart';
import 'responsive.dart';
import 'tour_keys.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> with PulseHighlightMixin {
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _inventory = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _query = "";

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final services = await DatabaseHelper().getAllServices();
    final inventory = await DatabaseHelper().getInventory();
    if (!mounted) return;
    setState(() {
      _services = services;
      _inventory = inventory;
      _isLoading = false;
    });
  }

  Future<void> _savePrice(String name, String field, String raw) async {
    final p = double.tryParse(raw.replaceAll(',', '.')) ?? 0;
    await DatabaseHelper().updateServicePrice(name, field, p);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Сохранено", style: GoogleFonts.manrope()),
        backgroundColor: AppColors.surface2,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _categorized() {
    final q = _query.trim().toLowerCase();
    final map = <String, List<Map<String, dynamic>>>{};
    for (final s in _services) {
      final name = s['name']?.toString() ?? "";
      if (q.isNotEmpty && !name.toLowerCase().contains(q)) continue;
      final cat = s['category']?.toString() ?? "Прочее";
      map.putIfAbsent(cat, () => []).add(s);
    }
    return map;
  }

  Future<void> _openRecipeEditor(Map<String, dynamic> service) async {
    final serviceName = service['name']?.toString() ?? '';
    if (serviceName.isEmpty) return;
    await runWithPulseHighlight(
      'svc_$serviceName',
      () => showDialog<void>(
        context: context,
        builder: (context) => _RecipeEditorDialog(
          serviceName: serviceName,
          inventory: _inventory,
          onChanged: _loadAll,
        ),
      ),
    );
    _loadAll();
  }

  Future<void> _openServiceEditor({Map<String, dynamic>? existing}) async {
    final result = await showDialog<_ServiceEditorResult>(
      context: context,
      builder: (context) => _ServiceEditorDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    try {
      if (existing == null) {
        await DatabaseHelper().addService(
          name: result.name,
          category: result.category,
          workshop: result.workshop,
          price1: result.price1,
          price2: result.price2,
          price3: result.price3,
          price4: result.price4,
          fixedPrice: result.fixedPrice,
        );
        if (mounted) showAppToast(context, 'Услуга создана');
      } else {
        final id = (existing['id'] as num?)?.toInt();
        if (id == null) return;
        await DatabaseHelper().updateServiceMeta(
          id,
          name: result.name,
          category: result.category,
          workshop: result.workshop,
        );
        final priceName = result.name;
        if (result.fixedPrice > 0) {
          await DatabaseHelper().updateServicePrice(priceName, 'fixed_price', result.fixedPrice);
          await DatabaseHelper().updateServicePrice(priceName, 'price1', 0);
          await DatabaseHelper().updateServicePrice(priceName, 'price2', 0);
          await DatabaseHelper().updateServicePrice(priceName, 'price3', 0);
          await DatabaseHelper().updateServicePrice(priceName, 'price4', 0);
        } else {
          await DatabaseHelper().updateServicePrice(priceName, 'fixed_price', 0);
          await DatabaseHelper().updateServicePrice(priceName, 'price1', result.price1);
          await DatabaseHelper().updateServicePrice(priceName, 'price2', result.price2);
          await DatabaseHelper().updateServicePrice(priceName, 'price3', result.price3);
          await DatabaseHelper().updateServicePrice(priceName, 'price4', result.price4);
        }
        if (mounted) showAppToast(context, 'Услуга обновлена');
      }
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      final msg = e is StateError ? e.message : '$e';
      showAppToast(context, msg);
    }
  }

  Future<void> _confirmDeleteService(Map<String, dynamic> s) async {
    final id = (s['id'] as num?)?.toInt();
    final name = s['name']?.toString() ?? '';
    if (id == null || name.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Удалить услугу?', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: Text(
          '«$name» будет удалена из прайса. Если она уже есть в заказах — скроется, а не сотрётся.',
          style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
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
    );
    if (ok != true || !mounted) return;
    try {
      final soft = await DatabaseHelper().deleteService(id);
      if (mounted) {
        showAppToast(
          context,
          soft ? 'Услуга скрыта (есть в заказах)' : 'Услуга удалена',
        );
      }
      await _loadAll();
    } catch (e) {
      if (mounted) showAppToast(context, '$e');
    }
  }

  Widget _buildServiceRow(Map<String, dynamic> s) {
    final name = s['name']?.toString() ?? "";
    final workshop = s['workshop']?.toString() ?? "";
    final fixed = (s['fixed_price'] as num?)?.toDouble() ?? 0;
    final isFixed = fixed > 0;
    final mobile = AppResponsive.isMobile(context);
    final fixedStr = fixed == fixed.roundToDouble()
        ? fixed.toStringAsFixed(0)
        : fixed.toStringAsFixed(2);

    Widget nameBlock({int maxLines = 2}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            if (workshop.isNotEmpty)
              Text(
                workshop,
                style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11),
              ),
          ],
        );

    Widget priceBlock() {
      if (isFixed) {
        return _PriceSaveField(
          initialValue: fixedStr,
          label: "Фикс",
          compact: mobile,
          onSave: (val) => _savePrice(name, 'fixed_price', val),
        );
      }
      return Row(
        children: [
          for (int i = 1; i <= 4; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: i == 1 ? 0 : (mobile ? 4 : 6)),
                child: _PriceSaveField(
                  initialValue: () {
                    final p = (s['price$i'] as num?)?.toDouble() ?? 0;
                    return p == p.roundToDouble() ? p.toStringAsFixed(0) : '$p';
                  }(),
                  label: mobile ? "$i" : "$i кл.",
                  compact: mobile,
                  onSave: (val) => _savePrice(name, 'price$i', val),
                ),
              ),
            ),
        ],
      );
    }

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: "Рецепт списания",
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: const Icon(Icons.science_outlined, size: 20, color: AppColors.primary),
          onPressed: () => _openRecipeEditor(s),
        ),
        PopupMenuButton<String>(
          tooltip: "Ещё",
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textMuted),
          color: AppColors.surface2,
          onSelected: (v) {
            if (v == 'edit') _openServiceEditor(existing: s);
            if (v == 'delete') _confirmDeleteService(s);
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'edit',
              child: Text('Изменить', style: GoogleFonts.manrope()),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text('Удалить', style: GoogleFonts.manrope(color: AppColors.danger)),
            ),
          ],
        ),
      ],
    );

    return PulseAnchor(
      active: isPulseActive('svc_$name'),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: mobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: nameBlock()),
                      actions,
                    ],
                  ),
                  const SizedBox(height: 8),
                  priceBlock(),
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 3, child: nameBlock(maxLines: 2)),
                  Expanded(flex: isFixed ? 2 : 4, child: priceBlock()),
                  actions,
                ],
              ),
      ),
    );
  }

  Widget _buildServicesTab() {
    final categorized = _categorized();
    final cats = categorized.keys.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(AppResponsive.isMobile(context) ? 12 : 24, 12, AppResponsive.isMobile(context) ? 12 : 24, 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.panelDecoration,
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: "Поиск",
                hintText: "Название услуги…",
                prefixIcon: Icon(Icons.search, color: AppColors.textMuted, size: 20),
                isDense: true,
              ),
              onChanged: (val) => setState(() => _query = val),
            ),
          ),
        ),
        Expanded(
          child: cats.isEmpty
              ? Center(
                  child: Text("Ничего не найдено", style: GoogleFonts.manrope(color: AppColors.textDim)),
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(AppResponsive.isMobile(context) ? 12 : 24, 0, AppResponsive.isMobile(context) ? 12 : 24, 24),
                  itemCount: cats.length,
                  itemBuilder: (context, index) {
                    final catName = cats[index];
                    final items = categorized[catName]!;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: AppTheme.panelDecoration,
                      clipBehavior: Clip.antiAlias,
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          initiallyExpanded: catName == "Тонировка",
                          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          iconColor: AppColors.primary,
                          collapsedIconColor: AppColors.textMuted,
                          title: Text(
                            catName,
                            style: GoogleFonts.manrope(
                              color: AppColors.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Text(
                            "${items.length} услуг",
                            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                          ),
                          children: items.map(_buildServiceRow).toList(),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: TourKeys.servicesArea,
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(AppResponsive.isMobile(context) ? 12 : 24, AppResponsive.isMobile(context) ? 12 : 20, AppResponsive.isMobile(context) ? 12 : 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text("Услуги", style: AppTheme.pageTitle),
                    const Spacer(),
                    Text(
                      "${_services.length}",
                      style: GoogleFonts.manrope(
                        color: AppColors.textDim,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => _openServiceEditor(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Услуга'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Прайс и рецепты работ', style: AppTheme.pageSubtitle),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _buildServicesTab(),
          ),
        ],
      ),
    );
  }
}

class _ServiceEditorResult {
  final String name;
  final String category;
  final String workshop;
  final double price1;
  final double price2;
  final double price3;
  final double price4;
  final double fixedPrice;

  const _ServiceEditorResult({
    required this.name,
    required this.category,
    required this.workshop,
    this.price1 = 0,
    this.price2 = 0,
    this.price3 = 0,
    this.price4 = 0,
    this.fixedPrice = 0,
  });
}

class _ServiceEditorDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;

  const _ServiceEditorDialog({this.existing});

  @override
  State<_ServiceEditorDialog> createState() => _ServiceEditorDialogState();
}

class _ServiceEditorDialogState extends State<_ServiceEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _p1;
  late final TextEditingController _p2;
  late final TextEditingController _p3;
  late final TextEditingController _p4;
  late final TextEditingController _fixed;
  late String _workshop;
  late bool _useFixed;
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name']?.toString() ?? '');
    _category = TextEditingController(text: e?['category']?.toString() ?? 'Прочее');
    final ws = e?['workshop']?.toString() ?? '';
    _workshop = ws;
    final fp = (e?['fixed_price'] as num?)?.toDouble() ?? 0;
    _useFixed = fp > 0;
    _p1 = TextEditingController(text: ((e?['price1'] as num?)?.toDouble() ?? 0).toStringAsFixed(0));
    _p2 = TextEditingController(text: ((e?['price2'] as num?)?.toDouble() ?? 0).toStringAsFixed(0));
    _p3 = TextEditingController(text: ((e?['price3'] as num?)?.toDouble() ?? 0).toStringAsFixed(0));
    _p4 = TextEditingController(text: ((e?['price4'] as num?)?.toDouble() ?? 0).toStringAsFixed(0));
    _fixed = TextEditingController(text: fp > 0 ? fp.toStringAsFixed(0) : '0');
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _p1.dispose();
    _p2.dispose();
    _p3.dispose();
    _p4.dispose();
    _fixed.dispose();
    super.dispose();
  }

  double _parse(String raw) => double.tryParse(raw.replaceAll(',', '.').trim()) ?? 0;

  void _submit() {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    Navigator.pop(
      context,
      _ServiceEditorResult(
        name: n,
        category: _category.text.trim().isEmpty ? 'Прочее' : _category.text.trim(),
        workshop: _workshop,
        price1: _useFixed ? 0 : _parse(_p1.text),
        price2: _useFixed ? 0 : _parse(_p2.text),
        price3: _useFixed ? 0 : _parse(_p3.text),
        price4: _useFixed ? 0 : _parse(_p4.text),
        fixedPrice: _useFixed ? _parse(_fixed.text) : 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workshopItems = <String>{
      '',
      ...WORKSHOPS,
      if (_workshop.isNotEmpty && !WORKSHOPS.contains(_workshop)) _workshop,
    }.toList();

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        _isEdit ? 'Изменить услугу' : 'Новая услуга',
        style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: AppResponsive.dialogWidth(context, desktop: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Название', isDense: true),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _category,
                decoration: const InputDecoration(labelText: 'Категория', isDense: true),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: workshopItems.contains(_workshop) ? _workshop : '',
                decoration: const InputDecoration(labelText: 'Цех', isDense: true),
                dropdownColor: AppColors.surface2,
                items: workshopItems
                    .map(
                      (w) => DropdownMenuItem(
                        value: w,
                        child: Text(w.isEmpty ? 'Не указан' : w),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _workshop = v);
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Фиксированная цена', style: GoogleFonts.manrope(fontSize: 13)),
                value: _useFixed,
                activeColor: AppColors.primary,
                onChanged: (v) => setState(() => _useFixed = v),
              ),
              if (_useFixed)
                TextField(
                  controller: _fixed,
                  decoration: const InputDecoration(labelText: 'Фикс. цена', isDense: true),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                )
              else
                Row(
                  children: [
                    for (final e in [
                      ('1 кл.', _p1),
                      ('2 кл.', _p2),
                      ('3 кл.', _p3),
                      ('4 кл.', _p4),
                    ])
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: e.$2 == _p1 ? 0 : 6),
                          child: TextField(
                            controller: e.$2,
                            decoration: InputDecoration(labelText: e.$1, isDense: true),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: _submit,
          child: Text(_isEdit ? 'Сохранить' : 'Создать'),
        ),
      ],
    );
  }
}

class _RecipeEditorDialog extends StatefulWidget {
  final String serviceName;
  final List<Map<String, dynamic>> inventory;
  final VoidCallback onChanged;

  const _RecipeEditorDialog({
    required this.serviceName,
    required this.inventory,
    required this.onChanged,
  });

  @override
  State<_RecipeEditorDialog> createState() => _RecipeEditorDialogState();
}

class _RecipeEditorDialogState extends State<_RecipeEditorDialog> {
  List<Map<String, dynamic>> _lines = [];
  bool _loading = true;
  int? _selectedInvId;
  final _qtyCtrl = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final lines = await DatabaseHelper().getRecipesForService(widget.serviceName);
    if (!mounted) return;
    setState(() {
      _lines = lines;
      _loading = false;
    });
  }

  Future<void> _addLine() async {
    final invId = _selectedInvId;
    if (invId == null) return;
    final qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '.')) ?? 0;
    if (qty <= 0) return;
    await DatabaseHelper().setRecipeLine(widget.serviceName, invId, qty);
    widget.onChanged();
    _qtyCtrl.text = '1';
    await _load();
  }

  Future<void> _removeLine(int recipeId) async {
    await DatabaseHelper().deleteRecipeLine(recipeId);
    widget.onChanged();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final usedIds = _lines.map((l) => (l['inventory_id'] as num).toInt()).toSet();
    final available = widget.inventory
        .where((i) => !usedIds.contains((i['id'] as num).toInt()))
        .toList();

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        "Рецепт · ${widget.serviceName}",
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
                  Text(
                    "При отметке работы «выполнено» спишется:",
                    style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  if (_lines.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        "Рецепт пуст — списания не будет",
                        style: GoogleFonts.manrope(color: AppColors.textDim),
                      ),
                    )
                  else
                    ..._lines.map((l) {
                      final qty = (l['qty'] as num?)?.toDouble() ?? 0;
                      final qtyStr = qty == qty.roundToDouble()
                          ? qty.toStringAsFixed(0)
                          : qty.toStringAsFixed(2);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          "${l['inventory_name'] ?? '?'} · $qtyStr ${l['unit'] ?? 'шт'}",
                          style: GoogleFonts.manrope(color: AppColors.text, fontWeight: FontWeight.w600),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18, color: AppColors.danger),
                          onPressed: () => _removeLine((l['id'] as num).toInt()),
                        ),
                      );
                    }),
                  const Divider(height: 20),
                  if (widget.inventory.isEmpty)
                    Text(
                      "Сначала добавь материалы в разделе «Склад».",
                      style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
                    )
                  else if (available.isEmpty)
                    Text(
                      "Все материалы уже в рецепте.",
                      style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
                    )
                  else
                    Builder(
                      builder: (context) {
                        final mobile = AppResponsive.isMobile(context);
                        final materialField = DropdownButtonFormField<int>(
                          value: available.any((i) => (i['id'] as num).toInt() == _selectedInvId)
                              ? _selectedInvId
                              : null,
                          decoration: const InputDecoration(labelText: "Материал", isDense: true),
                          dropdownColor: AppColors.surface2,
                          items: available
                              .map(
                                (i) => DropdownMenuItem(
                                  value: (i['id'] as num).toInt(),
                                  child: Text(
                                    i['name']?.toString() ?? '',
                                    style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _selectedInvId = v),
                        );
                        final qtyField = TextField(
                          controller: _qtyCtrl,
                          decoration: InputDecoration(
                            labelText: mobile ? "Количество" : "Кол-во",
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        );
                        final addBtn = IconButton(
                          tooltip: "Добавить в рецепт",
                          onPressed: _addLine,
                          icon: const Icon(Icons.add_circle, color: AppColors.primary),
                        );
                        if (mobile) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              materialField,
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(child: qtyField),
                                  addBtn,
                                ],
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(flex: 3, child: materialField),
                            const SizedBox(width: 8),
                            SizedBox(width: 88, child: qtyField),
                            addBtn,
                          ],
                        );
                      },
                    ),
                ],
              ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Готово"),
        ),
      ],
    );
  }
}

/// Price field that saves on submit and when focus is lost.
class _PriceSaveField extends StatefulWidget {
  final String initialValue;
  final String label;
  final Future<void> Function(String) onSave;
  final bool compact;

  const _PriceSaveField({
    required this.initialValue,
    required this.label,
    required this.onSave,
    this.compact = false,
  });

  @override
  State<_PriceSaveField> createState() => _PriceSaveFieldState();
}

class _PriceSaveFieldState extends State<_PriceSaveField> {
  late final TextEditingController _controller;
  late String _lastSaved;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _lastSaved = widget.initialValue;
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _PriceSaveField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue && !_focus.hasFocus) {
      _controller.text = widget.initialValue;
      _lastSaved = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    final val = _controller.text.trim();
    if (val == _lastSaved) return;
    _lastSaved = val;
    await widget.onSave(val);
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    return TextField(
      controller: _controller,
      focusNode: _focus,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        isDense: true,
        labelText: widget.label,
        labelStyle: GoogleFonts.manrope(
          fontSize: compact ? 9 : 10,
          color: AppColors.textDim,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 8,
          vertical: compact ? 8 : 10,
        ),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: GoogleFonts.manrope(
        color: AppColors.success,
        fontSize: compact ? 12 : 13,
        fontWeight: FontWeight.w600,
      ),
      onEditingComplete: () {
        _commit();
        _focus.unfocus();
      },
      onSubmitted: (_) => _commit(),
    );
  }
}
