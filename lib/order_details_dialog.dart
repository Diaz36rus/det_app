import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'database.dart';
import 'issue_guard.dart';
import 'master_picker.dart';
import 'quick_datetime_picker.dart';
import 'service_category_browser.dart';
import 'tour_keys.dart';
import 'work_order_pdf.dart';
import 'works_progress_bar.dart';

class OrderDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> order;
  /// Если задан — упрощённый режим карточки для цеха.
  final String? workshop;

  const OrderDetailsDialog({super.key, required this.order, this.workshop});

  /// Единая точка открытия: анимация внутри окна (заметно на Windows).
  static Future<bool?> open(
    BuildContext context,
    Map<String, dynamic> order, {
    String? workshop,
  }) {
    return showGeneralDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withOpacity(0.55),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return OrderDetailsDialog(order: order, workshop: workshop);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    );
  }

  @override
  State<OrderDetailsDialog> createState() => _OrderDetailsDialogState();
}

class _OrderDetailsDialogState extends State<OrderDetailsDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _enterCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  late final Animation<Offset> _slideAnim;
  bool _closing = false;

  // 1. Контроллер для текста комментария
  final TextEditingController _commentController = TextEditingController();
  final ExpansionTileController _priceListController = ExpansionTileController();
  bool _timelineSubmitBusy = false;

  // 2. Функция мгновенного добавления комментария
  Future<void> _addCommentToTimeline() async {
    if (_timelineSubmitBusy) return;
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    _timelineSubmitBusy = true;
    try {
      await DatabaseHelper().addOrderEvent(widget.order['id'], text);
      _commentController.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
      if (mounted) setState(() {});
    } finally {
      _timelineSubmitBusy = false;
    }
  }

  /// Enter в полях заметок: в ленту + очистка поля.
  Future<void> _submitNoteToTimeline({
    required String text,
    required String eventPrefix,
    required TextEditingController controller,
    required Future<void> Function(String) persist,
  }) async {
    if (_timelineSubmitBusy) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _timelineSubmitBusy = true;
    try {
      await persist(trimmed);
      await DatabaseHelper().addOrderEvent(widget.order['id'], "$eventPrefix: $trimmed");
      controller.clear();
      await persist("");
      FocusManager.instance.primaryFocus?.unfocus();
      _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
      if (mounted) setState(() {});
    } finally {
      _timelineSubmitBusy = false;
    }
  }

  late String _status;
  late double _initialPrice; // Итого к оплате (после скидки)
  double _paidAmount = 0; // Сколько клиент уже внес
  double _discountPercent = 0;
  double _discountFixed = 0;
  String _promoCode = "";
  late TextEditingController _priceController;
  late TextEditingController _autoPayController; // долг по услугам (авто, только чтение)
  late TextEditingController _payAmountController; // ручная сумма «оплатить сейчас»
  late TextEditingController _discountPercentController;
  late TextEditingController _discountFixedController;
  late TextEditingController _promoController;
  late TextEditingController _clientNotesController; // Комментарий от клиента
  late TextEditingController _visibleNotesController; // Комментарий для клиента
  late TextEditingController _masterCommentController; // Комментарий для мастера
  String _selectedWorkshopForComment = STATUSES.first; // Выбранный цех для комментария
  String _paymentMethod = "Не указан";
  
  List<Map<String, dynamic>> _masters = [];
  List<Map<String, dynamic>> _events = [];
  int? _selectedMasterId;
  List<Map<String, dynamic>> _clientCars = []; // Список авто клиента
  int? _selectedCarId; // Выбранное авто
  List<Map<String, dynamic>> _services = []; // Весь прайс-лист
  List<Map<String, dynamic>> _selectedWorks = []; // Выбранные работы (корзина)
  String _currentCarCategory = "1"; // Класс выбранного авто
  bool _isLoading = true;
  bool _isTechWash = false;
  String? _orderStartTime;
  String? _orderEndTime;
  String? _techWashStart;
  String? _techWashEnd;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    final curved = CurvedAnimation(
      parent: _enterCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _fadeAnim = curved;
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(curved);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(curved);
    // forward() — только после загрузки, иначе анимация «сгорает» на спиннере

    _status = widget.order['status'];
    _isTechWash = widget.order['tech_wash_start'] != null;
    _techWashStart = widget.order['tech_wash_start'];
    _techWashEnd = widget.order['tech_wash_end'];
    _orderStartTime = widget.order['start_time'];
    _orderEndTime = widget.order['end_time'];
    _initialPrice = (widget.order['price'] as num?)?.toDouble() ?? 0;
    _paidAmount = (widget.order['paid_amount'] as num?)?.toDouble() ?? 0;
    _discountPercent = (widget.order['discount_percent'] as num?)?.toDouble() ?? 0;
    _discountFixed = (widget.order['discount_fixed'] as num?)?.toDouble() ?? 0;
    _promoCode = widget.order['promo_code']?.toString() ?? "";
    _priceController = TextEditingController(text: widget.order['price'].toString());
    _autoPayController = TextEditingController();
    _payAmountController = TextEditingController();
    _discountPercentController = TextEditingController(
      text: _discountPercent == 0 ? "" : _formatMoney(_discountPercent),
    );
    _discountFixedController = TextEditingController(
      text: _discountFixed == 0 ? "" : _formatMoney(_discountFixed),
    );
    _promoController = TextEditingController(text: _promoCode);
    _clientNotesController = TextEditingController(text: widget.order['client_notes'] ?? "");
    _visibleNotesController = TextEditingController(text: widget.order['client_visible_notes'] ?? "");
    _masterCommentController = TextEditingController(text: widget.order['master_notes'] ?? "");
    _loadData();
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _commentController.dispose();
    _priceController.dispose();
    _autoPayController.dispose();
    _payAmountController.dispose();
    _discountPercentController.dispose();
    _discountFixedController.dispose();
    _promoController.dispose();
    _clientNotesController.dispose();
    _visibleNotesController.dispose();
    _masterCommentController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    _masters = await DatabaseHelper().getAllMastersFull();
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    _selectedMasterId = widget.order['master_id'];
    // Подгружаем все авто этого клиента
    _clientCars = await DatabaseHelper().getClientCars(widget.order['client_id']);
    _selectedCarId = widget.order['car_id'];
    
    // Определяем класс выбранного авто
    if (_selectedCarId != null) {
      var car = _clientCars.firstWhere((c) => c['id'] == _selectedCarId, orElse: () => {});
      if (car.isNotEmpty) _currentCarCategory = car['category'] ?? "1";
    }
    
    // Загружаем услуги
    _services = await DatabaseHelper().getAllServices();
    
    // Загружаем работы из order_items
    final dbItems = await DatabaseHelper().getOrderItems(widget.order['id']);
    _selectedWorks = dbItems.map((item) => Map<String, dynamic>.from(item)).toList();
    // Автопривязка цеха для старых услуг без workshop
    for (var i = 0; i < _selectedWorks.length; i++) {
      final w = _selectedWorks[i];
      final current = (w['workshop'] as String?)?.trim() ?? "";
      if (current.isNotEmpty && WORKSHOPS.contains(current)) continue;
      final auto = workshopForService(name: w['name']?.toString());
      if (auto == null) continue;
      await DatabaseHelper().updateOrderItemSchedule(
        w['id'] as int,
        w['start_time'] as String?,
        w['end_time'] as String?,
        auto,
      );
      _selectedWorks[i] = {...w, 'workshop': auto};
    }
    if (_selectedWorks.isEmpty) {
      // Миграция: notes "Услуга1, Услуга2" → отдельные order_items
      String notes = widget.order['notes'] ?? "";
      double oldPrice = (widget.order['price'] as num?)?.toDouble() ?? 0;
      if (notes.isNotEmpty) {
        List<String> names = notes.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        if (names.length == 1) {
          final ws = workshopForService(name: names.first);
          int newId = await DatabaseHelper().addOrderItem(widget.order['id'], names.first, oldPrice, sync: false, workshop: ws);
          _selectedWorks.add({"id": newId, "name": names.first, "price": oldPrice, "master_ids": "", "workshop": ws});
        } else {
          for (var name in names) {
            final ws = workshopForService(name: name);
            int newId = await DatabaseHelper().addOrderItem(widget.order['id'], name, 0, sync: false, workshop: ws);
            _selectedWorks.add({"id": newId, "name": name, "price": 0.0, "master_ids": "", "workshop": ws});
          }
        }
        await DatabaseHelper().syncOrderFromItems(widget.order['id']);
        if (names.length > 1 && oldPrice > 0 && _worksTotal == 0) {
          // Старые заказы: услуги без цен — оставляем прежнюю сумму заказа
          await DatabaseHelper().updateOrderPrice(widget.order['id'], oldPrice);
          _initialPrice = oldPrice;
          _priceController.text = _initialPrice.toString();
          _syncAutoPayField();
        } else {
          await _recalcOrderTotal(writeDb: false);
        }
      } else {
        await _recalcOrderTotal(writeDb: true);
      }
    } else {
      await _recalcOrderTotal(writeDb: true);
    }
    _paymentMethod = widget.order['payment_method'] ?? "Не указан";
    if (!mounted) return;
    _enterCtrl.value = 0;
    setState(() => _isLoading = false);
    // Запускаем открытие на кадре с уже готовым контентом
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closing) _enterCtrl.forward();
    });
  }

  // --- ФУНКЦИИ РАБОТЫ С УСЛУГАМИ ---
  final _customWorkName = TextEditingController();
  final _customWorkPrice = TextEditingController();
    // Безопасное форматирование времени (защита от старого формата "09:00")
  /// Для ленты и логов: 31.07 14:30
  String _formatDT(String? dtStr, String defaultText) {
    if (dtStr == null || dtStr.isEmpty) return defaultText;
    try {
      String n = dtStr.replaceFirst('T', ' ').split('.').first.trim();
      return DateFormat('dd.MM  HH:mm').format(DateTime.parse(n.contains(' ') ? n.replaceFirst(' ', 'T') : n));
    } catch (e) {
      return dtStr;
    }
  }

  /// Кнопка даты/времени — фон в гамме AppColors, акцент только рамкой.
  Widget _timeBadge({
    required String? value,
    required String emptyLabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    final hasValue = value != null && value.isNotEmpty;
    final text = hasValue ? _formatDT(value, emptyLabel) : emptyLabel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: hasValue ? color.withOpacity(0.65) : AppColors.border),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              color: hasValue ? AppColors.text : AppColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  double get _worksTotal =>
      _selectedWorks.fold(0.0, (sum, item) => sum + ((item['price'] as num?)?.toDouble() ?? 0));

  double get _discountAmount {
    final afterPct = _worksTotal * (_discountPercent.clamp(0, 100) / 100);
    final total = afterPct + _discountFixed;
    return total > _worksTotal ? _worksTotal : total;
  }

  double get _debt => _initialPrice - _paidAmount;

  String _formatMoney(double v) {
    if (v <= 0) return "0";
    return v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);
  }

  void _syncAutoPayField() {
    _autoPayController.text = _formatMoney(_debt);
  }

  /// Итого = сумма услуг минус скидка; пишем в orders.price.
  Future<void> _recalcOrderTotal({bool writeDb = true}) async {
    _initialPrice = DatabaseHelper.priceAfterDiscount(
      _worksTotal,
      _discountPercent,
      _discountFixed,
    );
    _priceController.text = _initialPrice.toString();
    _syncAutoPayField();
    if (writeDb) {
      await DatabaseHelper().syncOrderFromItems(widget.order['id']);
    }
  }

  Future<void> _persistDiscount({String? eventText}) async {
    await DatabaseHelper().updateOrderDiscount(
      widget.order['id'] as int,
      discountPercent: _discountPercent,
      discountFixed: _discountFixed,
      promoCode: _promoCode,
    );
    await _recalcOrderTotal(writeDb: false);
    if (eventText != null) {
      await DatabaseHelper().addOrderEvent(widget.order['id'], eventText);
      _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    }
    if (mounted) setState(() {});
  }

  Future<void> _applyPromoFromField() async {
    final code = _promoController.text.trim();
    if (code.isEmpty) {
      _promoCode = "";
      await _persistDiscount(eventText: "Промокод снят");
      return;
    }
    final promo = await DatabaseHelper().getPromocode(code);
    if (promo == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Промокод не найден", style: GoogleFonts.manrope()),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _promoCode = promo['code']?.toString() ?? code.toUpperCase();
    _discountPercent = (promo['discount_percent'] as num?)?.toDouble() ?? 0;
    _discountFixed = (promo['discount_fixed'] as num?)?.toDouble() ?? 0;
    _discountPercentController.text = _discountPercent == 0 ? "" : _formatMoney(_discountPercent);
    _discountFixedController.text = _discountFixed == 0 ? "" : _formatMoney(_discountFixed);
    _promoController.text = _promoCode;
    await _persistDiscount(
      eventText: "Промокод $_promoCode: −${_formatMoney(_discountAmount)} ₽",
    );
  }

  Future<void> _showManagePromosDialog() async {
    final codeCtrl = TextEditingController();
    final pctCtrl = TextEditingController();
    final fixedCtrl = TextEditingController();
    var list = await DatabaseHelper().getPromocodes();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setInner) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              title: Text("Промокоды", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (list.isEmpty)
                      Text("Пока нет промокодов", style: GoogleFonts.manrope(color: AppColors.textDim))
                    else
                      ...list.map((p) {
                        final pct = (p['discount_percent'] as num?)?.toDouble() ?? 0;
                        final fix = (p['discount_fixed'] as num?)?.toDouble() ?? 0;
                        final parts = <String>[];
                        if (pct > 0) parts.add("${_formatMoney(pct)}%");
                        if (fix > 0) parts.add("${_formatMoney(fix)} ₽");
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(
                            p['code']?.toString() ?? "",
                            style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: AppColors.text),
                          ),
                          subtitle: Text(
                            parts.isEmpty ? "Без скидки" : parts.join(" + "),
                            style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                            onPressed: () async {
                              await DatabaseHelper().deletePromocode((p['id'] as num).toInt());
                              list = await DatabaseHelper().getPromocodes();
                              setInner(() {});
                            },
                          ),
                        );
                      }),
                    const Divider(height: 20),
                    TextField(
                      controller: codeCtrl,
                      decoration: const InputDecoration(labelText: "Код", isDense: true),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: pctCtrl,
                            decoration: const InputDecoration(labelText: "%", isDense: true),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: fixedCtrl,
                            decoration: const InputDecoration(labelText: "Фикс ₽", isDense: true),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Закрыть")),
                ElevatedButton(
                  onPressed: () async {
                    final code = codeCtrl.text.trim();
                    if (code.isEmpty) return;
                    final pct = double.tryParse(pctCtrl.text.replaceAll(',', '.')) ?? 0;
                    final fix = double.tryParse(fixedCtrl.text.replaceAll(',', '.')) ?? 0;
                    await DatabaseHelper().upsertPromocode(code, pct, fix);
                    list = await DatabaseHelper().getPromocodes();
                    codeCtrl.clear();
                    pctCtrl.clear();
                    fixedCtrl.clear();
                    setInner(() {});
                  },
                  child: const Text("Сохранить"),
                ),
              ],
            );
          },
        );
      },
    );
  }
  Future<String?> _pickDateTime({String? current}) async {
    DateTime? initial;
    if (current != null && current.isNotEmpty) {
      try {
        final n = current.replaceFirst('T', ' ').split('.').first.trim();
        initial = DateTime.parse(n.contains(' ') ? n.replaceFirst(' ', 'T') : n);
      } catch (_) {}
    }
    return QuickDateTimePicker.pickDateTime(context, initial: initial ?? DateTime.now());
  }

  Future<void> _reloadWorksFromDb() async {
    final dbItems = await DatabaseHelper().getOrderItems(widget.order['id']);
    _selectedWorks = dbItems.map((item) => Map<String, dynamic>.from(item)).toList();
    await _recalcOrderTotal(writeDb: false);
    if (mounted) setState(() {});
  }

  void _addWork(String name, double price, [String category = ""]) async {
    final workshop = workshopForService(category: category, name: name);
    await DatabaseHelper().addOrderItem(
      widget.order['id'],
      name,
      price,
      category: category,
      workshop: workshop,
    );
    final wsNote = workshop != null ? " → цех $workshop" : "";
    final priceNote = isWrapPackageLine(category: category, name: name)
        ? "в пакет оклейки"
        : "$price руб";
    await DatabaseHelper().addOrderEvent(
      widget.order['id'],
      "Добавлена работа: $name ($priceNote)$wsNote",
    );
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    await _reloadWorksFromDb();
  }

  bool get _isWorkshopMode => widget.workshop != null && widget.workshop!.isNotEmpty;

  String _resolvedWorkWorkshop(Map<String, dynamic> w) {
    final raw = (w['workshop'] as String?)?.trim() ?? "";
    if (raw.isNotEmpty && WORKSHOPS.contains(raw)) return raw;
    return workshopForService(name: w['name']?.toString()) ?? "";
  }

  bool _canToggleWorkInWorkshop(Map<String, dynamic> w) {
    if (!_isWorkshopMode) return true;
    return _resolvedWorkWorkshop(w) == widget.workshop;
  }

  Future<void> _toggleWorkDone(int index, bool done) async {
    final w = _selectedWorks[index];
    if (_isWorkshopMode && !_canToggleWorkInWorkshop(w)) return;
    await DatabaseHelper().updateOrderItemDone(w['id'] as int, done);
    final updated = Map<String, dynamic>.from(w);
    updated['is_done'] = done ? 1 : 0;
    setState(() => _selectedWorks[index] = updated);
    final ws = widget.workshop;
    final log = done
        ? (ws != null ? "Цех «$ws»: работа выполнена — ${w['name']}" : "Работа выполнена: ${w['name']}")
        : (ws != null ? "Цех «$ws»: снята отметка — ${w['name']}" : "Снята отметка выполнения: ${w['name']}");
    await DatabaseHelper().addOrderEvent(widget.order['id'], log);
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    setState(() {});
  }

  Future<void> _addWorkshopMasterComment() async {
    if (_timelineSubmitBusy) return;
    final text = _commentController.text.trim();
    if (text.isEmpty || widget.workshop == null) return;
    _timelineSubmitBusy = true;
    try {
      await DatabaseHelper().addOrderEvent(
        widget.order['id'],
        "Цех «${widget.workshop}»: $text",
      );
      _commentController.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
      if (mounted) setState(() {});
    } finally {
      _timelineSubmitBusy = false;
    }
  }

  static const Map<String, Color> _workshopColors = {
    "Предварительная запись": AppColors.textDim,
    "Принят в работу": AppColors.primary,
    "Мойка": Color(0xFF22D3EE),
    "Химчистка": Color(0xFFA78BFA),
    "Полировка": Color(0xFFF59E0B),
    "Оклейка": AppColors.danger,
    "Интерьер": Color(0xFF14B8A6),
    "Оборудование": Color(0xFFD97706),
    "Подготовка к выдаче": Color(0xFF6366F1),
    "Выдан": AppColors.success,
  };

  static bool _isClientDialogEvent(String text) {
    final t = text.trim();
    return t.startsWith('От клиента:') ||
        t.startsWith('Для клиента:') ||
        t.startsWith('Комментарий от клиента:') ||
        t.startsWith('Комментарий для клиента:');
  }

  static bool _isFromClientEvent(String text) {
    final t = text.trim();
    return t.startsWith('От клиента:') || t.startsWith('Комментарий от клиента:');
  }

  static String _clientDialogBody(String text) {
    final t = text.trim();
    for (final p in [
      'От клиента: ',
      'Для клиента: ',
      'Комментарий от клиента: ',
      'Комментарий для клиента: ',
      'От клиента:',
      'Для клиента:',
      'Комментарий от клиента:',
      'Комментарий для клиента:',
    ]) {
      if (t.startsWith(p)) return t.substring(p.length).trim();
    }
    return t;
  }

  String _formatEventTime(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString().trim();
    if (s.isEmpty) return '';
    try {
      final n = s.replaceFirst('T', ' ').split('.').first.trim();
      final dt = DateTime.parse(n.contains(' ') ? n.replaceFirst(' ', 'T') : n);
      return DateFormat('dd.MM.yyyy HH:mm').format(dt);
    } catch (_) {
      if (s.length >= 16 && s[4] == '-' && s[7] == '-') {
        // 2026-08-02 12:30 или 2026-08-02T12:30
        final date = s.substring(0, 10).split('-');
        final time = s.substring(11, 16);
        if (date.length == 3) return '${date[2]}.${date[1]}.${date[0]} $time';
      }
      return s;
    }
  }

  /// Разбор текста события для чистого UI + цвет цеха.
  ({String? workshop, String body, Color accent}) _parseTimelineEvent(String raw) {
    final t = raw.trim();

    final fromShop = RegExp(r'^Комментарий от цеха «([^»]+)»:\s*(.*)$').firstMatch(t);
    if (fromShop != null) {
      final w = fromShop.group(1)!;
      return (
        workshop: w,
        body: fromShop.group(2)!.trim(),
        accent: _workshopColors[w] ?? AppColors.primary,
      );
    }

    final shopLine = RegExp(r'^Цех «([^»]+)»:\s*(.*)$').firstMatch(t);
    if (shopLine != null) {
      final w = shopLine.group(1)!;
      return (
        workshop: w,
        body: shopLine.group(2)!.trim(),
        accent: _workshopColors[w] ?? AppColors.primary,
      );
    }

    final plain = RegExp(r'^Комментарий:\s*(.*)$').firstMatch(t);
    if (plain != null) {
      return (workshop: null, body: plain.group(1)!.trim(), accent: AppColors.textMuted);
    }

    // Статус изменен на: Мойка
    final status = RegExp(r'^Статус изменен на:\s*(.+)$').firstMatch(t);
    if (status != null) {
      final name = status.group(1)!.trim();
      return (
        workshop: name,
        body: 'Статус → $name',
        accent: _workshopColors[name] ?? AppColors.primary,
      );
    }

    for (final w in [...WORKSHOPS, ...STATUSES]) {
      if (t.contains('«$w»')) {
        return (
          workshop: w,
          body: t
              .replaceFirst(RegExp(r'^Комментарий от цеха\s*'), '')
              .replaceFirst(RegExp(r'^Комментарий\s*'), '')
              .trim(),
          accent: _workshopColors[w] ?? AppColors.textMuted,
        );
      }
    }

    return (workshop: null, body: t, accent: AppColors.textMuted);
  }

  Widget _buildPlainTimelineEvent(Map<String, dynamic> ev) {
    final raw = ev['event_text']?.toString() ?? '';
    final parsed = _parseTimelineEvent(raw);
    final time = _formatEventTime(ev['created_at']);
    final accent = parsed.accent;
    final line = parsed.workshop != null
        ? "${parsed.workshop}: ${parsed.body}"
        : parsed.body;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line,
            style: GoogleFonts.manrope(
              color: accent,
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (time.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              time,
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClientDialogGroup(List<Map<String, dynamic>> groupDesc) {
    // В ленте события id DESC — внутри диалога показываем хронологически.
    final chrono = groupDesc.reversed.toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Диалог с клиентом",
            style: GoogleFonts.manrope(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          for (final ev in chrono) ...[
            Builder(
              builder: (_) {
                final raw = ev['event_text']?.toString() ?? '';
                final fromClient = _isFromClientEvent(raw);
                final body = _clientDialogBody(raw);
                final time = _formatEventTime(ev['created_at']);
                return Align(
                  alignment: fromClient ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 280),
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: fromClient
                          ? AppColors.surface
                          : AppColors.primary.withOpacity(0.18),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(10),
                        topRight: const Radius.circular(10),
                        bottomLeft: Radius.circular(fromClient ? 2 : 10),
                        bottomRight: Radius.circular(fromClient ? 10 : 2),
                      ),
                      border: Border.all(
                        color: fromClient ? AppColors.border : AppColors.primary.withOpacity(0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          fromClient ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                      children: [
                        Text(
                          fromClient ? "От клиента" : "Для клиента",
                          style: GoogleFonts.manrope(
                            color: fromClient ? AppColors.textDim : AppColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: GoogleFonts.manrope(
                            color: AppColors.text,
                            fontSize: 13,
                            height: 1.25,
                          ),
                        ),
                        if (time.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            time,
                            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 10),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _clientDialogEvents() {
    return _events
        .where((e) => _isClientDialogEvent(e['event_text']?.toString() ?? ''))
        .toList();
  }

  List<Widget> _buildOtherTimelineWidgets() {
    return _events
        .where((e) => !_isClientDialogEvent(e['event_text']?.toString() ?? ''))
        .map(_buildPlainTimelineEvent)
        .toList();
  }

  /// Закреплённый диалог с клиентом + прокручиваемая лента остальных событий.
  Widget _buildPinnedTimelineBody({required Widget composer}) {
    final dialog = _clientDialogEvents();
    final others = _buildOtherTimelineWidgets();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (dialog.isNotEmpty) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: _buildClientDialogGroup(dialog),
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 8),
        ],
        Text(
          "ЛЕНТА СОБЫТИЙ",
          style: GoogleFonts.manrope(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: others.isEmpty && dialog.isEmpty
              ? Center(
                  child: Text(
                    "Пока пусто",
                    style: GoogleFonts.manrope(color: AppColors.textDim),
                  ),
                )
              : others.isEmpty
                  ? Center(
                      child: Text(
                        "Нет других событий",
                        style: GoogleFonts.manrope(color: AppColors.textDim),
                      ),
                    )
                  : ListView(children: others),
        ),
        composer,
      ],
    );
  }

  void _removeWork(Map<String, dynamic> work) async {
    await DatabaseHelper().deleteOrderItem(work['id'] as int);
    await DatabaseHelper().addOrderEvent(widget.order['id'], "Удалена работа: ${work['name']}");
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    await _reloadWorksFromDb(); // deleteOrderItem уже sync; мог удалиться и пакет
  }

  Future<void> _editWrapPackagePrice(Map<String, dynamic> header) async {
    final current = (header['price'] as num?)?.toDouble() ?? 0;
    final ctrl = TextEditingController(text: current == 0 ? '' : _formatMoney(current));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text("Сумма пакета оклейки", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: "Сумма, ₽", isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Отмена")),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.replaceAll(',', '.').trim()) ?? 0;
              Navigator.pop(ctx, v);
            },
            child: const Text("Сохранить"),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    await DatabaseHelper().updateOrderItemPrice((header['id'] as num).toInt(), result);
    await DatabaseHelper().addOrderEvent(
      widget.order['id'],
      "Сумма пакета оклейки: ${_formatMoney(result)} ₽",
    );
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    await _reloadWorksFromDb();
  }

  void _addCustomWork() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text("Своя работа", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _customWorkName, decoration: const InputDecoration(labelText: "Название", isDense: true)),
            const SizedBox(height: 8),
            TextField(
              controller: _customWorkPrice,
              decoration: const InputDecoration(labelText: "Цена", isDense: true),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Отмена")),
          ElevatedButton(
            onPressed: () {
              if (_customWorkName.text.isNotEmpty) {
                _addWork(_customWorkName.text, double.tryParse(_customWorkPrice.text) ?? 0);
                _customWorkName.clear();
                _customWorkPrice.clear();
                Navigator.pop(context);
              }
            },
            child: const Text("Добавить"),
          ),
        ],
      ),
    );
  }

  void _addPayment() async {
    // Справа — ручная сумма; если пусто — берём авто-долг слева
    final manual = _payAmountController.text.trim().replaceAll(',', '.');
    double amount;
    if (manual.isNotEmpty) {
      amount = double.tryParse(manual) ?? 0;
    } else {
      amount = double.tryParse(_autoPayController.text.replaceAll(',', '.')) ?? _debt;
    }
    if (amount <= 0) return;

    await DatabaseHelper().addPayment(widget.order['id'], amount, _paymentMethod);
    await DatabaseHelper().updateOrderPaymentMethod(widget.order['id'], _paymentMethod);
    await DatabaseHelper().addOrderEvent(widget.order['id'], "Внесена оплата: $amount руб ($_paymentMethod)");

    _paidAmount += amount;
    _payAmountController.clear();
    _syncAutoPayField();
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    setState(() {});
  }

  Future<void> _closeDialog() async {
    if (_closing) return;
    _closing = true;
    await _enterCtrl.reverse();
    if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
  }

  Future<void> _printWorkOrder() async {
    String? masterName = widget.order['master_name']?.toString();
    if (_selectedMasterId != null) {
      final found = _masters.where((m) => m['id'] == _selectedMasterId).toList();
      if (found.isNotEmpty) masterName = found.first['name']?.toString();
    }
    final orderForPdf = {
      ...widget.order,
      'status': _status,
      'price': _initialPrice,
      'paid_amount': _paidAmount,
      'master_name': masterName ?? '',
      'start_time': _orderStartTime ?? widget.order['start_time'],
      'end_time': _orderEndTime ?? widget.order['end_time'],
    };
    if (!mounted) return;
    try {
      await WorkOrderPdf.showPreview(
        context,
        order: orderForPdf,
        items: _selectedWorks,
        masters: _masters,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Не удалось открыть превью: $e", style: GoogleFonts.manrope()),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Подсказка, если забыли выбрать цех (показываем поверх окна заказа).
  void _showNeedWorkshopHint() {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text("Сначала цех", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: Text(
          "У этой услуги не определился цех. Добавь её из прайса по категории — цех подставится сам.",
          style: GoogleFonts.manrope(color: AppColors.textMuted),
        ),
        actions: [
          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("Понятно")),
        ],
      ),
    );
  }

  /// Сохраняет цех и время одной услуги в базу + пишет в ленту.
  Future<void> _saveWorkSchedule(int index, {String? start, String? end, String? workshop, String? logText}) async {
    final w = _selectedWorks[index];
    final updated = Map<String, dynamic>.from(w);
    if (start != null) updated['start_time'] = start;
    if (end != null) updated['end_time'] = end;
    if (workshop != null) updated['workshop'] = workshop;

    await DatabaseHelper().updateOrderItemSchedule(
      w['id'] as int,
      updated['start_time'] as String?,
      updated['end_time'] as String?,
      updated['workshop'] as String?,
    );
    setState(() => _selectedWorks[index] = updated);
    if (logText != null && logText.isNotEmpty) {
      await DatabaseHelper().addOrderEvent(widget.order['id'], logText);
      _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
      setState(() {});
    }
  }

  Widget _section({required String title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Text(
              title,
              style: GoogleFonts.manrope(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: child,
          ),
        ],
      ),
    );
  }

  Future<void> _pickMastersForWork(int index, Map<String, dynamic> w) async {
    var workshop = (w['workshop'] as String?)?.trim() ?? "";
    if (workshop.isEmpty || !WORKSHOPS.contains(workshop)) {
      final auto = workshopForService(name: w['name']?.toString());
      if (auto != null) {
        await _saveWorkSchedule(index, workshop: auto);
        workshop = auto;
        w = _selectedWorks[index];
      }
    }
    if (workshop.isEmpty || !WORKSHOPS.contains(workshop)) {
      _showNeedWorkshopHint();
      return;
    }

    List<int> oldIds = [];
    if (w['master_ids'] != null && (w['master_ids'] as String).isNotEmpty) {
      oldIds = (w['master_ids'] as String)
          .split(',')
          .where((e) => e.trim().isNotEmpty)
          .map((e) => int.parse(e))
          .toList();
    }
    List<int> currentIds = List.from(oldIds);

    // Только мастера роли цеха (+ уже выбранные, чтобы можно было снять)
    final filtered = _masters.where((m) {
      final mId = (m['id'] as num).toInt();
      if (currentIds.contains(mId)) return true;
      return masterRoleFitsWorkshop(m['role']?.toString(), workshop);
    }).toList();

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              title: Text(
                "Мастера · $workshop",
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
              ),
              content: SizedBox(
                width: 280,
                child: filtered.isEmpty
                    ? Text(
                        "Нет мастеров с ролью для цеха «$workshop».\nДобавь их в разделе Сотрудники.",
                        style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.35),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: filtered.map((m) {
                          final mId = (m['id'] as num).toInt();
                          final isSelected = currentIds.contains(mId);
                          final role = m['role']?.toString() ?? "";
                          final fits = masterRoleFitsWorkshop(role, workshop);
                          return CheckboxListTile(
                            title: Text(m['name'], style: GoogleFonts.manrope(color: AppColors.text)),
                            subtitle: Text(
                              fits ? role : "$role (не по цеху)",
                              style: GoogleFonts.manrope(
                                color: fits ? AppColors.textDim : AppColors.danger,
                                fontSize: 12,
                              ),
                            ),
                            value: isSelected,
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true) {
                                  currentIds.add(mId);
                                } else {
                                  currentIds.remove(mId);
                                }
                              });
                              DatabaseHelper().updateOrderItemMasters(w['id'] as int, currentIds).then((_) {
                                setState(() {
                                  final updatedWork = Map<String, dynamic>.from(w);
                                  updatedWork['master_ids'] = currentIds.join(',');
                                  _selectedWorks[index] = updatedWork;
                                });
                              });
                            },
                          );
                        }).toList(),
                      ),
              ),
            );
          },
        );
      },
    );
    String getNames(List<int> ids) {
      return ids.map((id) {
        var found = _masters.where((master) => master['id'] == id).toList();
        return found.isNotEmpty ? found.first['name'] : '';
      }).where((n) => n.isNotEmpty).join(', ');
    }

    String oldNames = getNames(oldIds);
    String newNames = getNames(currentIds);
    if (oldNames != newNames) {
      String logText;
      if (newNames.isEmpty) {
        logText = "Сняты все мастера с работы: ${w['name']}";
      } else if (oldNames.isEmpty) {
        logText = "На работу '${w['name']}' назначены: $newNames";
      } else {
        logText = "Мастера на '${w['name']}' изменены на: $newNames";
      }
      await DatabaseHelper().addOrderEvent(widget.order['id'], logText);
      _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
      setState(() {});
    }
  }

  String _masterNamesFor(Map<String, dynamic> w) {
    if (w['master_ids'] == null || (w['master_ids'] as String).isEmpty) return "";
    List<int> ids = (w['master_ids'] as String)
        .split(',')
        .where((e) => e.trim().isNotEmpty)
        .map((e) => int.parse(e))
        .toList();
    return ids.map((id) {
      var found = _masters.where((m) => m['id'] == id).toList();
      return found.isNotEmpty ? found.first['name'] : '';
    }).where((n) => n.isNotEmpty).join(', ');
  }

  Widget _buildWorkCard(Map<String, dynamic> w, {bool hidePrice = false}) {
    final index = _selectedWorks.indexWhere((e) => e['id'] == w['id']);
    if (index < 0) return const SizedBox.shrink();
    final String? currentWorkshop =
        (w['workshop'] != null && (w['workshop'] as String).isNotEmpty && WORKSHOPS.contains(w['workshop']))
            ? w['workshop'] as String
            : null;
    final masters = _masterNamesFor(w);
    final hasMasters = masters.isNotEmpty;
    final isDone = (w['is_done'] as num?)?.toInt() == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: isDone ? AppColors.surface2 : AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: isDone ? AppColors.success.withOpacity(0.45) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Checkbox(
                value: isDone,
                activeColor: AppColors.success,
                side: const BorderSide(color: AppColors.border),
                onChanged: (val) => _toggleWorkDone(index, val == true),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${w['name']}",
                      style: GoogleFonts.manrope(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        decorationColor: AppColors.textDim,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [
                        if (currentWorkshop != null) currentWorkshop,
                        isDone ? "Выполнено" : "Не выполнено",
                      ].join(" · "),
                      style: GoogleFonts.manrope(
                        color: isDone ? AppColors.success : AppColors.textDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hasMasters)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          masters,
                          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  hasMasters ? Icons.groups : Icons.person_add_alt_1,
                  color: hasMasters ? AppColors.primary : AppColors.textDim,
                  size: 20,
                ),
                tooltip: "Назначить мастеров",
                onPressed: () => _pickMastersForWork(index, w),
              ),
              if (!hidePrice)
                Text(
                  "${w['price']} ₽",
                  style: GoogleFonts.manrope(color: AppColors.success, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              if (!_isWorkshopMode)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                  onPressed: () => _removeWork(w),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _timeBadge(
                  value: w['start_time']?.toString(),
                  emptyLabel: "Начало",
                  color: AppColors.success,
                  onTap: () async {
                    String? ws = (_selectedWorks[index]['workshop'] as String?) ?? currentWorkshop;
                    if (ws == null || ws.isEmpty) {
                      ws = workshopForService(name: w['name']?.toString());
                      if (ws != null) {
                        await _saveWorkSchedule(index, workshop: ws);
                      }
                    }
                    ws = (_selectedWorks[index]['workshop'] as String?) ?? ws;
                    if (ws == null || ws.isEmpty) {
                      _showNeedWorkshopHint();
                      return;
                    }
                    String? dt = await _pickDateTime(current: w['start_time']?.toString());
                    if (dt == null) return;
                    await _saveWorkSchedule(
                      index,
                      start: dt,
                      workshop: ws,
                      logText: "Услуга '${w['name']}': начало ${_formatDT(dt, dt)}",
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _timeBadge(
                  value: w['end_time']?.toString(),
                  emptyLabel: "Конец",
                  color: AppColors.danger,
                  onTap: () async {
                    String? ws = (_selectedWorks[index]['workshop'] as String?) ?? currentWorkshop;
                    if (ws == null || ws.isEmpty) {
                      ws = workshopForService(name: w['name']?.toString());
                      if (ws != null) {
                        await _saveWorkSchedule(index, workshop: ws);
                      }
                    }
                    ws = (_selectedWorks[index]['workshop'] as String?) ?? ws;
                    if (ws == null || ws.isEmpty) {
                      _showNeedWorkshopHint();
                      return;
                    }
                    String? dt = await _pickDateTime(current: w['end_time']?.toString() ?? w['start_time']?.toString());
                    if (dt == null) return;
                    await _saveWorkSchedule(
                      index,
                      end: dt,
                      workshop: ws,
                      logText: "Услуга '${w['name']}': конец ${_formatDT(dt, dt)}",
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Заказ #${widget.order['id']}  ·  ${widget.order['client_name']}",
                  style: GoogleFonts.manrope(
                    color: AppColors.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: "Печать заказ-наряда",
                onPressed: _printWorkOrder,
                icon: const Icon(Icons.print_outlined, color: AppColors.primary),
              ),
              IconButton(
                onPressed: _closeDialog,
                icon: const Icon(Icons.close, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(labelText: "Статус", isDense: true),
                  dropdownColor: AppColors.surface,
                  items: STATUSES.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (val) async {
                    if (val == null || val == _status) return;
                    final previous = _status;
                    setState(() => _status = val);
                    final ok = await tryUpdateOrderStatus(
                      context,
                      widget.order['id'] as int,
                      val,
                    );
                    if (!mounted) return;
                    if (!ok) {
                      setState(() => _status = previous);
                      return;
                    }
                    await DatabaseHelper().addOrderEvent(widget.order['id'], "Статус изменен на: $val");
                    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _selectedMasterId,
                  decoration: const InputDecoration(labelText: "Администратор", isDense: true),
                  dropdownColor: AppColors.surface,
                  items: [
                    const DropdownMenuItem<int>(value: null, child: Text("Не назначен")),
                    ..._masters.map((m) => DropdownMenuItem<int>(value: m['id'], child: Text(m['name']))),
                  ],
                  onChanged: (val) async {
                    if (val == _selectedMasterId) return;
                    setState(() => _selectedMasterId = val);
                    await DatabaseHelper().updateOrderMaster(widget.order['id'], val);
                    String masterName = "Не назначен";
                    if (val != null) {
                      var foundMaster = _masters.where((m) => m['id'] == val).toList();
                      if (foundMaster.isNotEmpty) masterName = foundMaster.first['name'];
                    }
                    await DatabaseHelper().addOrderEvent(widget.order['id'], "Назначен администратор: $masterName");
                    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _selectedCarId,
                  decoration: const InputDecoration(labelText: "Автомобиль", isDense: true),
                  dropdownColor: AppColors.surface,
                  items: _clientCars.map((car) {
                    final vin = (car['vin'] ?? '').toString();
                    return DropdownMenuItem<int>(
                      value: car['id'] as int,
                      child: Text(
                        vin.isEmpty
                            ? "${car['make_model']} | ${car['plate']}"
                            : "${car['make_model']} | ${car['plate']} | VIN $vin",
                      ),
                    );
                  }).toList(),
                  onChanged: (val) async {
                    if (val != null) {
                      setState(() => _selectedCarId = val);
                      await DatabaseHelper().reassignOrderCar(widget.order['id'], val);
                      var selectedCar = _clientCars.firstWhere((c) => c['id'] == val);
                      await DatabaseHelper().addOrderEvent(
                        widget.order['id'],
                        "Изменено авто на: ${selectedCar['make_model']} | ${selectedCar['plate']}",
                      );
                      _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
                      setState(() {});
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorksColumn() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Работы",
            style: GoogleFonts.manrope(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          WorksProgressBar.fromItems(_selectedWorks),
          const SizedBox(height: 12),
          if (!_isWorkshopMode) ...[
            ExpansionTile(
              controller: _priceListController,
              title: Text(
                "Добавить из прайса",
                style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              iconColor: AppColors.primary,
              collapsedIconColor: AppColors.textMuted,
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              children: [
                Container(
                  height: 280,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ServiceCategoryBrowser(
                    services: _services,
                    carCategory: _currentCarCategory,
                    onAdd: _addWork,
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addCustomWork,
                icon: const Icon(Icons.add, size: 18),
                label: const Text("Своя работа"),
              ),
            ),
            const SizedBox(height: 4),
          ],
          Expanded(child: _buildWorksListView()),
        ],
      ),
    );
  }

  Map<String, dynamic>? _wrapPackageHeader() {
    for (final w in _selectedWorks) {
      if (isWrapPackageHeader(w['name']?.toString()) && w['parent_id'] == null) {
        return w;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _wrapPackageChildren(int headerId) {
    return _selectedWorks
        .where((w) => (w['parent_id'] as num?)?.toInt() == headerId)
        .toList();
  }

  List<Map<String, dynamic>> _standaloneWorks() {
    return _selectedWorks.where((w) {
      if (isWrapPackageHeader(w['name']?.toString()) && w['parent_id'] == null) {
        return false;
      }
      if (w['parent_id'] != null) return false;
      return true;
    }).toList();
  }

  Future<void> _toggleWrapPackageDone(
    Map<String, dynamic> header,
    List<Map<String, dynamic>> children,
    bool done,
  ) async {
    final headerId = (header['id'] as num).toInt();
    await DatabaseHelper().updateWrapPackageDone(headerId, done);
    final log = done
        ? "Пакет оклейки выполнен (${children.length} поз.)"
        : "Снята отметка выполнения пакета оклейки";
    await DatabaseHelper().addOrderEvent(widget.order['id'], log);
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    await _reloadWorksFromDb();
  }

  Future<void> _saveWrapPackageSchedule({
    required Map<String, dynamic> header,
    String? start,
    String? end,
    String? logText,
  }) async {
    final headerId = (header['id'] as num).toInt();
    final nextStart = start ?? header['start_time']?.toString();
    final nextEnd = end ?? header['end_time']?.toString();
    await DatabaseHelper().updateWrapPackageSchedule(headerId, nextStart, nextEnd);
    if (logText != null && logText.isNotEmpty) {
      await DatabaseHelper().addOrderEvent(widget.order['id'], logText);
      _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    }
    await _reloadWorksFromDb();
  }

  Future<void> _pickMastersForWrapPackage(Map<String, dynamic> header) async {
    const workshop = 'Оклейка';
    List<int> oldIds = [];
    if (header['master_ids'] != null && (header['master_ids'] as String).isNotEmpty) {
      oldIds = (header['master_ids'] as String)
          .split(',')
          .where((e) => e.trim().isNotEmpty)
          .map((e) => int.parse(e))
          .toList();
    }
    List<int> currentIds = List.from(oldIds);

    final filtered = _masters.where((m) {
      final mId = (m['id'] as num).toInt();
      if (currentIds.contains(mId)) return true;
      return masterRoleFitsWorkshop(m['role']?.toString(), workshop);
    }).toList();

    final headerId = (header['id'] as num).toInt();

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              title: Text(
                "Мастера · $workshop (пакет)",
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
              ),
              content: SizedBox(
                width: 280,
                child: filtered.isEmpty
                    ? Text(
                        "Нет мастеров с ролью для цеха «$workshop».\nДобавь их в разделе Сотрудники.",
                        style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.35),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: filtered.map((m) {
                          final mId = (m['id'] as num).toInt();
                          final isSelected = currentIds.contains(mId);
                          final role = m['role']?.toString() ?? "";
                          final fits = masterRoleFitsWorkshop(role, workshop);
                          return CheckboxListTile(
                            title: Text(m['name'], style: GoogleFonts.manrope(color: AppColors.text)),
                            subtitle: Text(
                              fits ? role : "$role (не по цеху)",
                              style: GoogleFonts.manrope(
                                color: fits ? AppColors.textDim : AppColors.danger,
                                fontSize: 12,
                              ),
                            ),
                            value: isSelected,
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true) {
                                  currentIds.add(mId);
                                } else {
                                  currentIds.remove(mId);
                                }
                              });
                              DatabaseHelper().updateWrapPackageMasters(headerId, currentIds).then((_) {
                                _reloadWorksFromDb();
                              });
                            },
                          );
                        }).toList(),
                      ),
              ),
            );
          },
        );
      },
    );

    String getNames(List<int> ids) {
      return ids.map((id) {
        var found = _masters.where((master) => master['id'] == id).toList();
        return found.isNotEmpty ? found.first['name'] : '';
      }).where((n) => n.isNotEmpty).join(', ');
    }

    final oldNames = getNames(oldIds);
    final newNames = getNames(currentIds);
    if (oldNames != newNames) {
      final logText = newNames.isEmpty
          ? "Сняты все мастера с пакета оклейки"
          : "На пакет оклейки назначены: $newNames";
      await DatabaseHelper().addOrderEvent(widget.order['id'], logText);
      _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
      if (mounted) setState(() {});
    }
  }

  Widget _buildWrapPackageCompositionRow(Map<String, dynamic> child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.only(left: 10, right: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "${child['name']}",
              style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: "Убрать из пакета",
            icon: const Icon(Icons.close, color: AppColors.danger, size: 18),
            onPressed: () => _removeWork(child),
          ),
        ],
      ),
    );
  }

  Widget _buildWrapPackageBlock(
    Map<String, dynamic> header,
    List<Map<String, dynamic>> children,
  ) {
    final price = (header['price'] as num?)?.toDouble() ?? 0;
    final doneCount = children.where((c) => (c['is_done'] as num?)?.toInt() == 1).length;
    final allDone = children.isNotEmpty && doneCount == children.length;
    final someDone = doneCount > 0 && !allDone;
    final masters = _masterNamesFor(header);
    final hasMasters = masters.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: allDone ? AppColors.surface2 : AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: allDone ? AppColors.success.withOpacity(0.45) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Checkbox(
                tristate: true,
                value: allDone ? true : (someDone ? null : false),
                activeColor: AppColors.success,
                side: const BorderSide(color: AppColors.border),
                // tristate сам циклит false→true→null; игнорируем val и просто
                // переключаем: не всё выполнено → отметить всё, иначе снять.
                onChanged: children.isEmpty
                    ? null
                    : (_) => _toggleWrapPackageDone(header, children, !allDone),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Оклейка · ${children.length} поз.",
                      style: GoogleFonts.manrope(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        decoration: allDone ? TextDecoration.lineThrough : null,
                        decorationColor: AppColors.textDim,
                      ),
                    ),
                    Text(
                      allDone
                          ? "Выполнено"
                          : (someDone ? "Частично · $doneCount из ${children.length}" : "Не выполнено"),
                      style: GoogleFonts.manrope(
                        color: allDone ? AppColors.success : AppColors.textDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hasMasters)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          masters,
                          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _editWrapPackagePrice(header),
                child: Text(
                  "${_formatMoney(price)} ₽",
                  style: GoogleFonts.manrope(
                    color: AppColors.success,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  hasMasters ? Icons.groups : Icons.person_add_alt_1,
                  color: hasMasters ? AppColors.primary : AppColors.textDim,
                  size: 20,
                ),
                tooltip: "Мастера пакета",
                onPressed: () => _pickMastersForWrapPackage(header),
              ),
              IconButton(
                tooltip: "Удалить пакет",
                icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                onPressed: () => _removeWork(header),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _timeBadge(
                  value: header['start_time']?.toString(),
                  emptyLabel: "Начало",
                  color: AppColors.success,
                  onTap: () async {
                    final dt = await _pickDateTime(current: header['start_time']?.toString());
                    if (dt == null) return;
                    await _saveWrapPackageSchedule(
                      header: header,
                      start: dt,
                      logText: "Пакет оклейки: начало ${_formatDT(dt, dt)}",
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _timeBadge(
                  value: header['end_time']?.toString(),
                  emptyLabel: "Конец",
                  color: AppColors.danger,
                  onTap: () async {
                    final dt = await _pickDateTime(
                      current: header['end_time']?.toString() ?? header['start_time']?.toString(),
                    );
                    if (dt == null) return;
                    await _saveWrapPackageSchedule(
                      header: header,
                      end: dt,
                      logText: "Пакет оклейки: конец ${_formatDT(dt, dt)}",
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: false,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 4),
              iconColor: AppColors.primary,
              collapsedIconColor: AppColors.textMuted,
              title: Text(
                "Состав · выполнено $doneCount из ${children.length}",
                style: GoogleFonts.manrope(
                  color: AppColors.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              children: [
                if (children.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      "Нет зон — добавьте из прайса «Оклейка»",
                      style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                    ),
                  )
                else
                  for (final c in children) _buildWrapPackageCompositionRow(c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorksListView() {
    final header = _wrapPackageHeader();
    final children = header != null
        ? _wrapPackageChildren((header['id'] as num).toInt())
        : <Map<String, dynamic>>[];
    final standalone = _standaloneWorks();

    if (_isWorkshopMode) {
      final workshopItems = <Map<String, dynamic>>[
        ...children,
        ...standalone,
      ].where((w) => _resolvedWorkWorkshop(w) == widget.workshop).toList();

      if (workshopItems.isEmpty) {
        return Center(
          child: Text(
            "Нет работ этого цеха",
            style: GoogleFonts.manrope(color: AppColors.textDim),
          ),
        );
      }
      return ListView(
        children: [
          for (final w in workshopItems) _buildWorkCard(w, hidePrice: true),
        ],
      );
    }

    if (header == null && standalone.isEmpty) {
      return Center(
        child: Text(
          "Нет услуг в заказе",
          style: GoogleFonts.manrope(color: AppColors.textDim),
        ),
      );
    }

    return ListView(
      children: [
        if (header != null) _buildWrapPackageBlock(header, children),
        for (final w in standalone) _buildWorkCard(w),
      ],
    );
  }

  Widget _buildScheduleColumn() {
    return Column(
      children: [
        _section(
          title: "ГРАФИК ЗАКАЗА",
          child: Column(
            children: [
              _timeBadge(
                value: _orderStartTime,
                emptyLabel: "Начало",
                color: AppColors.success,
                onTap: () async {
                  String? dt = await _pickDateTime(current: _orderStartTime);
                  if (dt != null) {
                    setState(() => _orderStartTime = dt);
                    final parsed = DateTime.parse(dt.replaceFirst(' ', 'T'));
                    await DatabaseHelper().updateOrderSchedule(
                      widget.order['id'],
                      DateFormat('yyyy-MM-dd').format(parsed),
                      _orderStartTime!,
                      _orderEndTime ?? "",
                      "",
                    );
                    await DatabaseHelper().addOrderEvent(widget.order['id'], "Начало работ: ${_formatDT(dt, dt)}");
                    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
                    setState(() {});
                  }
                },
              ),
              const SizedBox(height: 10),
              _timeBadge(
                value: _orderEndTime,
                emptyLabel: "Конец",
                color: AppColors.danger,
                onTap: () async {
                  String? dt = await _pickDateTime(current: _orderEndTime ?? _orderStartTime);
                  if (dt != null) {
                    setState(() => _orderEndTime = dt);
                    String due = "";
                    if (_orderStartTime != null && _orderStartTime!.isNotEmpty) {
                      due = DateFormat('yyyy-MM-dd').format(DateTime.parse(_orderStartTime!.replaceFirst(' ', 'T')));
                    }
                    await DatabaseHelper().updateOrderSchedule(
                      widget.order['id'],
                      due,
                      _orderStartTime ?? "",
                      _orderEndTime!,
                      "",
                    );
                    await DatabaseHelper().addOrderEvent(widget.order['id'], "Окончание работ: ${_formatDT(dt, dt)}");
                    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
                    setState(() {});
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: AppColors.border),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                title: Text(
                  "Техническая мойка",
                  style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                iconColor: AppColors.primary,
                collapsedIconColor: AppColors.textMuted,
                children: [
                  SwitchListTile(
                    title: Text(
                      "Добавить в календарь мойки",
                      style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12),
                    ),
                    value: _isTechWash,
                    activeColor: AppColors.primary,
                    onChanged: (val) async {
                      setState(() => _isTechWash = val);
                      if (!val) {
                        _techWashStart = null;
                        _techWashEnd = null;
                        await DatabaseHelper().setTechWash(widget.order['id'], null, null);
                        await DatabaseHelper().addOrderEvent(widget.order['id'], "Техническая мойка отменена");
                        _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
                        setState(() {});
                      }
                    },
                  ),
                  if (_isTechWash)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Column(
                        children: [
                          _timeBadge(
                            value: _techWashStart,
                            emptyLabel: "Время ОТ",
                            color: AppColors.primary,
                            onTap: () async {
                              String? dt = await _pickDateTime(current: _techWashStart);
                              if (dt != null) {
                                setState(() => _techWashStart = dt);
                                await DatabaseHelper().setTechWash(widget.order['id'], _techWashStart, _techWashEnd);
                                await DatabaseHelper().addOrderEvent(widget.order['id'], "Тех. мойка: начало ${_formatDT(dt, dt)}");
                                _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
                                setState(() {});
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          _timeBadge(
                            value: _techWashEnd,
                            emptyLabel: "Время ДО",
                            color: AppColors.danger,
                            onTap: () async {
                              String? dt = await _pickDateTime(current: _techWashEnd ?? _techWashStart);
                              if (dt != null) {
                                setState(() => _techWashEnd = dt);
                                await DatabaseHelper().setTechWash(widget.order['id'], _techWashStart, _techWashEnd);
                                await DatabaseHelper().addOrderEvent(widget.order['id'], "Тех. мойка: конец ${_formatDT(dt, dt)}");
                                _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
                                setState(() {});
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotesColumn() {
    return Column(
      children: [
        _section(
          title: "ЗАМЕТКИ",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Диалог с клиентом",
                      style: GoogleFonts.manrope(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _clientNotesController,
                      decoration: const InputDecoration(labelText: "От клиента", isDense: true),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (val) => _submitNoteToTimeline(
                        text: val,
                        eventPrefix: "От клиента",
                        controller: _clientNotesController,
                        persist: (t) => DatabaseHelper().updateOrderClientNotes(widget.order['id'], t),
                      ),
                      onChanged: (val) async {
                        await DatabaseHelper().updateOrderClientNotes(widget.order['id'], val);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _visibleNotesController,
                      decoration: const InputDecoration(labelText: "Для клиента", isDense: true),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (val) => _submitNoteToTimeline(
                        text: val,
                        eventPrefix: "Для клиента",
                        controller: _visibleNotesController,
                        persist: (t) => DatabaseHelper().updateOrderClientVisibleNotes(widget.order['id'], t),
                      ),
                      onChanged: (val) async {
                        await DatabaseHelper().updateOrderClientVisibleNotes(widget.order['id'], val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _selectedWorkshopForComment,
                decoration: const InputDecoration(labelText: "Цех", isDense: true),
                dropdownColor: AppColors.surface,
                items: STATUSES.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (val) => setState(() => _selectedWorkshopForComment = val!),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _masterCommentController,
                decoration: const InputDecoration(labelText: "Комментарий от цеха", isDense: true),
                textInputAction: TextInputAction.send,
                onSubmitted: (val) => _submitNoteToTimeline(
                  text: val,
                  eventPrefix: "Цех «$_selectedWorkshopForComment»",
                  controller: _masterCommentController,
                  persist: (t) => DatabaseHelper().updateOrderMasterNotes(widget.order['id'], t),
                ),
                onChanged: (val) async {
                  await DatabaseHelper().updateOrderMasterNotes(widget.order['id'], val);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: _buildPinnedTimelineBody(
              composer: TextField(
                controller: _commentController,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _addCommentToTimeline(),
                style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Комментарий в ленту (Enter)...',
                  hintStyle: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: "Отправить",
                    icon: const Icon(Icons.send, size: 18, color: AppColors.primary),
                    onPressed: _addCommentToTimeline,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _discountPercentController,
                  decoration: const InputDecoration(labelText: "Скидка %", isDense: true),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) {
                    _discountPercent = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                  },
                  onEditingComplete: () async {
                    await _persistDiscount(
                      eventText: _discountPercent > 0 || _discountFixed > 0
                          ? "Скидка: ${_formatMoney(_discountPercent)}% + ${_formatMoney(_discountFixed)} ₽"
                          : "Скидка снята",
                    );
                    FocusManager.instance.primaryFocus?.unfocus();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _discountFixedController,
                  decoration: const InputDecoration(labelText: "Скидка ₽", isDense: true),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) {
                    _discountFixed = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                  },
                  onEditingComplete: () async {
                    await _persistDiscount(
                      eventText: _discountPercent > 0 || _discountFixed > 0
                          ? "Скидка: ${_formatMoney(_discountPercent)}% + ${_formatMoney(_discountFixed)} ₽"
                          : "Скидка снята",
                    );
                    FocusManager.instance.primaryFocus?.unfocus();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _promoController,
                  decoration: const InputDecoration(labelText: "Промокод", isDense: true),
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _applyPromoFromField(),
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: _applyPromoFromField,
                child: Text("Применить", style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
              TextButton(
                onPressed: _showManagePromosDialog,
                child: Text("Коды…", style: GoogleFonts.manrope(fontSize: 12)),
              ),
              const Spacer(),
              if (_discountAmount > 0.01)
                Text(
                  "−${_formatMoney(_discountAmount)} ₽ от ${_formatMoney(_worksTotal)}",
                  style: GoogleFonts.manrope(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 180,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Итого к оплате",
                      style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      "${_formatMoney(_initialPrice)} ₽",
                      style: GoogleFonts.manrope(color: AppColors.success, fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      "Оплачено: ${_formatMoney(_paidAmount)} ₽",
                      style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
                    ),
                    Text(
                      "Долг: ${_formatMoney(_debt)} ₽",
                      style: GoogleFonts.manrope(color: AppColors.danger, fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _autoPayController,
                  readOnly: true,
                  enableInteractiveSelection: false,
                  decoration: const InputDecoration(
                    labelText: "К оплате (авто)",
                    isDense: true,
                    helperText: "С учётом скидки",
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _payAmountController,
                  decoration: const InputDecoration(
                    labelText: "Оплатить сейчас",
                    isDense: true,
                    helperText: "Часть или другая сумма",
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _paymentMethod,
                  decoration: const InputDecoration(labelText: "Метод", isDense: true),
                  dropdownColor: AppColors.surface,
                  items: ['Наличные', 'Карта', 'Перевод', 'По счету', 'Не указан']
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (val) async {
                    if (val == null) return;
                    setState(() => _paymentMethod = val);
                    await DatabaseHelper().updateOrderPaymentMethod(widget.order['id'], val);
                  },
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(onPressed: _addPayment, child: const Text("Оплатить")),
              const Spacer(),
              TextButton(onPressed: _closeDialog, child: const Text("Отмена")),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _closeDialog, child: const Text("Закрыть")),
            ],
          ),
        ],
      ),
    );
  }

  String _workshopMastersLabel() {
    final ws = widget.workshop;
    if (ws == null) return '';
    final idSet = <int>{};
    for (final w in _selectedWorks) {
      if (isWrapPackageHeader(w['name']?.toString())) continue;
      if (_resolvedWorkWorkshop(w) != ws) continue;
      idSet.addAll(parseMasterIds(w['master_ids']));
    }
    return masterNamesFromIds(_masters, idSet.toList());
  }

  Future<void> _pickMastersForWorkshop() async {
    final ws = widget.workshop;
    if (ws == null) return;

    final idSet = <int>{};
    for (final w in _selectedWorks) {
      if (isWrapPackageHeader(w['name']?.toString())) continue;
      if (_resolvedWorkWorkshop(w) != ws) continue;
      idSet.addAll(parseMasterIds(w['master_ids']));
    }

    final picked = await pickWorkshopMasters(
      context,
      workshop: ws,
      masters: _masters,
      initialIds: idSet.toList(),
    );
    if (picked == null) return;

    await DatabaseHelper().assignMastersToWorkshop(
      widget.order['id'] as int,
      ws,
      picked,
    );

    final csv = picked.join(',');
    setState(() {
      for (var i = 0; i < _selectedWorks.length; i++) {
        if (isWrapPackageHeader(_selectedWorks[i]['name']?.toString())) continue;
        if (_resolvedWorkWorkshop(_selectedWorks[i]) != ws) continue;
        _selectedWorks[i] = {
          ..._selectedWorks[i],
          'master_ids': csv,
        };
      }
    });

    final names = masterNamesFromIds(_masters, picked);
    final event = names.isEmpty
        ? 'Цех «$ws»: сняты все мастера'
        : 'Цех «$ws»: назначены $names';
    await DatabaseHelper().addOrderEvent(widget.order['id'], event);
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    if (mounted) setState(() {});
  }

  Widget _buildWorkshopHeader() {
    final o = widget.order;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Заказ #${o['id']} · ${widget.workshop}",
                  style: GoogleFonts.manrope(
                    color: AppColors.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "${o['client_name'] ?? ''}",
                  style: GoogleFonts.manrope(
                    color: AppColors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if ((o['client_phone']?.toString() ?? "").isNotEmpty) o['client_phone'],
                    if ((o['make_model']?.toString() ?? "").isNotEmpty) o['make_model'],
                    if ((o['plate']?.toString() ?? "").isNotEmpty) o['plate'],
                  ].join(" · "),
                  style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: "Печать заказ-наряда",
            onPressed: _printWorkOrder,
            icon: const Icon(Icons.print_outlined, color: AppColors.primary),
          ),
          IconButton(
            tooltip: "Закрыть",
            onPressed: _closeDialog,
            icon: const Icon(Icons.close, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkshopMastersBlock() {
    final names = _workshopMastersLabel();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Мастер цеха",
                  style: GoogleFonts.manrope(
                    color: AppColors.textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  names.isEmpty ? "Не назначен" : names,
                  style: GoogleFonts.manrope(
                    color: names.isEmpty ? AppColors.textMuted : AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _pickMastersForWorkshop,
            icon: Icon(
              names.isEmpty ? Icons.person_add_alt_1 : Icons.groups,
              size: 18,
              color: AppColors.primary,
            ),
            label: Text(
              names.isEmpty ? "Назначить" : "Изменить",
              style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkshopWorkRow(int index) {
    final w = _selectedWorks[index];
    final isDone = (w['is_done'] as num?)?.toInt() == 1;
    final ws = _resolvedWorkWorkshop(w);
    final canToggle = _canToggleWorkInWorkshop(w);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      decoration: BoxDecoration(
        color: isDone ? AppColors.surface2 : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDone ? AppColors.success.withOpacity(0.4) : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: isDone,
            activeColor: AppColors.success,
            side: BorderSide(color: canToggle ? AppColors.border : AppColors.textDim),
            onChanged: canToggle ? (val) => _toggleWorkDone(index, val == true) : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${w['name']}",
                  style: GoogleFonts.manrope(
                    color: canToggle ? AppColors.text : AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                    decorationColor: AppColors.textDim,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ws.isEmpty ? "Без цеха" : ws,
                  style: GoogleFonts.manrope(
                    color: canToggle ? AppColors.primary : AppColors.textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkshopBody() {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 720,
        height: 820,
        child: Column(
          children: [
            _buildWorkshopHeader(),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildWorkshopMastersBlock(),
                    Text("Работы", style: AppTheme.sectionTitle),
                    const SizedBox(height: 4),
                    Text(
                      "Галочка доступна только для цеха «${widget.workshop}»",
                      style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      flex: 3,
                      child: _selectedWorks.isEmpty
                          ? Center(
                              child: Text(
                                "Нет работ",
                                style: GoogleFonts.manrope(color: AppColors.textDim),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _selectedWorks.length,
                              itemBuilder: (context, index) => _buildWorkshopWorkRow(index),
                            ),
                    ),
                    const SizedBox(height: 14),
                    Text("Лента событий", style: AppTheme.sectionTitle),
                    const SizedBox(height: 8),
                    Expanded(
                      flex: 2,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(AppTheme.radius),
                          border: Border.all(color: AppColors.border),
                        ),
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                        child: _buildPinnedTimelineBody(
                          composer: TextField(
                            controller: _commentController,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _addWorkshopMasterComment(),
                            style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: "Комментарий от цеха (Enter)…",
                              hintStyle: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
                              isDense: true,
                              suffixIcon: IconButton(
                                tooltip: "Отправить",
                                icon: const Icon(Icons.send, size: 18, color: AppColors.primary),
                                onPressed: _addWorkshopMasterComment,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget panel;
    if (_isLoading) {
      panel = Dialog(
        backgroundColor: AppColors.surface,
        child: SizedBox(
          width: _isWorkshopMode ? 720 : 1500,
          height: _isWorkshopMode ? 820 : 1200,
          child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      );
    } else if (_isWorkshopMode) {
      panel = _buildWorkshopBody();
    } else {
      panel = GestureDetector(
        onTap: () {
          _priceListController.collapse();
          FocusManager.instance.primaryFocus?.unfocus();
        },
        child: Dialog(
          backgroundColor: AppColors.surface,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: 1500,
            height: 1200,
            child: Column(
              children: [
                KeyedSubtree(key: TourKeys.orderDetailsHeader, child: _buildHeader()),
                const Divider(height: 1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: KeyedSubtree(
                            key: TourKeys.orderDetailsWorks,
                            child: _buildWorksColumn(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: KeyedSubtree(
                            key: TourKeys.orderDetailsSchedule,
                            child: _buildScheduleColumn(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: KeyedSubtree(
                            key: TourKeys.orderDetailsNotes,
                            child: _buildNotesColumn(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                KeyedSubtree(key: TourKeys.orderDetailsPayment, child: _buildFooter()),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _closeDialog();
      },
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: panel,
          ),
        ),
      ),
    );
  }
}
