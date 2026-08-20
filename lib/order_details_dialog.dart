import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_datetime.dart';
import 'app_theme.dart';
import 'app_toast.dart';
import 'cash_catalog.dart';
import 'crm/cloud_db_bridge.dart';
import 'database.dart';
import 'issue_guard.dart';
import 'master_picker.dart';
import 'order_defects_sheet.dart';
import 'inventory_catalog.dart';
import 'order_wrap_films_panel.dart';
import 'pulse_anchor.dart';
import 'quick_datetime_picker.dart';
import 'ready_notify_actions.dart';
import 'responsive.dart';
import 'schedule_conflict.dart';
import 'service_category_browser.dart';
import 'tour_keys.dart';
import 'work_order_pdf.dart';
import 'works_progress_bar.dart';
import 'zone_package_dialog.dart';

class OrderDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> order;
  /// Если задан — упрощённый режим карточки для цеха.
  final String? workshop;
  /// На телефоне открывается как fullscreen route.
  final bool fullscreen;

  const OrderDetailsDialog({
    super.key,
    required this.order,
    this.workshop,
    this.fullscreen = false,
  });

  /// Единая точка открытия: mobile → fullscreen, desktop → dialog.
  static Future<bool?> open(
    BuildContext context,
    Map<String, dynamic> order, {
    String? workshop,
  }) {
    if (AppResponsive.isMobile(context)) {
      return Navigator.of(context, rootNavigator: true).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => OrderDetailsDialog(
            order: order,
            workshop: workshop,
            fullscreen: true,
          ),
        ),
      );
    }
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

