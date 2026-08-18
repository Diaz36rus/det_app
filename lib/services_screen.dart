import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'database.dart';
import 'pulse_anchor.dart';
import 'responsive.dart';

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

  Widget _buildServiceRow(Map<String, dynamic> s) {
    final name = s['name']?.toString() ?? "";
    final fixed = (s['fixed_price'] as num?)?.toDouble() ?? 0;
    final isFixed = fixed > 0;

    return PulseAnchor(
      active: isPulseActive('svc_$name'),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                name,
                style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            if (isFixed)
              Expanded(
                flex: 2,
                child: _PriceSaveField(
                  initialValue: fixed.toString(),
                  label: "Фикс",
                  onSave: (val) => _savePrice(name, 'fixed_price', val),
                ),
              )
            else
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    for (int i = 1; i <= 4; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: i == 1 ? 0 : 6),
                          child: _PriceSaveField(
                            initialValue: (s['price$i'] as num?)?.toString() ?? "0",
                            label: "$i кл.",
                            onSave: (val) => _savePrice(name, 'price$i', val),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            IconButton(
              tooltip: "Рецепт списания",
              icon: const Icon(Icons.science_outlined, size: 20, color: AppColors.primary),
              onPressed: () => _openRecipeEditor(s),
            ),
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
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(AppResponsive.isMobile(context) ? 12 : 24, AppResponsive.isMobile(context) ? 12 : 24, AppResponsive.isMobile(context) ? 12 : 24, 8),
            child: Row(
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
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<int>(
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
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _selectedInvId = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _qtyCtrl,
                            decoration: const InputDecoration(labelText: "Кол-во", isDense: true),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        IconButton(
                          tooltip: "Добавить в рецепт",
                          onPressed: _addLine,
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

  const _PriceSaveField({
    required this.initialValue,
    required this.label,
    required this.onSave,
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
    return TextField(
      controller: _controller,
      focusNode: _focus,
      decoration: InputDecoration(
        isDense: true,
        labelText: widget.label,
        labelStyle: GoogleFonts.manrope(fontSize: 10, color: AppColors.textDim),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: GoogleFonts.manrope(color: AppColors.success, fontSize: 13, fontWeight: FontWeight.w600),
      onEditingComplete: () {
        _commit();
        _focus.unfocus();
      },
      onSubmitted: (_) => _commit(),
    );
  }
}
