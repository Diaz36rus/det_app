import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'database.dart';
import 'order_details_dialog.dart';
import 'vehicle_marking/vehicle_part.dart';
import 'vehicle_marking/vehicle_schema_view.dart';

enum TintFilmType { athermal, armor, tint }

class TintZoneQuote {
  TintFilmType? filmType;
  int? tintPercent;

  TintZoneQuote({this.filmType, this.tintPercent});
}

const List<int> kTintPercents = [5, 15, 50];

const Map<TintFilmType, String> kTintFilmLabels = {
  TintFilmType.athermal: 'Атермальная',
  TintFilmType.armor: 'Бронеплёнка',
  TintFilmType.tint: 'Тонировочная',
};

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final Map<String, TintZoneQuote> _quotes = {};
  final _amountController = TextEditingController();

  static const _quoteOrder = ['windshield', 'front_sides', 'rear_sides', 'rear'];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Set<String> get _selectedIds => _quotes.keys.toSet();

  List<String> get _orderedSelected =>
      _quoteOrder.where(_quotes.containsKey).toList();

  void _toggleQuote(String quoteId) {
    setState(() {
      if (_quotes.containsKey(quoteId)) {
        _quotes.remove(quoteId);
      } else {
        _quotes[quoteId] = TintZoneQuote();
      }
    });
  }

  void _removeQuote(String quoteId) {
    setState(() => _quotes.remove(quoteId));
  }

  void _setFilmType(String quoteId, TintFilmType type) {
    setState(() {
      final q = _quotes[quoteId];
      if (q == null) return;
      q.filmType = type;
      if (type != TintFilmType.tint) {
        q.tintPercent = null;
      }
    });
  }

  void _setTintPercent(String quoteId, int percent) {
    setState(() {
      final q = _quotes[quoteId];
      if (q == null || q.filmType != TintFilmType.tint) return;
      q.tintPercent = percent;
    });
  }

  String _selectionSummary(TintZoneQuote q) {
    final type = q.filmType;
    if (type == null) return 'Выберите плёнку';
    final label = kTintFilmLabels[type]!;
    if (type == TintFilmType.tint) {
      if (q.tintPercent == null) return '$label · выберите %';
      return '$label · ${q.tintPercent}%';
    }
    return label;
  }

  String _workName(String quoteId, TintZoneQuote q) {
    final zone = tintQuoteLabels[quoteId] ?? quoteId;
    final film = kTintFilmLabels[q.filmType!]!;
    if (q.filmType == TintFilmType.tint) {
      return 'Тонировка · $zone · $film ${q.tintPercent}%';
    }
    return 'Тонировка · $zone · $film';
  }

  double? _parseAmount() {
    final raw = _amountController.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  String? _validateQuote() {
    if (_quotes.isEmpty) return 'Отметьте стёкла на схеме';
    for (final id in _orderedSelected) {
      final q = _quotes[id]!;
      if (q.filmType == null) {
        return 'Выберите плёнку: ${tintQuoteLabels[id]}';
      }
      if (q.filmType == TintFilmType.tint && q.tintPercent == null) {
        return 'Выберите %: ${tintQuoteLabels[id]}';
      }
    }
    final amount = _parseAmount();
    if (amount == null || amount <= 0) return 'Укажите сумму больше 0';
    return null;
  }

  List<Map<String, dynamic>> _buildItems(double amount) {
    final ids = _orderedSelected;
    return [
      for (int i = 0; i < ids.length; i++)
        {
          'name': _workName(ids[i], _quotes[ids[i]]!),
          'price': i == 0 ? amount : 0.0,
          'workshop': 'Оклейка',
          'category': 'Тонировка',
        },
    ];
  }

  void _clearQuote() {
    setState(() {
      _quotes.clear();
      _amountController.clear();
    });
  }

  Future<void> _afterOrderCreated(int orderId) async {
    _clearQuote();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Добавлено в заказ #$orderId", style: GoogleFonts.manrope()),
        backgroundColor: AppColors.surface2,
        behavior: SnackBarBehavior.floating,
      ),
    );
    final full = await DatabaseHelper().getOrderById(orderId);
    if (full != null && mounted) {
      await OrderDetailsDialog.open(context, full);
    }
  }

  Future<void> _showToOrderDialog() async {
    final err = _validateQuote();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err, style: GoogleFonts.manrope()),
          backgroundColor: AppColors.danger.withOpacity(0.9),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final amount = _parseAmount()!;
    final items = _buildItems(amount);

    await showDialog(
      context: context,
      builder: (context) => _TintToOrderDialog(
        items: items,
        amount: amount,
        onDone: _afterOrderCreated,
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 6),
      child: FilterChip(
        label: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.text : AppColors.textMuted,
          ),
        ),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.surface2,
        checkmarkColor: AppColors.text,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }

  Widget _buildZoneCard(String id) {
    final quote = _quotes[id]!;
    final label = tintQuoteLabels[id] ?? id;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.manrope(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                tooltip: "Снять",
                icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                onPressed: () => _removeQuote(id),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            children: [
              for (final type in TintFilmType.values)
                _chip(
                  label: kTintFilmLabels[type]!,
                  selected: quote.filmType == type,
                  onTap: () => _setFilmType(id, type),
                ),
            ],
          ),
          if (quote.filmType == TintFilmType.tint) ...[
            const SizedBox(height: 2),
            Text(
              "Процент тонировки",
              style: GoogleFonts.manrope(
                color: AppColors.textDim,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              children: [
                for (final p in kTintPercents)
                  _chip(
                    label: '$p%',
                    selected: quote.tintPercent == p,
                    onTap: () => _setTintPercent(id, p),
                  ),
              ],
            ),
          ],
          Text(
            _selectionSummary(quote),
            style: GoogleFonts.manrope(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasQuotes = _quotes.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Row(
              children: [
                Text("Тонировка", style: AppTheme.pageTitle),
                const Spacer(),
                Text(
                  "Вид сверху",
                  style: GoogleFonts.manrope(
                    color: AppColors.textDim,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        border: Border.all(color: AppColors.border),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: VehicleSchemaView(
                        selectedQuoteIds: _selectedIds,
                        onQuoteToggle: _toggleQuote,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        border: Border.all(color: AppColors.border),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text("Смета", style: AppTheme.sectionTitle),
                          const SizedBox(height: 4),
                          Text(
                            "Стекло → плёнка → сумма → заказ",
                            style: GoogleFonts.manrope(
                              color: AppColors.textDim,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Expanded(
                            child: !hasQuotes
                                ? Center(
                                    child: Text(
                                      "Отметьте стёкла на схеме",
                                      style: GoogleFonts.manrope(color: AppColors.textDim),
                                      textAlign: TextAlign.center,
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: _orderedSelected.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                                    itemBuilder: (context, index) =>
                                        _buildZoneCard(_orderedSelected[index]),
                                  ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "Сумма",
                            style: GoogleFonts.manrope(
                              color: AppColors.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _amountController,
                            enabled: hasQuotes,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                            ],
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: hasQuotes ? "0" : "Сначала отметьте зоны",
                              suffixText: "₽",
                              suffixStyle: GoogleFonts.manrope(
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: GoogleFonts.manrope(
                              color: AppColors.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: hasQuotes ? _showToOrderDialog : null,
                            child: Text(
                              "В заказ",
                              style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Диалог: добавить тонировку в существующий или новый заказ.
class _TintToOrderDialog extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final double amount;
  final Future<void> Function(int orderId) onDone;

  const _TintToOrderDialog({
    required this.items,
    required this.amount,
    required this.onDone,
  });

  @override
  State<_TintToOrderDialog> createState() => _TintToOrderDialogState();
}

class _TintToOrderDialogState extends State<_TintToOrderDialog> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Map<String, dynamic>> _activeOrders = [];
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _cars = [];
  String _orderQuery = "";
  int? _selectedOrderId;
  int? _selectedClientId;
  int? _selectedCarId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final orders = await DatabaseHelper().getAllOrders();
    final clients = await DatabaseHelper().getClientsList();
    if (!mounted) return;
    setState(() {
      _activeOrders = orders;
      _clients = clients;
      _loading = false;
    });
  }

  Future<void> _onClientChanged(int? clientId) async {
    setState(() {
      _selectedClientId = clientId;
      _selectedCarId = null;
      _cars = [];
    });
    if (clientId == null) return;
    final cars = await DatabaseHelper().getClientCars(clientId);
    if (!mounted) return;
    setState(() {
      _cars = cars;
      if (cars.length == 1) _selectedCarId = cars.first['id'] as int;
    });
  }

  List<Map<String, dynamic>> get _filteredOrders {
    final q = _orderQuery.trim().toLowerCase();
    if (q.isEmpty) return _activeOrders;
    return _activeOrders.where((o) {
      final blob = "${o['id']} ${o['client_name']} ${o['client_phone']} ${o['make_model']} ${o['plate']}".toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  Future<void> _submitExisting() async {
    if (_selectedOrderId == null) return;
    setState(() => _saving = true);
    final orderId = _selectedOrderId!;
    for (int i = 0; i < widget.items.length; i++) {
      final item = widget.items[i];
      await DatabaseHelper().addOrderItem(
        orderId,
        item['name'] as String,
        (item['price'] as num).toDouble(),
        sync: false,
        workshop: 'Оклейка',
        category: 'Тонировка',
      );
    }
    await DatabaseHelper().syncOrderFromItems(orderId);
    await DatabaseHelper().addOrderEvent(
      orderId,
      "Тонировка из калькулятора: ${widget.amount} ₽ (${widget.items.length} зон)",
    );
    if (!mounted) return;
    Navigator.pop(context);
    await widget.onDone(orderId);
  }

  Future<void> _submitNew() async {
    if (_selectedClientId == null || _selectedCarId == null) return;
    setState(() => _saving = true);
    final orderId = await DatabaseHelper().addOrderWithItems(
      _selectedClientId!,
      _selectedCarId!,
      widget.items,
    );
    await DatabaseHelper().addOrderEvent(
      orderId,
      "Заказ создан из калькулятора тонировки: ${widget.amount} ₽",
    );
    if (!mounted) return;
    Navigator.pop(context);
    await widget.onDone(orderId);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text("В заказ", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 520,
        height: 440,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : Column(
                children: [
                  Text(
                    "${widget.items.length} работ · ${widget.amount} ₽",
                    style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TabBar(
                    controller: _tabs,
                    labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                    tabs: const [
                      Tab(text: "Существующий"),
                      Tab(text: "Новый"),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _buildExistingTab(),
                        _buildNewTab(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text("Отмена"),
        ),
        ElevatedButton(
          onPressed: _saving
              ? null
              : () {
                  if (_tabs.index == 0) {
                    if (_selectedOrderId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Выберите заказ", style: GoogleFonts.manrope()),
                          backgroundColor: AppColors.danger.withOpacity(0.9),
                        ),
                      );
                      return;
                    }
                    _submitExisting();
                  } else {
                    if (_selectedClientId == null || _selectedCarId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Выберите клиента и авто", style: GoogleFonts.manrope()),
                          backgroundColor: AppColors.danger.withOpacity(0.9),
                        ),
                      );
                      return;
                    }
                    _submitNew();
                  }
                },
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text),
                )
              : const Text("Добавить"),
        ),
      ],
    );
  }

  Widget _buildExistingTab() {
    final list = _filteredOrders;
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: "Поиск заказа",
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 20, color: AppColors.textMuted),
          ),
          onChanged: (v) => setState(() => _orderQuery = v),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    "Нет активных заказов",
                    style: GoogleFonts.manrope(color: AppColors.textDim),
                  ),
                )
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final o = list[index];
                    final id = o['id'] as int;
                    final selected = _selectedOrderId == id;
                    return ListTile(
                      selected: selected,
                      selectedTileColor: AppColors.primarySoft.withOpacity(0.35),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      title: Text(
                        "#$id · ${o['client_name']}",
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w600, color: AppColors.text),
                      ),
                      subtitle: Text(
                        "${o['make_model']} · ${o['plate']} · ${o['status']}",
                        style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12),
                      ),
                      onTap: () => setState(() => _selectedOrderId = id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildNewTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          value: _selectedClientId,
          decoration: const InputDecoration(labelText: "Клиент", isDense: true),
          dropdownColor: AppColors.surface2,
          items: _clients
              .map(
                (c) => DropdownMenuItem(
                  value: c['id'] as int,
                  child: Text(
                    "${c['name']} · ${c['phone']}",
                    style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: _onClientChanged,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: _selectedCarId,
          decoration: const InputDecoration(labelText: "Авто", isDense: true),
          dropdownColor: AppColors.surface2,
          items: _cars
              .map(
                (c) => DropdownMenuItem(
                  value: c['id'] as int,
                  child: Text(
                    "${c['make_model']} · ${c['plate']}",
                    style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _selectedCarId = v),
        ),
        if (_selectedClientId != null && _cars.isEmpty) ...[
          const SizedBox(height: 16),
          Text(
            "У клиента нет авто — добавьте в разделе Клиенты",
            style: GoogleFonts.manrope(color: AppColors.danger, fontSize: 13),
          ),
        ],
      ],
    );
  }
}
