import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'database.dart';
import 'responsive.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _inventory = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _query = "";

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
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
    await showDialog<void>(
      context: context,
      builder: (context) => _RecipeEditorDialog(
        serviceName: serviceName,
        inventory: _inventory,
        onChanged: _loadAll,
      ),
    );
    _loadAll();
  }

  Future<void> _showAddInventoryDialog() async {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '0');
    final unitCtrl = TextEditingController(text: 'шт');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text("Новая позиция склада", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Название", isDense: true),
              autofocus: true,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: qtyCtrl,
                    decoration: const InputDecoration(labelText: "Количество", isDense: true),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: unitCtrl,
                    decoration: const InputDecoration(labelText: "Ед.", isDense: true),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Отмена")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Добавить")),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
    await DatabaseHelper().addInventoryItem(name, qty, unitCtrl.text.trim());
    _loadAll();
  }

  Future<void> _adjustStock(Map<String, dynamic> item, double delta) async {
    await DatabaseHelper().adjustInventoryQuantity((item['id'] as num).toInt(), delta);
    _loadAll();
  }

  Future<void> _editInventory(Map<String, dynamic> item) async {
    final nameCtrl = TextEditingController(text: item['name']?.toString() ?? '');
    final qtyCtrl = TextEditingController(text: '${item['quantity'] ?? 0}');
    final unitCtrl = TextEditingController(text: item['unit']?.toString() ?? 'шт');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text("Редактировать", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Название", isDense: true),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: qtyCtrl,
                    decoration: const InputDecoration(labelText: "Количество", isDense: true),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: unitCtrl,
                    decoration: const InputDecoration(labelText: "Ед.", isDense: true),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Отмена")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Сохранить")),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
    await DatabaseHelper().updateInventoryItem(
      (item['id'] as num).toInt(),
      name: name,
      quantity: qty,
      unit: unitCtrl.text.trim(),
    );
    _loadAll();
  }

  Future<void> _deleteInventory(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text("Удалить позицию?", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: Text(
          "${item['name']} будет удалена вместе с рецептами.",
          style: GoogleFonts.manrope(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Отмена")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Удалить"),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseHelper().deleteInventoryItem((item['id'] as num).toInt());
    _loadAll();
  }

  Widget _buildServiceRow(Map<String, dynamic> s) {
    final name = s['name']?.toString() ?? "";
    final fixed = (s['fixed_price'] as num?)?.toDouble() ?? 0;
    final isFixed = fixed > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: AppColors.border),
            ),
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
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        border: Border.all(color: AppColors.border),
                      ),
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

  Widget _buildInventoryTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(AppResponsive.isMobile(context) ? 12 : 24, 12, AppResponsive.isMobile(context) ? 12 : 24, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  "Материалы. Списание — по рецепту услуги при отметке «выполнено».",
                  style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showAddInventoryDialog,
                icon: const Icon(Icons.add, size: 18),
                label: Text("Добавить", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _inventory.isEmpty
              ? Center(
                  child: Text(
                    "Склад пуст — добавь материалы",
                    style: GoogleFonts.manrope(color: AppColors.textDim),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(AppResponsive.isMobile(context) ? 12 : 24, 0, AppResponsive.isMobile(context) ? 12 : 24, 24),
                  itemCount: _inventory.length,
                  itemBuilder: (context, index) {
                    final item = _inventory[index];
                    final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
                    final low = qty <= 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        border: Border.all(
                          color: low ? AppColors.danger.withOpacity(0.45) : AppColors.border,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                        title: Text(
                          item['name']?.toString() ?? '',
                          style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: AppColors.text),
                        ),
                        subtitle: Text(
                          "${_fmtQty(qty)} ${item['unit'] ?? 'шт'}",
                          style: GoogleFonts.manrope(
                            color: low ? AppColors.danger : AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: "−1",
                              onPressed: () => _adjustStock(item, -1),
                              icon: const Icon(Icons.remove_circle_outline, color: AppColors.textMuted),
                            ),
                            IconButton(
                              tooltip: "+1",
                              onPressed: () => _adjustStock(item, 1),
                              icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                            ),
                            IconButton(
                              tooltip: "Изменить",
                              onPressed: () => _editInventory(item),
                              icon: const Icon(Icons.edit_outlined, color: AppColors.textDim, size: 20),
                            ),
                            IconButton(
                              tooltip: "Удалить",
                              onPressed: () => _deleteInventory(item),
                              icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _fmtQty(double q) {
    if (q == q.roundToDouble()) return q.toStringAsFixed(0);
    return q.toStringAsFixed(2);
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
                Text("Услуги и склад", style: AppTheme.pageTitle),
                const Spacer(),
                Text(
                  _tabs.index == 0 ? "${_services.length}" : "${_inventory.length}",
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
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TabBar(
              controller: _tabs,
              onTap: (_) => setState(() {}),
              labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 14),
              unselectedLabelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w500, fontSize: 14),
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textMuted,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: "Услуги"),
                Tab(text: "Склад"),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _buildServicesTab(),
                      _buildInventoryTab(),
                    ],
                  ),
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
                      "Сначала добавь материалы на вкладке «Склад».",
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