class _OrderDetailsDialogState extends State<OrderDetailsDialog>
    with SingleTickerProviderStateMixin, PulseHighlightMixin {
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
  late TextEditingController _paymentMethodController; // отображение метода (как у соседних TextField)
  late TextEditingController _discountPercentController;
  late TextEditingController _discountFixedController;
  late TextEditingController _promoController;
  late TextEditingController _clientNotesController; // Комментарий от клиента
  late TextEditingController _visibleNotesController; // Комментарий для клиента
  String _paymentMethod = CashMethods.cash;
  final GlobalKey _paymentMethodFieldKey = GlobalKey();
  final GlobalKey _paymentRegisterFieldKey = GlobalKey();
  late TextEditingController _paymentRegisterController;
  List<Map<String, dynamic>> _cashRegisters = [];
  int? _selectedRegisterId;

  List<Map<String, dynamic>> _masters = [];
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _payments = [];
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
  Map<String, dynamic> _handover = {};
  int _lastLiveRev = -1;
  bool _liveRefreshBusy = false;
  bool _handoverExpanded = false;

  @override
  void initState() {
    super.initState();
    _lastLiveRev = DatabaseHelper.dataRevision.value;
    DatabaseHelper.dataRevision.addListener(_onLiveDataRevision);
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
    final rawMethod = widget.order['payment_method']?.toString() ?? CashMethods.cash;
    _paymentMethod = rawMethod == 'Не указан' || rawMethod.isEmpty ? CashMethods.cash : rawMethod;
    _paymentMethodController = TextEditingController(text: _paymentMethod);
    _paymentRegisterController = TextEditingController();
    _discountPercentController = TextEditingController(
      text: _discountPercent == 0 ? "" : _formatMoney(_discountPercent),
    );
    _discountFixedController = TextEditingController(
      text: _discountFixed == 0 ? "" : _formatMoney(_discountFixed),
    );
    _promoController = TextEditingController(text: _promoCode);
    _clientNotesController = TextEditingController(text: widget.order['client_notes'] ?? "");
    _visibleNotesController = TextEditingController(text: widget.order['client_visible_notes'] ?? "");
    _loadData();
  }

  @override
  void dispose() {
    DatabaseHelper.dataRevision.removeListener(_onLiveDataRevision);
    _enterCtrl.dispose();
    _commentController.dispose();
    _priceController.dispose();
    _autoPayController.dispose();
    _payAmountController.dispose();
    _paymentMethodController.dispose();
    _paymentRegisterController.dispose();
    _discountPercentController.dispose();
    _discountFixedController.dispose();
    _promoController.dispose();
    _clientNotesController.dispose();
    _visibleNotesController.dispose();
    super.dispose();
  }

  void _onLiveDataRevision() {
    final rev = DatabaseHelper.dataRevision.value;
    if (rev == _lastLiveRev) return;
    _lastLiveRev = rev;
    unawaited(_refreshLiveFromDb());
  }

  /// Лента / чеклист / дефект-события с телефона без полного _loadData.
  Future<void> _refreshLiveFromDb() async {
    if (_liveRefreshBusy || !mounted) return;
    _liveRefreshBusy = true;
    try {
      final orderId = widget.order['id'];
      final events = await DatabaseHelper().getOrderEvents(orderId);
      final handover = await DatabaseHelper().getOrderHandover(orderId as int);
      if (!mounted) return;
      setState(() {
        _events = events;
        _handover = handover;
      });
    } finally {
      _liveRefreshBusy = false;
    }
  }

  Future<void> _openDefectsSheet({String? workshop}) async {
    await OrderDefectsSheet.open(
      context,
      orderId: widget.order['id'] as int,
      workshop: workshop ?? widget.workshop ?? '',
    );
    if (mounted) await _refreshLiveFromDb();
  }

  Future<void> _loadData() async {
    try {
      _masters = await DatabaseHelper().getAllMastersFull();
      _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
      _selectedMasterId = widget.order['master_id'];
      _clientCars = await DatabaseHelper().getClientCars(widget.order['client_id']);
      _selectedCarId = widget.order['car_id'];

      if (_selectedCarId != null) {
        var car = _clientCars.firstWhere((c) => c['id'] == _selectedCarId, orElse: () => {});
        if (car.isNotEmpty) _currentCarCategory = car['category'] ?? "1";
      }

      try {
        _services = await DatabaseHelper().getAllServices();
      } catch (e, st) {
        debugPrint('OrderDetails.getAllServices: $e\n$st');
        _services = [];
      }
      try {
        _cashRegisters = await DatabaseHelper().getCashRegisters();
      } catch (e, st) {
        debugPrint('OrderDetails.getCashRegisters: $e\n$st');
        _cashRegisters = [];
      }
      _handover = await DatabaseHelper().getOrderHandover(widget.order['id'] as int);
      _payments = await DatabaseHelper().getOrderPayments(widget.order['id'] as int);
      _syncRegisterForMethod(_paymentMethod, preferKeep: false);

      final dbItems = await DatabaseHelper().getOrderItems(widget.order['id']);
      _selectedWorks = dbItems.map((item) => Map<String, dynamic>.from(item)).toList();
      for (var i = 0; i < _selectedWorks.length; i++) {
        final w = _selectedWorks[i];
        final current = (w['workshop'] as String?)?.trim() ?? "";
        if (current.isNotEmpty && WORKSHOPS.contains(current)) continue;
        final auto = workshopForService(name: w['name']?.toString());
        if (auto == null) continue;
        final wid = (w['id'] as num?)?.toInt() ?? 0;
        if (wid > 0) {
          await DatabaseHelper().updateOrderItemSchedule(
            wid,
            w['start_time'] as String?,
            w['end_time'] as String?,
            auto,
          );
        }
        _selectedWorks[i] = {...w, 'workshop': auto};
      }
      if (_selectedWorks.isEmpty && !CloudDbBridge.active) {
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
      final rawMethod = widget.order['payment_method']?.toString() ?? CashMethods.cash;
      _paymentMethod = rawMethod == 'Не указан' || rawMethod.isEmpty ? CashMethods.cash : rawMethod;
      _paymentMethodController.text = _paymentMethod;
      _syncRegisterForMethod(_paymentMethod, preferKeep: false);
    } catch (e, st) {
      debugPrint('OrderDetails._loadData: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось загрузить заказ: $e'),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) {
        _enterCtrl.value = 0;
        setState(() => _isLoading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_closing) _enterCtrl.forward();
        });
      }
    }
  }

  // --- ФУНКЦИИ РАБОТЫ С УСЛУГАМИ ---
  final _customWorkName = TextEditingController();
  final _customWorkPrice = TextEditingController();

  String _formatDT(String? dtStr, String defaultText) =>
      AppDateTime.formatShort(dtStr, fallback: defaultText);

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
    await runWithPulseHighlight(
      'od_promo',
      () => showDialog<void>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setInner) {
              return AlertDialog(
                backgroundColor: AppColors.surface,
                title: Text("Промокоды", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                content: SizedBox(
                  width: AppResponsive.dialogWidth(context, desktop: 420),
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
      ),
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
    try {
      await DatabaseHelper().addOrderItem(
        widget.order['id'],
        name,
        price,
        category: category,
        workshop: workshop,
      );
      final wsNote = workshop != null ? " → цех $workshop" : "";
      final priceNote = isZonePackageLine(category: category, name: name)
          ? (isTintPackageLine(category: category, name: name) ? "в пакет тонировки" : "в пакет оклейки")
          : "$price руб";
      await DatabaseHelper().addOrderEvent(
        widget.order['id'],
        "Добавлена работа: $name ($priceNote)$wsNote",
      );
      _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
      await _reloadWorksFromDb();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось добавить работу: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
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

  /// Какие плёнки показывать в расходе: оклейка и/или тонировка — по составу заказа.
  List<String> _orderFilmCategories() {
    var wrap = false;
    var tint = false;
    for (final w in _selectedWorks) {
      final name = w['name']?.toString();
      final cat = w['category']?.toString();
      if (isTintPackageHeader(name) || isTintPackageLine(category: cat, name: name)) {
        tint = true;
      }
      if (isWrapPackageHeader(name) || isWrapPackageLine(category: cat, name: name)) {
        wrap = true;
      }
    }
    if (wrap && tint) {
      return const [InventoryCategories.filmWrap, InventoryCategories.filmTint];
    }
    if (tint && !wrap) return const [InventoryCategories.filmTint];
    // Заказ оклейки / цех Оклейка без явной тонировки — только оклеечная плёнка.
    return const [InventoryCategories.filmWrap];
  }

  Future<void> _toggleWorkDone(int index, bool done) async {
    final w = _selectedWorks[index];
    if (_isWorkshopMode && !_canToggleWorkInWorkshop(w)) return;
    final warnings = await DatabaseHelper().updateOrderItemDone(w['id'] as int, done);
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
    if (warnings.isNotEmpty && mounted) {
      showAppToast(
        context,
        warnings.length == 1
            ? 'Склад: ${warnings.first}'
            : 'Склад: нехватка по ${warnings.length} позициям',
      );
    }
  }

  Future<void> _addWorkshopMasterComment() async {
    if (_timelineSubmitBusy) return;
    final text = _commentController.text.trim();
    if (text.isEmpty || widget.workshop == null) return;
    _timelineSubmitBusy = true;
    try {
      await DatabaseHelper().addOrderEvent(
        widget.order['id'],
        "От цеха «${widget.workshop}»: $text",
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

  String _formatEventTime(dynamic raw) => AppDateTime.format(raw);

  /// Разбор текста события для чистого UI + цвет цеха.
  /// [direction]: forShop | fromShop | null.
  ({String? workshop, String body, Color accent, String? direction}) _parseTimelineEvent(String raw) {
    final t = raw.trim();

    final fromShopExplicit = RegExp(r'^От цеха «([^»]+)»:\s*(.*)$').firstMatch(t);
    if (fromShopExplicit != null) {
      final w = fromShopExplicit.group(1)!;
      return (
        workshop: w,
        body: fromShopExplicit.group(2)!.trim(),
        accent: _workshopColors[w] ?? AppColors.primary,
        direction: 'fromShop',
      );
    }

    final fromShopLegacy = RegExp(r'^Комментарий от цеха «([^»]+)»:\s*(.*)$').firstMatch(t);
    if (fromShopLegacy != null) {
      final w = fromShopLegacy.group(1)!;
      return (
        workshop: w,
        body: fromShopLegacy.group(2)!.trim(),
        accent: _workshopColors[w] ?? AppColors.primary,
        direction: 'fromShop',
      );
    }

    final forShop = RegExp(r'^Для цеха «([^»]+)»:\s*(.*)$').firstMatch(t);
    if (forShop != null) {
      final w = forShop.group(1)!;
      return (
        workshop: w,
        body: forShop.group(2)!.trim(),
        accent: _workshopColors[w] ?? AppColors.primary,
        direction: 'forShop',
      );
    }

    // Старый формат из цеха: Цех «Мойка»: …
    final shopLine = RegExp(r'^Цех «([^»]+)»:\s*(.*)$').firstMatch(t);
    if (shopLine != null) {
      final w = shopLine.group(1)!;
      return (
        workshop: w,
        body: shopLine.group(2)!.trim(),
        accent: _workshopColors[w] ?? AppColors.primary,
        direction: 'fromShop',
      );
    }

    final plain = RegExp(r'^Комментарий:\s*(.*)$').firstMatch(t);
    if (plain != null) {
      return (
        workshop: null,
        body: plain.group(1)!.trim(),
        accent: AppColors.textMuted,
        direction: null,
      );
    }

    // Статус изменен на: Мойка
    final status = RegExp(r'^Статус изменен на:\s*(.+)$').firstMatch(t);
    if (status != null) {
      final name = status.group(1)!.trim();
      return (
        workshop: name,
        body: 'Статус → $name',
        accent: _workshopColors[name] ?? AppColors.primary,
        direction: null,
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
          direction: null,
        );
      }
    }

    return (workshop: null, body: t, accent: AppColors.textMuted, direction: null);
  }

  Widget _buildPlainTimelineEvent(Map<String, dynamic> ev) {
    final raw = ev['event_text']?.toString() ?? '';
    final parsed = _parseTimelineEvent(raw);
    final time = _formatEventTime(ev['created_at']);
    final accent = parsed.accent;
    final isShopNote = parsed.direction == 'forShop' || parsed.direction == 'fromShop';

    if (isShopNote && parsed.workshop != null) {
      final isFor = parsed.direction == 'forShop';
      final dirLabel = isFor ? 'Для' : 'От';
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$dirLabel · ${parsed.workshop}',
                    style: GoogleFonts.manrope(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  TextSpan(
                    text: '\n${parsed.body}',
                    style: GoogleFonts.manrope(
                      color: AppColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
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

  Future<void> _addPayment() async {
    // Справа — ручная сумма; если пусто — берём авто-долг слева
    final manual = _payAmountController.text.trim().replaceAll(',', '.');
    double amount;
    if (manual.isNotEmpty) {
      amount = double.tryParse(manual) ?? 0;
    } else {
      amount = double.tryParse(_autoPayController.text.replaceAll(',', '.')) ?? _debt;
    }
    if (amount <= 0) return;

    if (_paymentMethod == 'Не указан' || !CashMethods.all.contains(_paymentMethod)) {
      if (!mounted) return;
      showAppToast(context, 'Выберите способ оплаты');
      return;
    }
    if (_cashRegisters.isNotEmpty && _selectedRegisterId == null) {
      if (!mounted) return;
      showAppToast(context, 'Выберите кассу для оплаты');
      return;
    }

    if (!mounted) return;
    final confirmPay = await runWithPulseHighlight(
      'od_pay',
      () => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Провести оплату?', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
          content: Text(
            'Сумма: ${_formatMoney(amount)} ₽\nСпособ: $_paymentMethod\n\n'
            'Если ошиблись — оплату потом можно отменить в списке ниже.',
            style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.35),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Провести'),
            ),
          ],
        ),
      ),
    );
    if (confirmPay != true || !mounted) return;

    final shift = await DatabaseHelper().getCurrentShift();
    if (shift == null) {
      if (!mounted) return;
      await runWithPulseHighlight(
        'od_pay',
        () => showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('Смена не открыта', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
            content: Text(
              'Откройте смену в разделе «Касса», затем проведите оплату.\n'
              'Без смены оплата запрещена.',
              style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.35),
            ),
            actions: [
              ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
            ],
          ),
        ),
      );
      return;
    }

    var registerId = _selectedRegisterId;
    if (registerId == null) {
      registerId = await DatabaseHelper().resolveRegisterIdForMethod(_paymentMethod);
      _selectedRegisterId = registerId;
    }
    String? registerName = _registerNameById(registerId);
    if (registerName == null && registerId != null) {
      _cashRegisters = await DatabaseHelper().getCashRegisters();
      registerName = _registerNameById(registerId);
      _syncRegisterLabel();
    }

    await DatabaseHelper().addPayment(
      widget.order['id'],
      amount,
      _paymentMethod,
      shiftId: (shift['id'] as num).toInt(),
      registerId: registerId,
    );
    await DatabaseHelper().updateOrderPaymentMethod(widget.order['id'], _paymentMethod);
    final regNote = registerName != null ? ' → $registerName' : '';
    await DatabaseHelper().addOrderEvent(
      widget.order['id'],
      "Внесена оплата: $amount руб ($_paymentMethod)$regNote",
    );

    _paidAmount += amount;
    _payAmountController.clear();
    _syncAutoPayField();
    _payments = await DatabaseHelper().getOrderPayments(widget.order['id'] as int);
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    if (!mounted) return;
    setState(() {});
    showAppToast(
      context,
      registerName != null
          ? 'Оплата ${_formatMoney(amount)} ₽ · зачислено в «$registerName»'
          : 'Оплата ${_formatMoney(amount)} ₽ ($_paymentMethod)',
    );
  }

  Future<void> _voidPayment(Map<String, dynamic> pay) async {
    final id = (pay['id'] as num?)?.toInt();
    if (id == null) return;
    final amount = (pay['amount'] as num?)?.toDouble() ?? 0;
    final method = pay['method']?.toString() ?? '';
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Отменить оплату?', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: Text(
          'Сумма ${_formatMoney(amount)} ₽ ($method) будет снята с заказа и из кассы/отчётов.',
          style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.35),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отменить оплату'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    final voided = await DatabaseHelper().voidPayment(id);
    if (voided == null) {
      if (mounted) showAppToast(context, 'Платёж уже удалён');
      return;
    }
    await DatabaseHelper().addOrderEvent(
      widget.order['id'],
      'Отменена оплата: ${_formatMoney(amount)} ₽ ($method)',
    );
    _paidAmount = (_paidAmount - amount).clamp(0.0, double.infinity);
    _syncAutoPayField();
    _payments = await DatabaseHelper().getOrderPayments(widget.order['id'] as int);
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    if (!mounted) return;
    setState(() {});
    showAppToast(context, 'Оплата ${_formatMoney(amount)} ₽ отменена');
  }

  ButtonStyle get _payButtonStyle => ElevatedButton.styleFrom(
        backgroundColor: AppColors.success,
        foregroundColor: Colors.white,
      );

  Widget _paymentsList({bool compact = false}) {
    if (_payments.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: compact ? 8 : 10, bottom: compact ? 4 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Проведённые оплаты',
            style: GoogleFonts.manrope(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final p in _payments)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_formatMoney((p['amount'] as num?)?.toDouble() ?? 0)} ₽ · '
                        '${p['method'] ?? ''} · ${AppDateTime.format(p['created_at'])}',
                        style: GoogleFonts.manrope(color: AppColors.text, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _voidPayment(p),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Отменить'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String? _registerNameById(int? id) {
    if (id == null) return null;
    for (final r in _cashRegisters) {
      if ((r['id'] as num).toInt() == id) return r['name']?.toString();
    }
    return null;
  }

  void _syncRegisterLabel() {
    final name = _registerNameById(_selectedRegisterId);
    _paymentRegisterController.text = name ?? (_cashRegisters.isEmpty ? 'Нет касс' : 'Выберите кассу');
  }

  /// Подбирает кассу под метод оплаты (money_type). [preferKeep] — не менять, если текущая подходит.
  void _syncRegisterForMethod(String method, {bool preferKeep = true}) {
    if (_cashRegisters.isEmpty) {
      _selectedRegisterId = null;
      _syncRegisterLabel();
      return;
    }
    if (preferKeep && _selectedRegisterId != null) {
      for (final r in _cashRegisters) {
        if ((r['id'] as num).toInt() == _selectedRegisterId &&
            r['money_type']?.toString() == method) {
          _syncRegisterLabel();
          return;
        }
      }
    }
    Map<String, dynamic>? match;
    for (final r in _cashRegisters) {
      if (r['money_type']?.toString() == method) {
        match = r;
        break;
      }
    }
    _selectedRegisterId = ((match ?? _cashRegisters.first)['id'] as num).toInt();
    _syncRegisterLabel();
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
      decoration: AppTheme.panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(title, style: AppTheme.sectionLabel),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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

    await runWithPulseHighlight(
      'od_masters',
      () => showDialog(
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
                                  if (!mounted) return;
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
      ),
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
        color: isDone ? AppColors.success.withOpacity(0.06) : AppColors.bg.withOpacity(0.45),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border(
          left: BorderSide(
            color: isDone ? AppColors.success.withOpacity(0.75) : AppColors.borderSoft,
            width: 3,
          ),
        ),
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
          _workCommentField(w),
        ],
      ),
    );
  }

  bool get _isMobileLayout => widget.fullscreen || AppResponsive.isMobile(context);

  static const _adminRoles = {'Администратор', 'Приемщик'};

  bool _isAdminRole(String? role) => masterHasAnyRole(role, _adminRoles);

  /// Сотрудники для поля «Администратор» (+ текущий, если роль устарела).
  List<Map<String, dynamic>> get _adminsForDropdown {
    final list = _masters.where((m) => _isAdminRole(m['role']?.toString())).toList();
    if (_selectedMasterId != null &&
        !list.any((m) => m['id'] == _selectedMasterId)) {
      final cur = _masters.where((m) => m['id'] == _selectedMasterId).toList();
      if (cur.isNotEmpty) list.insert(0, cur.first);
    }
    return list;
  }

  int? get _safeMasterDropdownValue {
    if (_selectedMasterId == null) return null;
    final ok = _adminsForDropdown.any((m) => m['id'] == _selectedMasterId);
    return ok ? _selectedMasterId : null;
  }

  int? get _safeCarDropdownValue {
    if (_selectedCarId == null) return null;
    final ok = _clientCars.any((c) => c['id'] == _selectedCarId);
    return ok ? _selectedCarId : null;
  }

  bool _handoverValue(String key) => (_handover[key] as num?)?.toInt() == 1;

  bool get _handoverComplete => _handoverItems.keys.every(_handoverValue);

  Future<void> _setHandoverValue(String key, bool checked) async {
    final wasReady = _handoverValue('handover_ready');
    final next = Map<String, dynamic>.from(_handover)..[key] = checked ? 1 : 0;
    final complete = _handoverItems.keys.every((item) => (next[item] as num?)?.toInt() == 1);
    next['handover_ready'] = complete ? 1 : 0;
    await DatabaseHelper().saveOrderHandover(widget.order['id'] as int, next);
    if (!wasReady && complete) {
      await DatabaseHelper().addOrderEvent(widget.order['id'], 'Чек-лист выдачи: готово');
      _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    }
    if (mounted) setState(() => _handover = next);
  }

  Future<bool> _ensureHandoverCompleteForIssue() async {
    if (_handoverComplete) return true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Чек-лист выдачи не завершён', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: Text(
          'Чтобы перевести заказ в «Выдан», отметьте все пункты чек-листа выдачи.',
          style: GoogleFonts.manrope(color: AppColors.textMuted),
        ),
        actions: [
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
        ],
      ),
    );
    return false;
  }

  Future<void> _notifyReadyWhatsApp() async {
    final order = <String, dynamic>{
      'id': widget.order['id'],
      'client_name': widget.order['client_name'],
      'client_phone': widget.order['client_phone'],
      'make_model': widget.order['make_model'],
      'plate': widget.order['plate'],
      'price': _initialPrice,
      'paid_amount': _paidAmount,
    };
    final ok = await ReadyNotifyActions.notifyOrder(
      context,
      order: order,
      markHandoverNotified: false,
    );
    if (!ok || !mounted) return;
    await _setHandoverValue('handover_notified', true);
    await DatabaseHelper().addOrderEvent(widget.order['id'], 'WhatsApp: уведомление о готовности');
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    if (mounted) setState(() {});
  }

  /// Порядок = реальный сценарий выдачи (до визита → QC → осмотр → оплата → ключи).
  static const _handoverItems = <String, String>{
    'handover_notified': 'Клиент уведомлён о готовности',
    'handover_works': 'Работы проверены (QC)',
    'handover_inspect': 'Авто осмотрено с клиентом',
    'handover_payment': 'Оплата проверена / закрыта',
    'handover_keys': 'Ключи и документы переданы',
  };

  int get _handoverDoneCount =>
      _handoverItems.keys.where(_handoverValue).length;

  /// Компактная кнопка; по нажатию раскрывается чек-лист выдачи.
  Widget _buildHandoverChecklist() {
    final done = _handoverDoneCount;
    final total = _handoverItems.length;
    final complete = _handoverComplete;
    final accent = complete ? AppColors.success : AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: complete
            ? AppColors.success.withOpacity(0.08)
            : AppColors.surface2.withOpacity(0.85),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border(
          left: BorderSide(color: accent.withOpacity(0.8), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              onTap: () => setState(() => _handoverExpanded = !_handoverExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(
                  children: [
                    Icon(
                      complete ? Icons.verified_outlined : Icons.checklist_rtl,
                      size: 20,
                      color: accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Чек-лист выдачи',
                            style: GoogleFonts.manrope(
                              color: AppColors.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            complete ? 'Готово к выдаче' : 'Отмечено $done из $total',
                            style: GoogleFonts.manrope(
                              color: complete ? AppColors.success : AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$done/$total',
                        style: GoogleFonts.manrope(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _handoverExpanded ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_handoverExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Column(
                children: _handoverItems.entries.map((entry) {
                  final isNotify = entry.key == 'handover_notified';
                  return CheckboxListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.primary,
                    title: Text(
                      entry.value,
                      style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13),
                    ),
                    secondary: isNotify
                        ? IconButton(
                            tooltip: 'WhatsApp: готов к выдаче',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.chat_outlined, color: AppColors.success, size: 20),
                            onPressed: _notifyReadyWhatsApp,
                          )
                        : null,
                    value: _handoverValue(entry.key),
                    onChanged: (value) => _setHandoverValue(entry.key, value ?? false),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusDropdown() {
    final statusValue = STATUSES.contains(_status) ? _status : STATUSES.first;
    return DropdownButtonFormField<String>(
      value: statusValue,
      isExpanded: true,
      decoration: const InputDecoration(labelText: "Статус", isDense: true),
      dropdownColor: AppColors.surface,
      items: STATUSES
          .map((s) => DropdownMenuItem(
                value: s,
                child: Text(s, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (val) async {
        if (val == null || val == _status) return;
        if (val == 'Выдан' && !await _ensureHandoverCompleteForIssue()) return;
        if (!mounted) return;
        final ok = await tryUpdateOrderStatus(
          context,
          widget.order['id'] as int,
          val,
        );
        if (!mounted) return;
        if (!ok) return;
        setState(() => _status = val);
        await DatabaseHelper().addOrderEvent(widget.order['id'], "Статус изменен на: $val");
        _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
        if (mounted) setState(() {});
      },
    );
  }

  Widget _adminDropdown() {
    final admins = _adminsForDropdown;
    return DropdownButtonFormField<int>(
      value: _safeMasterDropdownValue,
      isExpanded: true,
      decoration: const InputDecoration(labelText: "Администратор", isDense: true),
      dropdownColor: AppColors.surface,
      items: [
        const DropdownMenuItem<int>(
          value: null,
          child: Text("Не назначен", overflow: TextOverflow.ellipsis),
        ),
        ...admins.map((m) {
          final role = m['role']?.toString() ?? '';
          final name = m['name']?.toString() ?? '';
          final label = _isAdminRole(role) ? name : '$name ($role)';
          return DropdownMenuItem<int>(
            value: m['id'] as int?,
            child: Text(label, overflow: TextOverflow.ellipsis),
          );
        }),
      ],
      onChanged: (val) async {
        if (val == _selectedMasterId) return;
        setState(() => _selectedMasterId = val);
        await DatabaseHelper().updateOrderMaster(widget.order['id'], val);
        String masterName = "Не назначен";
        if (val != null) {
          final foundMaster = _masters.where((m) => m['id'] == val).toList();
          if (foundMaster.isNotEmpty) masterName = foundMaster.first['name'];
        }
        await DatabaseHelper().addOrderEvent(widget.order['id'], "Назначен администратор: $masterName");
        _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
        if (mounted) setState(() {});
      },
    );
  }

  /// Коммент под работой → БД + сразу в ленту («для цеха»).
  /// Возвращает true, если событие попало в ленту.
  Future<bool> _saveWorkComment(int itemId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    final idx = _selectedWorks.indexWhere((w) => (w['id'] as num?)?.toInt() == itemId);
    final w = idx >= 0 ? _selectedWorks[idx] : null;
    var ws = w?['workshop']?.toString() ?? '';
    if (ws.isEmpty) {
      ws = workshopForService(name: w?['name']?.toString()) ?? 'Цех';
    }
    final workName = w?['name']?.toString() ?? '';
    final body = workName.isEmpty ? trimmed : '$trimmed · $workName';

    try {
      await DatabaseHelper().updateOrderItemComment(itemId, trimmed);
    } catch (e) {
      debugPrint('updateOrderItemComment: $e');
      // Колонка/синк могли сбоить — ленту всё равно пишем.
    }

    try {
      await DatabaseHelper().addOrderEvent(
        widget.order['id'],
        "Для цеха «$ws»: $body",
      );
      _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
      if (idx >= 0) {
        _selectedWorks[idx]['comment'] = trimmed;
      }
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Отправлено в ленту'), duration: Duration(seconds: 1)),
        );
      }
      return true;
    } catch (e) {
      debugPrint('addOrderEvent work comment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось отправить: $e')),
        );
      }
      return false;
    }
  }

  Widget _workCommentField(Map<String, dynamic> w) {
    final id = (w['id'] as num?)?.toInt();
    if (id == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _WorkItemCommentField(
        key: ValueKey('work_for_shop_$id'),
        itemId: id,
        initial: w['comment']?.toString() ?? '',
        onSend: _saveWorkComment,
      ),
    );
  }

  Widget _carDropdown() {
    return DropdownButtonFormField<int>(
      value: _safeCarDropdownValue,
      isExpanded: true,
      decoration: const InputDecoration(labelText: "Автомобиль", isDense: true),
      dropdownColor: AppColors.surface,
      items: _clientCars.map((car) {
        final vin = (car['vin'] ?? '').toString();
        final label = vin.isEmpty
            ? "${car['make_model']} | ${car['plate']}"
            : "${car['make_model']} | ${car['plate']} | VIN $vin";
        return DropdownMenuItem<int>(
          value: car['id'] as int,
          child: Text(label, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: (val) async {
        if (val == null) return;
        setState(() => _selectedCarId = val);
        await DatabaseHelper().reassignOrderCar(widget.order['id'], val);
        final selectedCar = _clientCars.firstWhere((c) => c['id'] == val);
        await DatabaseHelper().addOrderEvent(
          widget.order['id'],
          "Изменено авто на: ${selectedCar['make_model']} | ${selectedCar['plate']}",
        );
        _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildHeader() {
    final mobile = _isMobileLayout;
    final client = widget.order['client_name']?.toString() ?? '';
    return Padding(
      padding: EdgeInsets.fromLTRB(mobile ? 12 : 22, 16, mobile ? 8 : 16, 12),
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
                      'ЗАКАЗ #${widget.order['id']}',
                      style: AppTheme.sectionLabel,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      client.isEmpty ? 'Без клиента' : client,
                      style: GoogleFonts.manrope(
                        color: AppColors.text,
                        fontSize: mobile ? 20 : 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.35,
                        height: 1.15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: "Печать заказ-наряда",
                onPressed: _printWorkOrder,
                icon: const Icon(Icons.print_outlined, color: AppColors.textMuted),
              ),
              IconButton(
                tooltip: 'Дефекты',
                onPressed: () async {
                  await _openDefectsSheet();
                },
                icon: const Icon(Icons.report_problem_outlined, color: AppColors.danger),
              ),
              IconButton(
                tooltip: 'Закрыть',
                onPressed: _closeDialog,
                icon: const Icon(Icons.close, color: AppColors.textDim),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (mobile) ...[
            _statusDropdown(),
            const SizedBox(height: 10),
            _adminDropdown(),
            const SizedBox(height: 10),
            _carDropdown(),
            const SizedBox(height: 10),
            KeyedSubtree(key: TourKeys.orderDetailsSchedule, child: _buildScheduleRow()),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _statusDropdown()),
                const SizedBox(width: 12),
                Expanded(child: _adminDropdown()),
                const SizedBox(width: 12),
                Expanded(child: _carDropdown()),
              ],
            ),
            const SizedBox(height: 10),
            KeyedSubtree(key: TourKeys.orderDetailsSchedule, child: _buildScheduleRow()),
          ],
          _buildHandoverChecklist(),
          // В полном заказе — только просмотр/правка; основное заполнение — в цехе Оклейка.
          if (!_isWorkshopMode &&
              _selectedWorks.any((work) => work['workshop']?.toString() == 'Оклейка')) ...[
            const SizedBox(height: 12),
            OrderWrapFilmsPanel(
              orderId: widget.order['id'] as int,
              collapsible: true,
              initiallyExpanded: false,
              filmCategories: _orderFilmCategories(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWorksColumn({bool fill = true, bool showTitle = true}) {
    final list = _buildWorksListView(shrinkWrap: !fill);
    return Container(
      decoration: AppTheme.panelDecoration,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (showTitle) ...[
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
          ],
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
                    color: AppColors.bg.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                  ),
                  child: ServiceCategoryBrowser(
                    services: _services,
                    carCategory: _currentCarCategory,
                    onAdd: _addWork,
                    onConfigurePackage: _openZonePackageFromCategory,
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
          if (fill) Expanded(child: list) else list,
        ],
      ),
    );
  }

  Map<String, dynamic>? _zonePackageHeader(String headerName) {
    for (final w in _selectedWorks) {
      if ((w['name']?.toString() ?? '') == headerName && w['parent_id'] == null) {
        return w;
      }
    }
    return null;
  }

  Map<String, dynamic>? _wrapPackageHeader() => _zonePackageHeader('Оклейка');

  Map<String, dynamic>? _tintPackageHeader() => _zonePackageHeader('Тонировка');

  List<Map<String, dynamic>> _wrapPackageChildren(int headerId) {
    return _selectedWorks
        .where((w) => (w['parent_id'] as num?)?.toInt() == headerId)
        .toList();
  }

  List<Map<String, dynamic>> _standaloneWorks() {
    return _selectedWorks.where((w) {
      if (isZonePackageHeader(w['name']?.toString()) && w['parent_id'] == null) {
        return false;
      }
      if (w['parent_id'] != null) return false;
      return true;
    }).toList();
  }

  Future<void> _openZonePackageFromCategory(String category) async {
    final kind = zonePackageKindForCategory(category);
    if (kind == null) return;
    await _openZonePackageEditor(kind);
  }

  Future<void> _openZonePackageEditor(String kind) async {
    final headerName = zonePackageHeaderName(kind);
    final category = zonePackageCategory(kind);
    final catalog = _services
        .where((s) => (s['category'] ?? '').toString() == category)
        .toList();
    final header = _zonePackageHeader(headerName);
    final children = header != null
        ? _wrapPackageChildren((header['id'] as num).toInt())
        : <Map<String, dynamic>>[];
    final selected = children.map((c) => (c['name'] ?? '').toString()).toSet();
    final price = (header?['price'] as num?)?.toDouble() ?? 0;

    final result = await runWithPulseHighlight(
      'od_works',
      () => ZonePackageDialog.open(
        context,
        kind: kind,
        catalogZones: catalog,
        initiallySelected: selected,
        initialPrice: price,
      ),
    );
    if (result == null || !mounted) return;

    try {
      await DatabaseHelper().syncZonePackage(
        orderId: widget.order['id'] as int,
        kind: kind,
        zoneNames: result.zoneNames,
        packagePrice: result.packagePrice,
      );
      final label = headerName;
      final event = result.zoneNames.isEmpty
          ? "Пакет «$label» удалён"
          : "Пакет «$label»: ${result.zoneNames.length} зон, ${_formatMoney(result.packagePrice)} ₽";
      await DatabaseHelper().addOrderEvent(widget.order['id'], event);
      if (!mounted) return;
      _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
      await _reloadWorksFromDb();
      if (mounted) _priceListController.collapse();
    } catch (e, st) {
      debugPrint('_openZonePackageEditor: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить пакет: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _toggleWrapPackageDone(
    Map<String, dynamic> header,
    List<Map<String, dynamic>> children,
    bool done,
  ) async {
    final headerId = (header['id'] as num).toInt();
    final label = header['name']?.toString() ?? 'Пакет';
    final warnings = await DatabaseHelper().updateWrapPackageDone(headerId, done);
    final log = done
        ? "Пакет «$label» выполнен (${children.length} поз.)"
        : "Снята отметка выполнения пакета «$label»";
    await DatabaseHelper().addOrderEvent(widget.order['id'], log);
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    await _reloadWorksFromDb();
    if (warnings.isNotEmpty && mounted) {
      showAppToast(
        context,
        warnings.length == 1
            ? 'Склад: ${warnings.first}'
            : 'Склад: нехватка по ${warnings.length} позициям',
      );
    }
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

    await runWithPulseHighlight(
      'od_masters',
      () => showDialog(
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
      ),
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

  Widget _buildWrapPackageCompositionRow(
    Map<String, dynamic> child, {
    bool workshopView = false,
    bool canToggleZones = true,
  }) {
    final isDone = (child['is_done'] as num?)?.toInt() == 1;
    final label = (child['name']?.toString() ?? '')
        .replaceFirst(RegExp(r'^(Оклейка|Тонировка)\s*·\s*'), '');
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(4, 0, 2, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDone ? AppColors.success.withOpacity(0.4) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Checkbox(
                value: isDone,
                activeColor: AppColors.success,
                side: BorderSide(color: canToggleZones ? AppColors.border : AppColors.textDim),
                onChanged: !canToggleZones
                    ? null
                    : (val) async {
                        final id = (child['id'] as num).toInt();
                        final idx = _selectedWorks.indexWhere((w) => (w['id'] as num?)?.toInt() == id);
                        if (idx >= 0) await _toggleWorkDone(idx, val == true);
                      },
              ),
              Expanded(
                child: Text(
                  label.isEmpty ? "${child['name']}" : label,
                  style: GoogleFonts.manrope(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                    decorationColor: AppColors.textDim,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!workshopView)
                IconButton(
                  tooltip: "Убрать из пакета",
                  icon: const Icon(Icons.close, color: AppColors.danger, size: 18),
                  onPressed: () => _removeWork(child),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8),
            child: _workCommentField(child),
          ),
        ],
      ),
    );
  }

  Widget _buildWrapPackageBlock(
    Map<String, dynamic> header,
    List<Map<String, dynamic>> children, {
    bool workshopView = false,
  }) {
    final price = (header['price'] as num?)?.toDouble() ?? 0;
    final doneCount = children.where((c) => (c['is_done'] as num?)?.toInt() == 1).length;
    final allDone = children.isNotEmpty && doneCount == children.length;
    final someDone = doneCount > 0 && !allDone;
    final masters = _masterNamesFor(header);
    final hasMasters = masters.isNotEmpty;
    final packageName = header['name']?.toString() ?? 'Пакет';
    final kind = isTintPackageHeader(packageName) ? 'tint' : 'wrap';
    final canToggle = !workshopView || widget.workshop == 'Оклейка';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
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
                side: BorderSide(color: canToggle ? AppColors.border : AppColors.textDim),
                onChanged: !canToggle || children.isEmpty
                    ? null
                    : (_) => _toggleWrapPackageDone(header, children, !allDone),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "$packageName · ${children.length} поз.",
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
              if (!workshopView) ...[
                Flexible(
                  child: TextButton(
                    onPressed: () => _openZonePackageEditor(kind),
                    child: Text(
                      "${_formatMoney(price)} ₽",
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        color: AppColors.success,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
                  tooltip: "Зоны и сумма",
                  onPressed: () => _openZonePackageEditor(kind),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    hasMasters ? Icons.groups : Icons.person_add_alt_1,
                    color: hasMasters ? AppColors.primary : AppColors.textDim,
                    size: 20,
                  ),
                  tooltip: "Мастера пакета",
                  onPressed: () => _pickMastersForWrapPackage(header),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: "Удалить пакет",
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                  onPressed: () => _removeWork(header),
                ),
              ],
            ],
          ),
          if (!workshopView) ...[
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
          ],
          _workCommentField(header),
          const SizedBox(height: 4),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              // Всегда свёрнут: на мобилке/в цехе иначе зоны оклейки забивают экран.
              // Не true при rebuild — live-refresh снова раскрывал бы список.
              initiallyExpanded: false,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 4),
              iconColor: AppColors.primary,
              collapsedIconColor: AppColors.textMuted,
              title: Text(
                "Состав · $doneCount из ${children.length} · нажмите, чтобы раскрыть",
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
                  for (final c in children)
                    _buildWrapPackageCompositionRow(
                      c,
                      workshopView: workshopView,
                      canToggleZones: canToggle,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorksListView({bool shrinkWrap = false}) {
    final wrapHeader = _wrapPackageHeader();
    final wrapChildren = wrapHeader != null
        ? _wrapPackageChildren((wrapHeader['id'] as num).toInt())
        : <Map<String, dynamic>>[];
    final tintHeader = _tintPackageHeader();
    final tintChildren = tintHeader != null
        ? _wrapPackageChildren((tintHeader['id'] as num).toInt())
        : <Map<String, dynamic>>[];
    final standalone = _standaloneWorks();
    final scrollPhysics = shrinkWrap ? const NeverScrollableScrollPhysics() : null;

    if (_isWorkshopMode) {
      return _buildWorkshopWorksList(shrinkWrap: shrinkWrap);
    }

    if (wrapHeader == null && tintHeader == null && standalone.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          "Нет услуг в заказе",
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(color: AppColors.textDim),
        ),
      );
    }

    return ListView(
      shrinkWrap: shrinkWrap,
      physics: scrollPhysics,
      children: [
        if (wrapHeader != null) _buildWrapPackageBlock(wrapHeader, wrapChildren),
        if (tintHeader != null) _buildWrapPackageBlock(tintHeader, tintChildren),
        for (final w in standalone) _buildWorkCard(w),
      ],
    );
  }

  String get _techWashChipLabel {
    if (!_isTechWash) return '+ Тех. мойка';
    final a = _formatDT(_techWashStart, '');
    final b = _formatDT(_techWashEnd, '');
    if (a.isNotEmpty && b.isNotEmpty) return 'Тех. мойка · $a – $b';
    if (a.isNotEmpty) return 'Тех. мойка · с $a';
    if (b.isNotEmpty) return 'Тех. мойка · до $b';
    return 'Тех. мойка · без времени';
  }

  Future<void> _openTechWashDialog() async {
    var enabled = _isTechWash;
    String? start = _techWashStart;
    String? end = _techWashEnd;

    final ok = await runWithPulseHighlight(
      'od_schedule',
      () => showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              return AlertDialog(
                backgroundColor: AppColors.surface,
                title: Text(
                  'Техническая мойка',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                ),
                content: SizedBox(
                  width: AppResponsive.dialogWidth(ctx, desktop: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'В календарь мойки',
                          style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14),
                        ),
                        value: enabled,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setLocal(() => enabled = v),
                      ),
                      if (enabled) ...[
                        const SizedBox(height: 8),
                        _timeBadge(
                          value: start,
                          emptyLabel: 'Время ОТ',
                          color: AppColors.primary,
                          onTap: () async {
                            final dt = await _pickDateTime(current: start);
                            if (dt != null) setLocal(() => start = dt);
                          },
                        ),
                        const SizedBox(height: 8),
                        _timeBadge(
                          value: end,
                          emptyLabel: 'Время ДО',
                          color: AppColors.danger,
                          onTap: () async {
                            final dt = await _pickDateTime(current: end ?? start);
                            if (dt != null) setLocal(() => end = dt);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                  ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Готово')),
                ],
              );
            },
          );
        },
      ),
    );
    if (ok != true || !mounted) return;

    if (!enabled) {
      setState(() {
        _isTechWash = false;
        _techWashStart = null;
        _techWashEnd = null;
      });
      await DatabaseHelper().setTechWash(widget.order['id'], null, null);
      await DatabaseHelper().addOrderEvent(widget.order['id'], 'Техническая мойка отменена');
    } else {
      final prevStart = _techWashStart;
      final prevEnd = _techWashEnd;
      setState(() {
        _isTechWash = true;
        _techWashStart = start;
        _techWashEnd = end;
      });
      await DatabaseHelper().setTechWash(widget.order['id'], start, end);
      if (start != null && start != prevStart) {
        await DatabaseHelper().addOrderEvent(
          widget.order['id'],
          'Тех. мойка: начало ${_formatDT(start, '')}',
        );
      }
      if (end != null && end != prevEnd) {
        await DatabaseHelper().addOrderEvent(
          widget.order['id'],
          'Тех. мойка: конец ${_formatDT(end, '')}',
        );
      }
      if (prevStart == null && prevEnd == null && start == null && end == null) {
        await DatabaseHelper().addOrderEvent(widget.order['id'], 'Техническая мойка включена');
      }
    }
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    if (mounted) setState(() {});
  }

  Widget _techWashButton({bool compact = false}) {
    final active = _isTechWash;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openTechWashDialog,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: compact ? null : double.infinity,
          height: compact ? 44 : null,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 0 : 12),
          decoration: BoxDecoration(
            color: active ? AppColors.primary.withOpacity(0.12) : AppColors.surface2,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(
              color: active ? AppColors.primary.withOpacity(0.55) : AppColors.border,
            ),
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Icon(
                active ? Icons.local_car_wash : Icons.local_car_wash_outlined,
                size: 18,
                color: active ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _techWashChipLabel,
                  style: GoogleFonts.manrope(
                    color: active ? AppColors.text : AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!compact)
                Icon(Icons.chevron_right, size: 18, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setOrderStartTime() async {
    final dt = await runWithPulseHighlight(
      'od_schedule',
      () => _pickDateTime(current: _orderStartTime),
    );
    if (dt == null || !mounted) return;
    final end = _orderEndTime ?? '';
    if (end.isNotEmpty) {
      final ok = await confirmNoScheduleConflict(
        context,
        startTime: dt,
        endTime: end,
        excludeOrderId: widget.order['id'] as int?,
      );
      if (!ok || !mounted) return;
    }
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
    if (mounted) setState(() {});
  }

  Future<void> _setOrderEndTime() async {
    final dt = await runWithPulseHighlight(
      'od_schedule',
      () => _pickDateTime(current: _orderEndTime ?? _orderStartTime),
    );
    if (dt == null || !mounted) return;
    final start = _orderStartTime ?? '';
    if (start.isNotEmpty) {
      final ok = await confirmNoScheduleConflict(
        context,
        startTime: start,
        endTime: dt,
        excludeOrderId: widget.order['id'] as int?,
      );
      if (!ok || !mounted) return;
    }
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
    if (mounted) setState(() {});
  }

  /// Подпись «ГРАФИК» между статусом и полями; времена/техмойка — в одну линию.
  Widget _buildScheduleRow() {
    return PulseAnchor(
      active: isPulseActive('od_schedule'),
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ГРАФИК',
            style: GoogleFonts.manrope(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _timeBadge(
                  value: _orderStartTime,
                  emptyLabel: 'Приём',
                  color: AppColors.success,
                  onTap: _setOrderStartTime,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _timeBadge(
                  value: _orderEndTime,
                  emptyLabel: 'Выдача',
                  color: AppColors.danger,
                  onTap: _setOrderEndTime,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _techWashButton(compact: true)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotesColumn({bool fill = true}) {
    final timeline = Container(
      height: fill ? null : 280,
      decoration: AppTheme.panelDecoration,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
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
    );

    return Column(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      children: [
        _section(
          title: "ЗАМЕТКИ",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                decoration: BoxDecoration(
                  color: AppColors.bg.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(AppTheme.radius),
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
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (fill) Expanded(child: timeline) else timeline,
      ],
    );
  }

  Future<void> _onDiscountEditingComplete() async {
    await _persistDiscount(
      eventText: _discountPercent > 0 || _discountFixed > 0
          ? "Скидка: ${_formatMoney(_discountPercent)}% + ${_formatMoney(_discountFixed)} ₽"
          : "Скидка снята",
    );
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Widget _discountPercentField() {
    return TextField(
      controller: _discountPercentController,
      decoration: const InputDecoration(labelText: "Скидка %", isDense: true),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (v) {
        _discountPercent = double.tryParse(v.replaceAll(',', '.')) ?? 0;
      },
      onEditingComplete: _onDiscountEditingComplete,
    );
  }

  Widget _discountFixedField() {
    return TextField(
      controller: _discountFixedController,
      decoration: const InputDecoration(labelText: "Скидка ₽", isDense: true),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (v) {
        _discountFixed = double.tryParse(v.replaceAll(',', '.')) ?? 0;
      },
      onEditingComplete: _onDiscountEditingComplete,
    );
  }

  Widget _promoField() {
    return TextField(
      controller: _promoController,
      decoration: const InputDecoration(labelText: "Промокод", isDense: true),
      textCapitalization: TextCapitalization.characters,
      onSubmitted: (_) => _applyPromoFromField(),
    );
  }

  static const _paymentMethods = CashMethods.all;

  /// Тот же TextField, что у «К оплате» / «Оплатить сейчас» — DropdownButtonFormField
  /// на Windows рисует поле ниже из‑за своей внутренней геометрии.
  Widget _paymentMethodDropdown({String? helperText}) {
    return TextField(
      key: _paymentMethodFieldKey,
      controller: _paymentMethodController,
      readOnly: true,
      enableInteractiveSelection: false,
      mouseCursor: SystemMouseCursors.click,
      onTap: _pickPaymentMethod,
      decoration: InputDecoration(
        labelText: 'Метод',
        isDense: true,
        helperText: helperText ?? 'Нал / карта / перевод / по счету',
        suffixIcon: const Icon(Icons.arrow_drop_down, size: 22),
      ),
    );
  }

  Future<void> _pickPaymentMethod() async {
    final box = _paymentMethodFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    // Меню под рамкой поля, без учёта helper-текста (~18–22 px).
    final fieldBottom = origin.dy + size.height - (18);
    final selected = await showMenu<String>(
      context: context,
      color: AppColors.surface,
      position: RelativeRect.fromLTRB(
        origin.dx,
        fieldBottom,
        origin.dx + size.width,
        fieldBottom,
      ),
      items: _paymentMethods
          .map((m) => PopupMenuItem<String>(value: m, child: Text(m)))
          .toList(),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _paymentMethod = selected;
      _paymentMethodController.text = selected;
      _syncRegisterForMethod(selected, preferKeep: false);
    });
    await DatabaseHelper().updateOrderPaymentMethod(widget.order['id'], selected);
  }

  Widget _paymentRegisterDropdown({String? helperText}) {
    return TextField(
      key: _paymentRegisterFieldKey,
      controller: _paymentRegisterController,
      readOnly: true,
      enableInteractiveSelection: false,
      mouseCursor: SystemMouseCursors.click,
      onTap: _cashRegisters.isEmpty ? null : _pickPaymentRegister,
      decoration: InputDecoration(
        labelText: 'Касса',
        isDense: true,
        helperText: helperText ?? 'Куда зачислить',
        suffixIcon: const Icon(Icons.arrow_drop_down, size: 22),
      ),
    );
  }

  Future<void> _pickPaymentRegister() async {
    if (_cashRegisters.isEmpty) return;
    final box = _paymentRegisterFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    final fieldBottom = origin.dy + size.height - 18;
    final selected = await showMenu<int>(
      context: context,
      color: AppColors.surface,
      position: RelativeRect.fromLTRB(
        origin.dx,
        fieldBottom,
        origin.dx + size.width,
        fieldBottom,
      ),
      items: _cashRegisters.map((r) {
        final id = (r['id'] as num).toInt();
        final name = r['name']?.toString() ?? 'Касса';
        final type = r['money_type']?.toString() ?? '';
        return PopupMenuItem<int>(
          value: id,
          child: Text('$name${type.isEmpty ? '' : ' · $type'}'),
        );
      }).toList(),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedRegisterId = selected;
      _syncRegisterLabel();
      // Подтянуть метод оплаты под тип выбранной кассы
      for (final r in _cashRegisters) {
        if ((r['id'] as num).toInt() == selected) {
          final type = r['money_type']?.toString() ?? '';
          if (type.isNotEmpty && CashMethods.all.contains(type) && type != _paymentMethod) {
            _paymentMethod = type;
            _paymentMethodController.text = type;
            DatabaseHelper().updateOrderPaymentMethod(widget.order['id'], type);
          }
          break;
        }
      }
    });
  }

  Widget _totalsColumn({bool alignEnd = false}) {
    final align = alignEnd ? TextAlign.right : TextAlign.left;
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Итого к оплате",
          textAlign: align,
          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        Text(
          "${_formatMoney(_initialPrice)} ₽",
          textAlign: align,
          style: GoogleFonts.manrope(color: AppColors.success, fontSize: 16, fontWeight: FontWeight.w800),
        ),
        Text(
          "Оплачено: ${_formatMoney(_paidAmount)} ₽",
          textAlign: align,
          style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
        ),
        Text(
          "Долг: ${_formatMoney(_debt)} ₽",
          textAlign: align,
          style: GoogleFonts.manrope(color: AppColors.danger, fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    final mobile = _isMobileLayout;
    return Container(
      padding: EdgeInsets.fromLTRB(mobile ? 12 : 22, 16, mobile ? 12 : 22, 16),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.98),
        border: const Border(top: BorderSide(color: AppColors.borderSoft)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: mobile ? _buildMobileFooter() : _buildDesktopFooter(),
    );
  }

  Widget _buildMobileFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _totalsColumn(),
        if (_discountAmount > 0.01) ...[
          const SizedBox(height: 4),
          Text(
            "−${_formatMoney(_discountAmount)} ₽ от ${_formatMoney(_worksTotal)}",
            style: GoogleFonts.manrope(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _discountPercentField()),
            const SizedBox(width: 8),
            Expanded(child: _discountFixedField()),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _promoField()),
            const SizedBox(width: 4),
            TextButton(
              onPressed: _applyPromoFromField,
              child: Text("Применить", style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 12)),
            ),
            TextButton(
              onPressed: _showManagePromosDialog,
              child: Text("Коды…", style: GoogleFonts.manrope(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _autoPayController,
          readOnly: true,
          enableInteractiveSelection: false,
          decoration: const InputDecoration(
            labelText: "К оплате (авто)",
            isDense: true,
            helperText: "С учётом скидки",
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
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
            const SizedBox(width: 8),
            Expanded(
              child: _paymentMethodDropdown(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _paymentRegisterDropdown(),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: _payButtonStyle,
            onPressed: _addPayment,
            child: const Text("Оплатить"),
          ),
        ),
        _paymentsList(compact: true),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _closeDialog, child: const Text("Закрыть")),
        ),
      ],
    );
  }

  Widget _buildDesktopFooter() {
    // Фиксированная ширина слота под «Применить / Коды», чтобы колонки
    // «Скидка %» ↔ «К оплате (авто)» совпадали по вертикали.
    const promoActionsWidth = 148.0;

    Widget payFieldAuto() => TextField(
          controller: _autoPayController,
          readOnly: true,
          enableInteractiveSelection: false,
          decoration: const InputDecoration(
            labelText: 'К оплате (авто)',
            isDense: true,
            helperText: 'С учётом скидки',
          ),
        );

    Widget payFieldManual() => TextField(
          controller: _payAmountController,
          decoration: const InputDecoration(
            labelText: 'Оплатить сейчас',
            isDense: true,
            helperText: 'Часть или другая сумма',
          ),
          keyboardType: TextInputType.number,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ОПЛАТА',
          style: GoogleFonts.manrope(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Строка 1: скидки — 3 равные колонки
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _discountPercentField()),
                      const SizedBox(width: 10),
                      Expanded(child: _discountFixedField()),
                      const SizedBox(width: 10),
                      Expanded(child: _promoField()),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: promoActionsWidth,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Flexible(
                                child: TextButton(
                                  onPressed: _applyPromoFromField,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'Применить',
                                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _showManagePromosDialog,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text('Коды', style: GoogleFonts.manrope(fontSize: 13)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_discountAmount > 0.01) ...[
                    const SizedBox(height: 4),
                    Text(
                      '−${_formatMoney(_discountAmount)} ₽ от ${_formatMoney(_worksTotal)}',
                      style: GoogleFonts.manrope(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // Строка 2: оплата — сумма / метод / касса (+ слот как у промо)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: payFieldAuto()),
                      const SizedBox(width: 10),
                      Expanded(child: payFieldManual()),
                      const SizedBox(width: 10),
                      Expanded(child: _paymentMethodDropdown()),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: promoActionsWidth,
                        child: _paymentRegisterDropdown(helperText: 'Касса'),
                      ),
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(width: 20),
            // Справа: суммы над кнопками действий
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _totalsColumn(alignEnd: true),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      style: _payButtonStyle,
                      onPressed: _addPayment,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        child: Text('Оплатить'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: _closeDialog, child: const Text('Закрыть')),
                  ],
                ),
                SizedBox(
                  width: 320,
                  child: _paymentsList(),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  String _workshopMastersLabel() {
    final ws = widget.workshop;
    if (ws == null) return '';
    final idSet = <int>{};
    for (final w in _selectedWorks) {
      if (isZonePackageHeader(w['name']?.toString())) continue;
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
      if (isZonePackageHeader(w['name']?.toString())) continue;
      if (_resolvedWorkWorkshop(w) != ws) continue;
      idSet.addAll(parseMasterIds(w['master_ids']));
    }

    final picked = await runWithPulseHighlight(
      'od_masters',
      () => pickWorkshopMasters(
        context,
        workshop: ws,
        masters: _masters,
        initialIds: idSet.toList(),
      ),
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
        if (isZonePackageHeader(_selectedWorks[i]['name']?.toString())) continue;
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
            tooltip: 'Дефекты',
            onPressed: () => _openDefectsSheet(),
            icon: const Icon(Icons.report_problem_outlined, color: AppColors.danger),
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
    return PulseAnchor(
      active: isPulseActive('od_masters'),
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: AppTheme.panelDecoration,
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

  /// Список работ цеха: пакеты оклейки/тонировки — блоками, без дубля шапка+зоны.
  Widget _buildWorkshopWorksList({bool shrinkWrap = false}) {
    final wrapHeader = _wrapPackageHeader();
    final wrapChildren = wrapHeader != null
        ? _wrapPackageChildren((wrapHeader['id'] as num).toInt())
        : <Map<String, dynamic>>[];
    final tintHeader = _tintPackageHeader();
    final tintChildren = tintHeader != null
        ? _wrapPackageChildren((tintHeader['id'] as num).toInt())
        : <Map<String, dynamic>>[];
    final packageIds = <int>{
      if (wrapHeader != null) (wrapHeader['id'] as num).toInt(),
      ...wrapChildren.map((c) => (c['id'] as num).toInt()),
      if (tintHeader != null) (tintHeader['id'] as num).toInt(),
      ...tintChildren.map((c) => (c['id'] as num).toInt()),
    };
    final otherIndexes = <int>[];
    for (var i = 0; i < _selectedWorks.length; i++) {
      final w = _selectedWorks[i];
      final id = (w['id'] as num?)?.toInt();
      if (id != null && packageIds.contains(id)) continue;
      final name = w['name']?.toString();
      // Зоны/шапки пакета не дублируем отдельными строками (в т.ч. сироты).
      if (isZonePackageHeader(name) || isZonePackageLine(name: name)) continue;
      otherIndexes.add(i);
    }

    if (wrapHeader == null && tintHeader == null && otherIndexes.isEmpty) {
      return Center(
        child: Text("Нет работ", style: GoogleFonts.manrope(color: AppColors.textDim)),
      );
    }

    return ListView(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      children: [
        if (wrapHeader != null)
          _buildWrapPackageBlock(wrapHeader, wrapChildren, workshopView: true),
        if (tintHeader != null)
          _buildWrapPackageBlock(tintHeader, tintChildren, workshopView: true),
        for (final i in otherIndexes) _buildWorkshopWorkRow(i),
      ],
    );
  }

  Widget _workshopInner() {
    final isWrapShop = widget.workshop == 'Оклейка';
    return Column(
      children: [
        _buildWorkshopHeader(),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(_isMobileLayout ? 12 : 20, 14, _isMobileLayout ? 12 : 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildWorkshopMastersBlock(),
                if (isWrapShop) ...[
                  OrderWrapFilmsPanel(
                    orderId: widget.order['id'] as int,
                    collapsible: true,
                    initiallyExpanded: false,
                    filmCategories: _orderFilmCategories(),
                  ),
                  const SizedBox(height: 10),
                ],
                Text("Работы", style: AppTheme.sectionTitle),
                const SizedBox(height: 4),
                Text(
                  "Галочка доступна только для цеха «${widget.workshop}»",
                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Expanded(
                  flex: 3,
                  child: _buildWorkshopWorksList(),
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
    );
  }

  Widget _buildWorkshopBody() {
    if (widget.fullscreen) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(child: _workshopInner()),
      );
    }
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 720,
        height: 820,
        child: _workshopInner(),
      ),
    );
  }

  Widget _adminColumnsBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: PulseAnchor(
              active: isPulseActive('od_works') || isPulseActive('od_masters'),
              child: KeyedSubtree(key: TourKeys.orderDetailsWorks, child: _buildWorksColumn()),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 2,
            child: KeyedSubtree(key: TourKeys.orderDetailsNotes, child: _buildNotesColumn()),
          ),
        ],
      ),
    );
  }

  Widget _mobileAccordion({
    required String title,
    String? subtitle,
    required Widget child,
    bool initiallyExpanded = false,
    Key? key,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.panelDecoration,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          iconColor: AppColors.primary,
          collapsedIconColor: AppColors.textMuted,
          title: Text(
            title,
            style: GoogleFonts.manrope(
              color: AppColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: subtitle == null || subtitle.isEmpty
              ? null
              : Text(
                  subtitle,
                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
          children: [child],
        ),
      ),
    );
  }

  Widget _buildMobileTitleBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "Заказ #${widget.order['id']}  ·  ${widget.order['client_name']}",
              style: GoogleFonts.manrope(
                color: AppColors.text,
                fontSize: 18,
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
            tooltip: 'Дефекты',
            onPressed: () => _openDefectsSheet(),
            icon: const Icon(Icons.report_problem_outlined, color: AppColors.danger),
          ),
          IconButton(
            onPressed: _closeDialog,
            icon: const Icon(Icons.close, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _adminMobileInner() {
    final countable = _selectedWorks.where((w) {
      if (isZonePackageHeader(w['name']?.toString()) && w['parent_id'] == null) return false;
      return true;
    }).toList();
    final worksTotal = countable.length;
    final worksDoneCount = countable.where((w) => (w['is_done'] as num?)?.toInt() == 1).length;
    final scheduleHint = [
      if (_orderStartTime != null && _orderStartTime!.isNotEmpty) _formatDT(_orderStartTime, ''),
      if (_orderEndTime != null && _orderEndTime!.isNotEmpty) _formatDT(_orderEndTime, ''),
    ].where((s) => s.isNotEmpty).join(' → ');

    return Column(
      children: [
        _buildMobileTitleBar(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            children: [
              _mobileAccordion(
                title: "Данные",
                subtitle: [
                  _status,
                  if (scheduleHint.isNotEmpty) scheduleHint,
                ].join(' · '),
                initiallyExpanded: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _statusDropdown(),
                    const SizedBox(height: 8),
                    _adminDropdown(),
                    const SizedBox(height: 8),
                    _carDropdown(),
                    const SizedBox(height: 10),
                    KeyedSubtree(key: TourKeys.orderDetailsSchedule, child: _buildScheduleRow()),
                  ],
                ),
              ),
              _mobileAccordion(
                key: TourKeys.orderDetailsWorks,
                title: "Работы",
                subtitle: worksTotal == 0
                    ? "Нет работ"
                    : "Выполнено $worksDoneCount из $worksTotal",
                initiallyExpanded: true,
                child: _buildWorksColumn(fill: false, showTitle: false),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                child: _buildHandoverChecklist(),
              ),
              if (_selectedWorks.any((work) => work['workshop']?.toString() == 'Оклейка'))
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  child: OrderWrapFilmsPanel(
                    orderId: widget.order['id'] as int,
                    collapsible: true,
                    initiallyExpanded: false,
                    filmCategories: _orderFilmCategories(),
                  ),
                ),
              _mobileAccordion(
                key: TourKeys.orderDetailsNotes,
                title: "Заметки",
                subtitle: "Диалог и лента",
                child: _buildNotesColumn(fill: false),
              ),
              _mobileAccordion(
                key: TourKeys.orderDetailsPayment,
                title: "Оплата",
                subtitle: "Итого ${_formatMoney(_initialPrice)} ₽ · долг ${_formatMoney(_debt)} ₽",
                initiallyExpanded: true,
                child: _buildMobileFooter(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _adminInner() {
    if (_isMobileLayout) return _adminMobileInner();
    return Column(
      children: [
        KeyedSubtree(key: TourKeys.orderDetailsHeader, child: _buildHeader()),
        const Divider(height: 1),
        Expanded(child: _adminColumnsBody()),
        PulseAnchor(
          active: isPulseActive('od_pay') || isPulseActive('od_promo'),
          child: KeyedSubtree(key: TourKeys.orderDetailsPayment, child: _buildFooter()),
        ),
      ],
    );
  }

  Widget _buildAdminBody() {
    final content = GestureDetector(
      onTap: () {
        _priceListController.collapse();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: _adminInner(),
    );

    if (widget.fullscreen) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        resizeToAvoidBottomInset: true,
        body: SafeArea(child: content),
      );
    }

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 1500,
        height: 1200,
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget panel;
    if (_isLoading) {
      if (widget.fullscreen) {
        panel = const Scaffold(
          backgroundColor: AppColors.surface,
          body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        );
      } else {
        panel = Dialog(
          backgroundColor: AppColors.surface,
          child: SizedBox(
            width: _isWorkshopMode ? 720 : 1500,
            height: _isWorkshopMode ? 820 : 1200,
            child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          ),
        );
      }
    } else if (_isWorkshopMode) {
      panel = _buildWorkshopBody();
    } else {
      panel = _buildAdminBody();
    }

    final animated = FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          child: panel,
        ),
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _closeDialog();
      },
      child: widget.fullscreen ? panel : animated,
    );
  }
}

/// Поле «Для цеха» под работой: Enter / кнопка → сразу в ленту.
class _WorkItemCommentField extends StatefulWidget {
  final int itemId;
  final String initial;
  final Future<bool> Function(int itemId, String text) onSend;

  const _WorkItemCommentField({
    super.key,
    required this.itemId,
    required this.initial,
    required this.onSend,
  });

  @override
  State<_WorkItemCommentField> createState() => _WorkItemCommentFieldState();
}

class _WorkItemCommentFieldState extends State<_WorkItemCommentField> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
    _focus = FocusNode();
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_saving) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      final ok = await widget.onSend(widget.itemId, text);
      if (!mounted) return;
      if (ok) {
        // Готово к следующему сообщению; текст уже в БД и в ленте.
        _ctrl.clear();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _send,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _send,
      },
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        enabled: !_saving,
        maxLines: 1,
        style: GoogleFonts.manrope(color: AppColors.text, fontSize: 12),
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _send(),
        decoration: InputDecoration(
          labelText: 'Для цеха',
          hintText: 'Enter или кнопка → в ленту',
          isDense: true,
          labelStyle: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12),
          hintStyle: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11),
          contentPadding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
          suffixIcon: IconButton(
            tooltip: 'Отправить в ленту',
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send, size: 18, color: AppColors.primary),
            onPressed: _saving ? null : _send,
          ),
        ),
      ),
    );
  }
}
