import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'access_model.dart';
import 'app_datetime.dart';
import 'app_notifications.dart';
import 'app_theme.dart';
import 'app_toast.dart';
import 'auth/auth_controller.dart';
import 'car_label.dart';
import 'cash_catalog.dart';
import 'client_notify.dart';
import 'crm/cloud_db_bridge.dart';
import 'database.dart';
import 'debt_reminder.dart';
import 'issue_guard.dart';
import 'master_picker.dart';
import 'on_shift_controller.dart';
import 'order_defects_sheet.dart';
import 'inventory_catalog.dart';
import 'order_lead_source.dart';
import 'order_wrap_films_panel.dart';
import 'outsource_assign_dialog.dart';
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
import 'ui_kit.dart';

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
      barrierColor: Colors.black.withValues(alpha: 0.55),
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
  VoidCallback? _orderModalRebuild;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    final tick = _orderModalRebuild;
    if (tick != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          tick();
        } catch (_) {}
      });
    }
  }

  // 1. Контроллер для текста комментария
  final TextEditingController _commentController = TextEditingController();
  bool _priceListOpen = false;
  final Set<int> _expandedWorkComments = {};
  /// Свёрнутые пакеты оклейки/тонировки в чек-листе цеха (по умолчанию раскрыты).
  final Set<int> _collapsedShopPackages = {};
  /// Общая зона «кнопка цеху + поле»: клик снаружи сворачивает сообщение.
  static const Object _workCommentTapGroup = Object();
  bool _timelineSubmitBusy = false;

  void _collapseWorkComments() {
    if (_expandedWorkComments.isEmpty) return;
    setState(() => _expandedWorkComments.clear());
    FocusManager.instance.primaryFocus?.unfocus();
  }

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
  String _leadSource = OrderLeadSources.unset;
  double _depositRequired = 0;
  Map<String, dynamic> _margin = const {
    'price': 0.0,
    'materials': 0.0,
    'payroll': 0.0,
    'outsource': 0.0,
    'margin': 0.0,
    'margin_pct': 0.0,
  };
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
  int? _selectedReceptionistId;
  List<Map<String, dynamic>> _clientCars = []; // Список авто клиента
  int? _selectedCarId; // Выбранное авто
  List<Map<String, dynamic>> _services = []; // Весь прайс-лист
  List<Map<String, dynamic>> _selectedWorks = []; // Выбранные работы (корзина)
  /// ЗП по цехам: workshop → [{master_id, amount}, ...]
  final Map<String, List<Map<String, dynamic>>> _payrollByWorkshop = {};
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
  bool _handoverExpanded = true;
  /// Max event id, помеченный прочитанным для бейджа ленты (локально на устройстве).
  int _feedSeenId = 0;

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
    _leadSource = OrderLeadSources.normalize(widget.order['lead_source']?.toString());
    _depositRequired = (widget.order['deposit_required'] as num?)?.toDouble() ?? 0;
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

  Future<void> _openDefectsSheet({String? workshop, ImageSource? initialSource}) async {
    final o = widget.order;
    await OrderDefectsSheet.open(
      context,
      orderId: o['id'] as int,
      workshop: workshop ?? widget.workshop ?? '',
      clientName: o['client_name']?.toString() ?? '',
      makeModel: o['make_model']?.toString() ?? '',
      plate: o['plate']?.toString() ?? '',
      initialSource: initialSource,
    );
    if (mounted) await _refreshLiveFromDb();
  }

  Future<void> _loadData() async {
    try {
      _masters = await DatabaseHelper().getAllMastersFull();
      unawaited(OnShiftController.instance.refresh());
      _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
      await _loadFeedSeen();
      _selectedMasterId = widget.order['master_id'];
      _selectedReceptionistId = (widget.order['receptionist_id'] as num?)?.toInt();
      // Мастер цеха, ошибочно записанный в master_id — не админ заказа.
      if (_selectedMasterId != null) {
        final cur = _masters.where((m) => m['id'] == _selectedMasterId).toList();
        if (cur.isEmpty || !_isAdminOnlyRole(cur.first['role']?.toString())) {
          _selectedMasterId = null;
          try {
            await DatabaseHelper().updateOrderMaster(widget.order['id'], null);
          } catch (e) {
            debugPrint('clear non-admin master_id: $e');
          }
        }
      }
      if (_selectedReceptionistId != null) {
        final cur = _masters.where((m) => m['id'] == _selectedReceptionistId).toList();
        if (cur.isEmpty || !_isReceptionistEligible(cur.first['role']?.toString())) {
          _selectedReceptionistId = null;
          try {
            await DatabaseHelper().updateOrderReceptionist(widget.order['id'], null);
          } catch (e) {
            debugPrint('clear bad receptionist_id: $e');
          }
        }
      }
      _clientCars = await DatabaseHelper().getClientCars(widget.order['client_id']);
      _selectedCarId = widget.order['car_id'];

      if (_selectedCarId != null) {
        Map<String, dynamic>? car;
        for (final c in _clientCars) {
          if (c['id'] == _selectedCarId) {
            car = c;
            break;
          }
        }
        if (car != null) _currentCarCategory = car['category'] ?? "1";
      }

      try {
        _services = await DatabaseHelper().getAllServices();
      } catch (e, st) {
        debugPrint('OrderDetails.getAllServices: $e\n$st');
        _services = [];
      }
      try {
        if (_canUseCash) {
          _cashRegisters = await DatabaseHelper().getCashRegisters();
        } else {
          _cashRegisters = [];
        }
      } catch (e, st) {
        debugPrint('OrderDetails.getCashRegisters: $e\n$st');
        _cashRegisters = [];
      }
      _handover = await DatabaseHelper().getOrderHandover(widget.order['id'] as int);
      try {
        if (_canUseCash) {
          _payments = await DatabaseHelper().getOrderPayments(widget.order['id'] as int);
          _syncRegisterForMethod(_paymentMethod, preferKeep: false);
        } else {
          _payments = [];
        }
      } catch (e, st) {
        debugPrint('OrderDetails.getOrderPayments: $e\n$st');
        _payments = [];
      }

      final dbItems = await DatabaseHelper().getOrderItems(widget.order['id']);
      _selectedWorks = dbItems.map((item) => Map<String, dynamic>.from(item)).toList();
      await _reloadPayroll(silent: true);
      try {
        _margin = await DatabaseHelper().getOrderMarginBreakdown(widget.order['id'] as int);
      } catch (e) {
        debugPrint('margin: $e');
      }
      // Автоцех только в UI при открытии; мастеру нельзя PATCH workshop → иначе 403
      // и ложный «Не удалось загрузить заказ», хотя карточка уже открыта.
      final persistAutoWorkshop = !_opsRestricted;
      for (var i = 0; i < _selectedWorks.length; i++) {
        final w = _selectedWorks[i];
        final current = (w['workshop'] as String?)?.trim() ?? "";
        if (current.isNotEmpty && WORKSHOPS.contains(current)) continue;
        final auto = workshopForService(name: w['name']?.toString());
        if (auto == null) continue;
        final wid = (w['id'] as num?)?.toInt() ?? 0;
        if (persistAutoWorkshop && wid > 0) {
          try {
            await DatabaseHelper().updateOrderItemSchedule(
              wid,
              w['start_time'] as String?,
              w['end_time'] as String?,
              auto,
            );
          } catch (e, st) {
            debugPrint('OrderDetails.autoWorkshop: $e\n$st');
          }
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
          await _recalcOrderTotal(writeDb: !_opsRestricted);
        }
      } else {
        await _recalcOrderTotal(writeDb: !_opsRestricted);
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
    VoidCallback? onTap,
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
            border: Border.all(color: hasValue ? color.withValues(alpha: 0.65) : AppColors.border),
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

  /// Компактное время на карточке работы: только иконка + цвет.
  Widget _timeIconChip({
    required String? value,
    required IconData icon,
    required String tooltip,
    required Color color,
    VoidCallback? onTap,
  }) {
    final hasValue = value != null && value.isNotEmpty;
    final enabled = onTap != null;
    return Tooltip(
      message: hasValue ? _formatDT(value, tooltip) : tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hasValue ? color.withValues(alpha: enabled ? 0.15 : 0.08) : AppColors.bg.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasValue
                    ? color.withValues(alpha: enabled ? 0.8 : 0.35)
                    : AppColors.border,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: hasValue
                  ? (enabled ? color : color.withValues(alpha: 0.45))
                  : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _masterActionChip({
    required String masters,
    required bool hasMasters,
    VoidCallback? onTap,
  }) {
    return MasterPill(
      label: hasMasters ? masters : (onTap != null ? '+ Исполнитель' : 'Исполнитель'),
      hasValue: hasMasters,
      onTap: onTap,
    );
  }

  Widget _workCommentToggle(Map<String, dynamic> w) {
    final id = (w['id'] as num?)?.toInt();
    if (id == null) return const SizedBox.shrink();
    final open = _expandedWorkComments.contains(id);
    final hasDraft = (w['comment']?.toString() ?? '').trim().isNotEmpty;
    return TapRegion(
      groupId: _workCommentTapGroup,
      child: Tooltip(
        message: open
            ? (_isWorkshopMode ? 'Скрыть комментарий' : 'Скрыть сообщение цеху')
            : (_isWorkshopMode ? 'Комментарий в ленту' : 'Сообщение цеху'),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                if (open) {
                  _expandedWorkComments.remove(id);
                } else {
                  _expandedWorkComments.add(id);
                }
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: open || hasDraft
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.bg.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: open || hasDraft
                      ? AppColors.primary.withValues(alpha: 0.75)
                      : AppColors.border,
                ),
              ),
              child: Icon(
                open ? Icons.chat_bubble : Icons.chat_bubble_outline,
                size: 17,
                color: open || hasDraft ? AppColors.primary : AppColors.textMuted,
              ),
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

  void _addWork(String name, double price, [String category = "", String? workshopOverride]) async {
    final workshop = workshopOverride ?? workshopForService(category: category, name: name);
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
      if (!mounted) return;
      _notifyIfWorkshopHasNoMasters(workshop);
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

  void _notifyIfWorkshopHasNoMasters(String? workshop) {
    final ws = (workshop ?? '').trim();
    if (ws.isEmpty || !WORKSHOPS.contains(ws)) return;
    final missing = workshopsWithoutMasters([ws], _masters);
    if (missing.isEmpty) return;
    showAppToast(context, missingMastersMessage(missing));
  }

  bool get _isWorkshopMode => widget.workshop != null && widget.workshop!.isNotEmpty;

  /// Мастер: урезанные операции даже при открытии с доски (без параметра workshop).
  bool get _masterRestricted => isStudioMaster(AuthController.instance.user);

  /// Цех из меню ИЛИ мастер по должности — без цен / кассы / выдачи / чужих цехов.
  bool get _opsRestricted => _isWorkshopMode || _masterRestricted;

  Set<String> get _editableWorkshops {
    if (_isWorkshopMode) {
      final ws = widget.workshop!.trim();
      return WORKSHOPS.contains(ws) ? {ws} : <String>{};
    }
    if (_masterRestricted) {
      return (AuthController.instance.user?.workshops ?? const [])
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && WORKSHOPS.contains(e))
          .toSet();
    }
    return {};
  }

  /// Можно ли править мастеров/время/галочку у этого цеха.
  bool _canEditWorkshopOps(String? workshop) {
    if (!_opsRestricted) return true;
    final ws = (workshop ?? '').trim();
    if (ws.isEmpty) return false;
    return _editableWorkshops.contains(ws);
  }

  bool get _canUseCash =>
      !_opsRestricted && userHasPermission(AuthController.instance.user, 'cash.read');

  bool get _canIssueOrder =>
      !_opsRestricted && userHasPermission(AuthController.instance.user, 'orders.issue');

  String _resolvedWorkWorkshop(Map<String, dynamic> w) {
    final raw = (w['workshop'] as String?)?.trim() ?? "";
    if (raw.isNotEmpty && WORKSHOPS.contains(raw)) return raw;
    return workshopForService(name: w['name']?.toString()) ?? "";
  }

  /// Цех, где сейчас стоит авто (= статус заказа, если это цех).
  String? get _carLocationWorkshop {
    final s = _status.trim();
    if (WORKSHOPS.contains(s)) return s;
    return null;
  }

  bool _workMatchesCarLocation(Map<String, dynamic> w) {
    final loc = _carLocationWorkshop;
    if (loc == null) return false;
    return _resolvedWorkWorkshop(w) == loc;
  }

  Color get _carLocationAccent =>
      kOrderStatusColors[_carLocationWorkshop ?? ''] ?? AppColors.primary;

  Future<void> _reloadPayroll({bool silent = false}) async {
    try {
      final rows = await DatabaseHelper().getOrderWorkshopPayroll(widget.order['id'] as int);
      _payrollByWorkshop.clear();
      for (final r in rows) {
        final ws = r['workshop']?.toString().trim() ?? '';
        if (ws.isEmpty) continue;
        final mid = (r['master_id'] as num?)?.toInt();
        final amount = (r['amount'] as num?)?.toDouble() ?? 0;
        if (mid == null || amount <= 0) continue;
        _payrollByWorkshop.putIfAbsent(ws, () => []).add({
          'master_id': mid,
          'amount': amount,
        });
      }
      if (!silent && mounted) setState(() {});
    } catch (e) {
      debugPrint('payroll load: $e');
    }
  }

  List<Map<String, dynamic>> _payrollLines(String workshop) =>
      List<Map<String, dynamic>>.from(_payrollByWorkshop[workshop] ?? const []);

  double _payrollTotal(String workshop) => _payrollLines(workshop).fold<double>(
        0,
        (s, l) => s + ((l['amount'] as num?)?.toDouble() ?? 0),
      );

  /// Мастера, уже назначенные на работы этого цеха (для префилла диалога).
  List<int> _masterIdsOnWorkshopWorks(String workshop) {
    final ids = <int>{};
    for (final w in _selectedWorks) {
      if (_resolvedWorkWorkshop(w) != workshop) continue;
      final raw = w['master_ids']?.toString() ?? '';
      for (final part in raw.split(',')) {
        final id = int.tryParse(part.trim());
        if (id != null) ids.add(id);
      }
    }
    return ids.toList();
  }

  bool _canEditPayroll(String workshop) {
    if (!_opsRestricted) return true;
    return _editableWorkshops.contains(workshop.trim());
  }

  String _payrollMasterName(int? masterId) {
    if (masterId == null) return '';
    for (final m in _masters) {
      if ((m['id'] as num?)?.toInt() == masterId) {
        return m['name']?.toString() ?? '';
      }
    }
    return '';
  }

  String _payrollButtonLabel(String workshop) {
    final lines = _payrollLines(workshop);
    final total = _payrollTotal(workshop);
    if (lines.isEmpty || total <= 0.001) return 'ЗП';
    if (lines.length == 1) {
      final name = _payrollMasterName((lines.first['master_id'] as num?)?.toInt());
      if (name.isNotEmpty) return 'ЗП · $name · ${total.toStringAsFixed(0)} ₽';
      return 'ЗП · ${total.toStringAsFixed(0)} ₽';
    }
    return 'ЗП · ${lines.length} маст. · ${total.toStringAsFixed(0)} ₽';
  }

  Future<void> _savePayrollLines(String workshop, List<Map<String, dynamic>> lines) async {
    if (!_canEditPayroll(workshop)) return;
    try {
      await DatabaseHelper().setOrderWorkshopPayroll(
        orderId: widget.order['id'] as int,
        workshop: workshop,
        lines: lines,
      );
      final cleaned = <Map<String, dynamic>>[];
      for (final l in lines) {
        final mid = (l['master_id'] as num?)?.toInt();
        final amt = (l['amount'] as num?)?.toDouble() ?? 0;
        if (mid == null || amt <= 0) continue;
        cleaned.add({'master_id': mid, 'amount': amt});
      }
      if (cleaned.isEmpty) {
        _payrollByWorkshop.remove(workshop);
      } else {
        _payrollByWorkshop[workshop] = cleaned;
      }
      if (mounted) {
        setState(() {});
        final total = cleaned.fold<double>(0, (s, l) => s + ((l['amount'] as num?)?.toDouble() ?? 0));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              cleaned.isEmpty
                  ? 'ЗП «$workshop» сброшена'
                  : 'ЗП «$workshop»: ${cleaned.length} маст. · ${total.toStringAsFixed(0)} ₽',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        var msg = e.toString();
        if (msg.contains('Not Found') || msg.contains('404')) {
          msg = 'Сервер ещё без ЗП (нужен API ≥ 0.16.18). Обновите API или попробуйте позже.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сохранить ЗП: $msg'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _openPayrollDialog(String workshop) async {
    final canEdit = _canEditPayroll(workshop);
    final mastersForWs = _masters.where((m) {
      final role = m['role']?.toString();
      return masterRoleFitsWorkshop(role, workshop);
    }).toList();
    final seed = _payrollLines(workshop);
    if (seed.isEmpty) {
      for (final id in _masterIdsOnWorkshopWorks(workshop)) {
        seed.add({'master_id': id, 'amount': 0.0});
      }
      if (seed.isEmpty && mastersForWs.isNotEmpty) {
        seed.add({
          'master_id': (mastersForWs.first['id'] as num).toInt(),
          'amount': 0.0,
        });
      }
    }

    final draft = seed
        .map(
          (l) => {
            'master_id': (l['master_id'] as num?)?.toInt(),
            'amount': (l['amount'] as num?)?.toDouble() ?? 0,
            'ctrl': TextEditingController(
              text: ((l['amount'] as num?)?.toDouble() ?? 0) > 0
                  ? ((l['amount'] as num).toDouble()).toStringAsFixed(0)
                  : '',
            ),
          },
        )
        .toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          double draftTotal() => draft.fold<double>(0, (s, l) {
                final t = (l['ctrl'] as TextEditingController).text.trim().replaceAll(',', '.');
                return s + (double.tryParse(t) ?? 0);
              });

          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(
              'ЗП · $workshop',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Несколько мастеров — отдельная сумма каждому. '
                      'В кассе «начислено» считается по каждому мастеру.',
                      style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, height: 1.35),
                    ),
                    if (canEdit) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            final mids = draft
                                .map((l) => l['master_id'] as int?)
                                .whereType<int>()
                                .toList();
                            final suggested = await DatabaseHelper().calculateWorkshopPayrollSuggestion(
                              orderId: widget.order['id'] as int,
                              workshop: workshop,
                              masterIds: mids.isEmpty ? null : mids,
                            );
                            if (suggested.isEmpty) {
                              if (ctx.mounted) {
                                showAppToast(ctx, 'Нет правил ЗП — добавьте в Студия или введите вручную');
                              }
                              return;
                            }
                            setLocal(() {
                              for (final c in draft) {
                                (c['ctrl'] as TextEditingController).dispose();
                              }
                              draft
                                ..clear()
                                ..addAll(
                                  suggested.map(
                                    (s) => {
                                      'master_id': s['master_id'],
                                      'amount': (s['amount'] as num?)?.toDouble() ?? 0,
                                      'ctrl': TextEditingController(
                                        text: ((s['amount'] as num?)?.toDouble() ?? 0)
                                            .toStringAsFixed(0),
                                      ),
                                    },
                                  ),
                                );
                            });
                          },
                          icon: const Icon(Icons.calculate_outlined, size: 18),
                          label: Text(
                            'Рассчитать',
                            style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    for (var i = 0; i < draft.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<int?>(
                              initialValue: (draft[i]['master_id'] as int?),
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Мастер',
                                isDense: true,
                              ),
                              dropdownColor: AppColors.surface2,
                              items: [
                                const DropdownMenuItem<int?>(value: null, child: Text('—')),
                                ...mastersForWs.map(
                                  (m) => DropdownMenuItem<int?>(
                                    value: (m['id'] as num).toInt(),
                                    child: Text(
                                      m['name']?.toString() ?? '',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: !canEdit
                                  ? null
                                  : (v) => setLocal(() => draft[i]['master_id'] = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: draft[i]['ctrl'] as TextEditingController,
                              enabled: canEdit,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'ЗП, ₽',
                                isDense: true,
                              ),
                              onChanged: (_) => setLocal(() {}),
                            ),
                          ),
                          if (canEdit)
                            IconButton(
                              tooltip: 'Убрать',
                              onPressed: () {
                                setLocal(() {
                                  (draft[i]['ctrl'] as TextEditingController).dispose();
                                  draft.removeAt(i);
                                });
                              },
                              icon: const Icon(Icons.close, color: AppColors.textMuted, size: 18),
                            ),
                        ],
                      ),
                    ],
                    if (canEdit) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          final used = draft
                              .map((l) => l['master_id'] as int?)
                              .whereType<int>()
                              .toSet();
                          Map<String, dynamic>? next;
                          for (final m in mastersForWs) {
                            final id = (m['id'] as num).toInt();
                            if (!used.contains(id)) {
                              next = m;
                              break;
                            }
                          }
                          next ??= mastersForWs.isEmpty ? null : mastersForWs.first;
                          setLocal(() {
                            draft.add({
                              'master_id': next == null ? null : (next['id'] as num).toInt(),
                              'amount': 0.0,
                              'ctrl': TextEditingController(),
                            });
                          });
                        },
                        icon: const Icon(Icons.person_add_alt_1, size: 18),
                        label: Text(
                          'Ещё мастер',
                          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      'Итого по цеху: ${draftTotal().toStringAsFixed(0)} ₽',
                      style: GoogleFonts.manrope(
                        color: AppColors.success,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена'),
              ),
              if (canEdit)
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Сохранить'),
                ),
            ],
          );
        },
      ),
    );

    final lines = <Map<String, dynamic>>[];
    for (final l in draft) {
      final ctrl = l['ctrl'] as TextEditingController;
      final mid = l['master_id'] as int?;
      final amt = double.tryParse(ctrl.text.trim().replaceAll(',', '.')) ?? 0;
      if (ok == true && mid != null && amt > 0) {
        lines.add({'master_id': mid, 'amount': amt});
      }
      ctrl.dispose();
    }
    if (ok == true) {
      await _savePayrollLines(workshop, lines);
    }
  }

  /// Пакет оклейки/тонировки уже держит ЗП цеха «Оклейка».
  bool _packageAnchorsPayroll(String workshop) {
    if (workshop != 'Оклейка') return false;
    return _wrapPackageHeader() != null || _tintPackageHeader() != null;
  }

  /// ЗП один раз на цех: на шапке пакета (wrap приоритетнее tint).
  bool _showPayrollOnPackageHeader(Map<String, dynamic> header) {
    final ws = _resolvedWorkWorkshop(header);
    if (ws.isEmpty) return false;
    if (isTintPackageHeader(header['name']?.toString())) {
      return _wrapPackageHeader() == null;
    }
    return true;
  }

  /// ЗП на первой самостоятельной работе цеха (если нет пакета-якоря).
  bool _showPayrollOnStandalone(
    Map<String, dynamic> w,
    List<Map<String, dynamic>> standalone,
  ) {
    final ws = _resolvedWorkWorkshop(w);
    if (ws.isEmpty) return false;
    if (_packageAnchorsPayroll(ws)) return false;
    for (final o in standalone) {
      if (_resolvedWorkWorkshop(o) != ws) continue;
      return (o['id'] as num?)?.toInt() == (w['id'] as num?)?.toInt();
    }
    return false;
  }

  /// Компактная кнопка ЗП внутри карточки работы/пакета.
  Widget _buildWorkshopPayrollEditor(String workshop, {bool embedded = false}) {
    final total = _payrollTotal(workshop);
    final label = _payrollButtonLabel(workshop);
    return Padding(
      padding: EdgeInsets.only(top: embedded ? 8 : 0, bottom: embedded ? 0 : 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => _openPayrollDialog(workshop),
          style: OutlinedButton.styleFrom(
            foregroundColor: total > 0.001 ? AppColors.success : AppColors.text,
            side: BorderSide(
              color: total > 0.001 ? AppColors.success.withValues(alpha: 0.55) : AppColors.border,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
          icon: Icon(
            Icons.payments_outlined,
            size: 16,
            color: total > 0.001 ? AppColors.success : AppColors.primary,
          ),
          label: Text(
            label,
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
        ),
      ),
    );
  }

  bool _canToggleWorkInWorkshop(Map<String, dynamic> w) {
    return _canEditWorkshopOps(_resolvedWorkWorkshop(w));
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
    if (_opsRestricted && !_canToggleWorkInWorkshop(w)) return;
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
    if (done) {
      final workshop = (ws ?? _resolvedWorkWorkshop(updated)).trim();
      final orderId = widget.order['id'] as int;
      final car = [
        widget.order['make_model']?.toString() ?? '',
        widget.order['plate']?.toString() ?? '',
      ].where((s) => s.trim().isNotEmpty).join(' · ');
      final client = widget.order['client_name']?.toString();
      await AppNotifications.postWorkDone(
        orderId: orderId,
        workName: w['name']?.toString() ?? '',
        workshop: workshop.isEmpty ? null : workshop,
        clientName: client,
        carLabel: car,
      );
      if (workshop.isNotEmpty) {
        await AppNotifications.maybePostWorkshopAllDone(
          orderId: orderId,
          workshop: workshop,
          clientName: client,
          carLabel: car,
        );
      }
    }
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

  static Map<String, Color> get _workshopColors => kOrderStatusColors;

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
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
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
                          : AppColors.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(10),
                        topRight: const Radius.circular(10),
                        bottomLeft: Radius.circular(fromClient ? 2 : 10),
                        bottomRight: Radius.circular(fromClient ? 10 : 2),
                      ),
                      border: Border.all(
                        color: fromClient ? AppColors.border : AppColors.primary.withValues(alpha: 0.4),
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
    String? pickedWorkshop;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Своя работа', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _customWorkName,
                  decoration: const InputDecoration(labelText: 'Название', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _customWorkPrice,
                  decoration: const InputDecoration(labelText: 'Цена', isDense: true),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: pickedWorkshop,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Цех', isDense: true),
                  items: [
                    for (final w in WORKSHOPS)
                      DropdownMenuItem(value: w, child: Text(w)),
                  ],
                  onChanged: (v) => setLocal(() => pickedWorkshop = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () {
                final name = _customWorkName.text.trim();
                if (name.isEmpty) return;
                var ws = pickedWorkshop?.trim();
                ws ??= workshopForService(name: name);
                if (ws == null || ws.isEmpty) {
                  showAppToast(context, 'Выберите цех');
                  return;
                }
                _addWork(name, double.tryParse(_customWorkPrice.text) ?? 0, '', ws);
                _customWorkName.clear();
                _customWorkPrice.clear();
                Navigator.pop(context);
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editWorkPrice(Map<String, dynamic> w) async {
    if (_opsRestricted) return;
    final id = (w['id'] as num?)?.toInt();
    if (id == null) return;
    final current = (w['price'] as num?)?.toDouble() ?? 0;
    final ctrl = TextEditingController(
      text: current % 1 == 0 ? current.toInt().toString() : current.toStringAsFixed(2),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text("Цена работы", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              w['name']?.toString() ?? '',
              style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: "Цена",
                isDense: true,
                suffixText: "₽",
              ),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Отмена")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Сохранить")),
        ],
      ),
    );
    final raw = ctrl.text.trim().replaceAll(',', '.');
    ctrl.dispose();
    if (ok != true || !mounted) return;
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed < 0) {
      showAppToast(context, "Некорректная цена");
      return;
    }
    if ((parsed - current).abs() < 0.001) return;
    try {
      await DatabaseHelper().updateOrderItemPrice(id, parsed);
      await DatabaseHelper().addOrderEvent(
        widget.order['id'],
        "Цена «${w['name']}»: ${_formatMoney(current)} → ${_formatMoney(parsed)} ₽",
      );
      _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
      await _reloadWorksFromDb();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Не удалось сохранить цену: $e")),
      );
    }
  }

  Future<void> _addPayment() async {
    if (!_canUseCash) {
      showAppToast(context, 'Нет доступа к кассе');
      return;
    }
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
    final adminName = _staffName(_selectedMasterId);
    final receptionistName = _staffName(_selectedReceptionistId);
    final orderForPdf = {
      ...widget.order,
      'status': _status,
      'price': _initialPrice,
      'paid_amount': _paidAmount,
      'master_name': adminName,
      'receptionist_name': receptionistName,
      'start_time': _orderStartTime ?? widget.order['start_time'],
      'end_time': _orderEndTime ?? widget.order['end_time'],
    };
    final payroll = <Map<String, dynamic>>[];
    _payrollByWorkshop.forEach((ws, lines) {
      for (final line in lines) {
        payroll.add({
          'workshop': ws,
          'master_id': line['master_id'],
          'amount': line['amount'],
        });
      }
    });
    if (!mounted) return;
    try {
      await WorkOrderPdf.showPreview(
        context,
        order: orderForPdf,
        items: _selectedWorks,
        masters: _masters,
        payroll: payroll,
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

  /// Подсказка / выбор цеха, если у услуги он пустой.
  Future<String?> _ensureWorkWorkshop(int index, Map<String, dynamic> w) async {
    var workshop = (w['workshop'] as String?)?.trim() ?? '';
    if (workshop.isEmpty || !WORKSHOPS.contains(workshop)) {
      final auto = workshopForService(name: w['name']?.toString());
      if (auto != null && WORKSHOPS.contains(auto)) {
        await _saveWorkSchedule(index, workshop: auto);
        return auto;
      }
    } else {
      return workshop;
    }

    final picked = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Выберите цех', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'У «${w['name']}» нет цеха. Укажите, куда отнести работу — потом можно назначить мастера или аутсорс.',
                style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.35),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final ws in WORKSHOPS)
                      ListTile(
                        title: Text(ws, style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                        onTap: () => Navigator.pop(context, ws),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        ],
      ),
    );
    if (picked == null || picked.isEmpty) return null;
    await _saveWorkSchedule(index, workshop: picked, logText: "Услуга «${w['name']}»: цех $picked");
    return picked;
  }

  /// Сохраняет цех и время одной услуги в базу + пишет в ленту.
  Future<void> _saveWorkSchedule(int index, {String? start, String? end, String? workshop, String? logText}) async {
    final w = _selectedWorks[index];
    final nextWs = (workshop ?? _resolvedWorkWorkshop(w)).trim();
    if (_opsRestricted && (nextWs.isEmpty || !_editableWorkshops.contains(nextWs))) {
      showAppToast(context, 'Мастер может править только свой цех');
      return;
    }
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
    final workshop = await _ensureWorkWorkshop(index, w);
    if (!mounted || workshop == null || workshop.isEmpty) return;
    w = _selectedWorks[index];
    if (_opsRestricted && !_editableWorkshops.contains(workshop)) {
      showAppToast(context, 'Мастер может назначать только свой цех');
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

    if (filtered.isEmpty && mounted) {
      showAppToast(context, missingMastersMessage([workshop]));
    }

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
                  "Исполнитель · $workshop",
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                ),
                content: SizedBox(
                  width: 280,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.handshake_outlined, color: AppColors.primary),
                        title: Text(
                          'Аутсорс…',
                          style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                        subtitle: Text(
                          'Подрядчик из базы или новый',
                          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11.5),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _assignOutsourceToWork(index, w);
                        },
                      ),
                      if ((w['outsourcer_id'] as num?) != null)
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _clearOutsourceFromWork(index, w);
                          },
                          child: Text('Снять аутсорс', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                        ),
                      const Divider(height: 16),
                      if (filtered.isEmpty)
                        Text(
                          "Нет мастеров с ролью для цеха «$workshop».\nДобавь их в разделе Сотрудники.",
                          style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.35),
                        )
                      else
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                          ),
                          child: ListView(
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
                                      updatedWork['outsourcer_id'] = null;
                                      updatedWork['outsourcer_name'] = null;
                                      _selectedWorks[index] = updatedWork;
                                    });
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ),
                    ],
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
    final oxId = (w['outsourcer_id'] as num?)?.toInt();
    final oxName = (w['outsourcer_name']?.toString() ?? '').trim();
    if (oxId != null || oxName.isNotEmpty) {
      return oxName.isNotEmpty ? 'Аутсорс · $oxName' : 'Аутсорс';
    }
    if (w['master_ids'] == null || (w['master_ids'] as String).isEmpty) return '';
    final ids = (w['master_ids'] as String)
        .split(',')
        .where((e) => e.trim().isNotEmpty)
        .map((e) => int.parse(e))
        .toList();
    return ids.map((id) {
      final found = _masters.where((m) => m['id'] == id).toList();
      return found.isNotEmpty ? found.first['name'] : '';
    }).where((n) => n.isNotEmpty).join(', ');
  }

  Future<void> _assignOutsourceToWork(int index, Map<String, dynamic> w) async {
    final itemId = (w['id'] as num?)?.toInt();
    if (itemId == null) return;
    final workshop = await _ensureWorkWorkshop(index, w);
    if (!mounted || workshop == null || workshop.isEmpty) return;
    w = _selectedWorks[index];
    final result = await showOutsourceAssignDialog(
      context,
      initialOutsourcerId: (w['outsourcer_id'] as num?)?.toInt(),
      initialCost: (w['outsource_cost'] as num?)?.toDouble(),
      initialSentAt: w['outsource_sent_at']?.toString(),
      initialDueAt: w['outsource_due_at']?.toString(),
      initialNote: w['outsource_note']?.toString(),
    );
    if (result == null || !mounted) return;
    await DatabaseHelper().setItemOutsource(
      orderItemId: itemId,
      outsourcerId: result.outsourcerId,
      cost: result.cost,
      sentAt: result.sentAt,
      dueAt: result.dueAt,
      note: result.note,
    );
    await DatabaseHelper().addOrderEvent(
      widget.order['id'],
      "Аутсорс на «${w['name']}»: ${result.outsourcerName}",
    );
    await _reloadWorksFromDb();
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    if (mounted) {
      setState(() {});
      showAppToast(context, 'Аутсорс: ${result.outsourcerName}');
    }
  }

  Future<void> _clearOutsourceFromWork(int index, Map<String, dynamic> w) async {
    final itemId = (w['id'] as num?)?.toInt();
    if (itemId == null) return;
    await DatabaseHelper().clearItemOutsource(itemId);
    await DatabaseHelper().addOrderEvent(
      widget.order['id'],
      "Снят аутсорс с «${w['name']}»",
    );
    await _reloadWorksFromDb();
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    if (mounted) setState(() {});
  }

  Widget _buildWorkCard(
    Map<String, dynamic> w, {
    bool hidePrice = false,
    bool showPayroll = false,
  }) {
    final index = _selectedWorks.indexWhere((e) => e['id'] == w['id']);
    if (index < 0) return const SizedBox.shrink();
    final String? currentWorkshop =
        (w['workshop'] != null && (w['workshop'] as String).isNotEmpty && WORKSHOPS.contains(w['workshop']))
            ? w['workshop'] as String
            : null;
    final masters = _masterNamesFor(w);
    final hasMasters = masters.isNotEmpty;
    final isDone = (w['is_done'] as num?)?.toInt() == 1;
    final itemId = (w['id'] as num?)?.toInt();
    final commentOpen = itemId != null && _expandedWorkComments.contains(itemId);
    final payrollWs = _resolvedWorkWorkshop(w);
    final canEditWork = _canEditWorkshopOps(payrollWs.isNotEmpty ? payrollWs : currentWorkshop);
    final atCar = _workMatchesCarLocation(w);
    final locAccent = _carLocationAccent;
    final hasLoc = _carLocationWorkshop != null;
    final baseColor = isDone ? AppColors.primary.withValues(alpha: 0.08) : AppColors.bg.withValues(alpha: 0.45);
    final baseBorder = isDone ? AppColors.primary.withValues(alpha: 0.35) : AppColors.borderSoft;

    return Opacity(
      opacity: hasLoc && !atCar ? 0.72 : 1,
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: atCar ? Color.alphaBlend(locAccent.withValues(alpha: 0.14), baseColor) : baseColor,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: atCar ? locAccent.withValues(alpha: 0.55) : baseBorder,
          width: atCar ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PremiumCheck(
                  value: isDone,
                  onChanged: (val) => _toggleWorkDone(index, val),
                ),
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
                        if (atCar) 'сейчас',
                        isDone ? "Выполнено" : "Не выполнено",
                      ].join(" · "),
                      style: GoogleFonts.manrope(
                        color: atCar
                            ? locAccent
                            : (isDone ? AppColors.primary : AppColors.textDim),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (!hidePrice)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Tooltip(
                    message: _opsRestricted ? "Цена" : "Изменить цену",
                    child: InkWell(
                      onTap: _opsRestricted ? null : () => _editWorkPrice(w),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "${_formatMoney((w['price'] as num?)?.toDouble() ?? 0)} ₽",
                              style: GoogleFonts.manrope(
                                color: AppColors.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (!_opsRestricted) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.edit_outlined, size: 14, color: AppColors.primary.withValues(alpha: 0.75)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (!_opsRestricted)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                  onPressed: () => _removeWork(w),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Flexible(
                child: _masterActionChip(
                  masters: masters,
                  hasMasters: hasMasters,
                  onTap: canEditWork ? () => _pickMastersForWork(index, w) : null,
                ),
              ),
              const SizedBox(width: 8),
              _timeIconChip(
                value: w['start_time']?.toString(),
                icon: Icons.play_arrow_rounded,
                tooltip: canEditWork ? "Начало" : "Только просмотр",
                color: AppColors.success,
                onTap: !canEditWork
                    ? null
                    : () async {
                  final ws = await _ensureWorkWorkshop(index, w);
                  if (!mounted || ws == null || ws.isEmpty) return;
                  if (!_canEditWorkshopOps(ws)) {
                    showAppToast(context, 'Мастер может править только свой цех');
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
              const SizedBox(width: 6),
              _timeIconChip(
                value: w['end_time']?.toString(),
                icon: Icons.stop_rounded,
                tooltip: canEditWork ? "Конец" : "Только просмотр",
                color: AppColors.danger,
                onTap: !canEditWork
                    ? null
                    : () async {
                  final ws = await _ensureWorkWorkshop(index, w);
                  if (!mounted || ws == null || ws.isEmpty) return;
                  if (!_canEditWorkshopOps(ws)) {
                    showAppToast(context, 'Мастер может править только свой цех');
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
              const SizedBox(width: 6),
              _workCommentToggle(w),
            ],
          ),
          if (commentOpen) _workCommentField(w),
          if (showPayroll && payrollWs.isNotEmpty && _canEditWorkshopOps(payrollWs))
            _buildWorkshopPayrollEditor(payrollWs, embedded: true),
        ],
      ),
    ),
    );
  }

  bool get _isMobileLayout => widget.fullscreen || AppResponsive.isMobile(context);

  static const _adminOnlyRoles = {'Администратор'};
  static const _receptionistRoles = {'Администратор', 'Приемщик'};

  bool _isAdminOnlyRole(String? role) => masterHasAnyRole(role, _adminOnlyRoles);
  bool _isReceptionistEligible(String? role) => masterHasAnyRole(role, _receptionistRoles);

  String _staffName(int? id) {
    if (id == null) return '';
    final found = _masters.where((m) => m['id'] == id).toList();
    return found.isEmpty ? '' : (found.first['name']?.toString() ?? '');
  }

  List<Map<String, dynamic>> get _adminsOnlyForPicker =>
      _masters.where((m) => _isAdminOnlyRole(m['role']?.toString())).toList();

  List<Map<String, dynamic>> get _receptionistsForPicker =>
      _masters.where((m) => _isReceptionistEligible(m['role']?.toString())).toList();

  Future<void> _pickAdministrator() async {
    final picked = await pickOrderStaff(
      context,
      title: 'Администратор',
      candidates: _adminsOnlyForPicker,
      currentId: _selectedMasterId,
      emptyHint: 'Нет сотрудников с ролью «Администратор».',
    );
    if (picked == null || !mounted) return;
    final id = picked.isEmpty ? null : picked.first;
    if (id == _selectedMasterId) return;
    setState(() => _selectedMasterId = id);
    await DatabaseHelper().updateOrderMaster(widget.order['id'], id);
    final name = id == null ? 'Не назначен' : _staffName(id);
    await DatabaseHelper().addOrderEvent(widget.order['id'], 'Назначен администратор: $name');
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    if (mounted) setState(() {});
  }

  Future<void> _pickReceptionist() async {
    final picked = await pickOrderStaff(
      context,
      title: 'Мастер-приёмщик',
      candidates: _receptionistsForPicker,
      currentId: _selectedReceptionistId,
      emptyHint: 'Нет сотрудников с ролью «Администратор» или «Приемщик».',
    );
    if (picked == null || !mounted) return;
    final id = picked.isEmpty ? null : picked.first;
    if (id == _selectedReceptionistId) return;
    setState(() => _selectedReceptionistId = id);
    await DatabaseHelper().updateOrderReceptionist(widget.order['id'], id);
    final name = id == null ? 'Не назначен' : _staffName(id);
    await DatabaseHelper().addOrderEvent(widget.order['id'], 'Назначен мастер-приёмщик: $name');
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    if (mounted) setState(() {});
  }

  Widget _staffRoleChip({
    required String label,
    required String name,
    required bool assigned,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: assigned ? AppColors.primary.withValues(alpha: 0.16) : AppColors.bg.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: assigned ? AppColors.primary.withValues(alpha: 0.75) : AppColors.primary.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              Icon(
                assigned ? Icons.badge_outlined : Icons.person_add_alt_1,
                size: 18,
                color: onTap == null ? AppColors.textDim : AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.manrope(
                        color: AppColors.textDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      assigned ? name : '+ Назначить',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _staffAssignRow() {
    final locked = _opsRestricted;
    return Row(
      children: [
        Expanded(
          child: _staffRoleChip(
            label: 'Администратор',
            name: _staffName(_selectedMasterId),
            assigned: _selectedMasterId != null,
            onTap: locked ? null : _pickAdministrator,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _staffRoleChip(
            label: 'Мастер-приёмщик',
            name: _staffName(_selectedReceptionistId),
            assigned: _selectedReceptionistId != null,
            onTap: locked ? null : _pickReceptionist,
          ),
        ),
      ],
    );
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
    await DatabaseHelper().addOrderEvent(widget.order['id'], 'Клиенту: уведомление о готовности');
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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: complete
            ? AppColors.success.withValues(alpha: 0.08)
            : AppColors.surface2.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border(
          left: BorderSide(color: accent.withValues(alpha: 0.8), width: 3),
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
                        color: accent.withValues(alpha: 0.12),
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
                            tooltip: 'Клиенту: готов к выдаче',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.chat_outlined, color: AppColors.success, size: 20),
                            onPressed: _notifyReadyWhatsApp,
                          )
                        : null,
                    value: _handoverValue(entry.key),
                    onChanged: _opsRestricted
                        ? null
                        : (value) => _setHandoverValue(entry.key, value ?? false),
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
      initialValue: statusValue,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Статус',
        isDense: true,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: EdgeInsets.fromLTRB(14, 16, 14, 12),
      ),
      dropdownColor: AppColors.surface,
      items: STATUSES
          .map((s) => DropdownMenuItem(
                value: s,
                child: Text(s, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: _opsRestricted
          ? null
          : (val) async {
              if (val == null || val == _status) return;
              if (val == 'Выдан') {
                if (!_canIssueOrder) {
                  showAppToast(context, 'Нет права на выдачу заказа');
                  return;
                }
                if (!await _ensureHandoverCompleteForIssue()) return;
              }
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

  /// Коммент под работой → лента.
  /// Из цеха: «От цеха …» (свой комментарий). Из карточки заказа: «Для цеха …».
  Future<bool> _saveWorkComment(int itemId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    final idx = _selectedWorks.indexWhere((w) => (w['id'] as num?)?.toInt() == itemId);
    final w = idx >= 0 ? _selectedWorks[idx] : null;
    final workName = w?['name']?.toString() ?? '';
    final body = workName.isEmpty ? trimmed : '$trimmed · $workName';

    final String eventText;
    if (_isWorkshopMode) {
      final fromWs = widget.workshop!.trim();
      eventText = "От цеха «$fromWs»: $body";
    } else {
      var ws = w?['workshop']?.toString() ?? '';
      if (ws.isEmpty) {
        ws = workshopForService(name: w?['name']?.toString()) ?? 'Цех';
      }
      eventText = "Для цеха «$ws»: $body";
    }

    // Только лента: в order_items.comment / заказ-наряд цеховой чат не пишем.
    try {
      await DatabaseHelper().addOrderEvent(widget.order['id'], eventText);
      _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
      if (mounted) {
        setState(() {
          _expandedWorkComments.remove(itemId);
        });
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
      child: TapRegion(
        groupId: _workCommentTapGroup,
        onTapOutside: (_) => _collapseWorkComments(),
        child: _WorkItemCommentField(
          key: ValueKey('work_for_shop_$id'),
          itemId: id,
          initial: w['comment']?.toString() ?? '',
          onSend: _saveWorkComment,
        ),
      ),
    );
  }

  Widget _carDropdown() {
    return DropdownButtonFormField<int>(
      initialValue: _safeCarDropdownValue,
      isExpanded: true,
      decoration: const InputDecoration(labelText: "Автомобиль", isDense: true),
      dropdownColor: AppColors.surface,
      items: _clientCars.map((car) {
        final vin = (car['vin'] ?? '').toString();
        final base = formatCarMakePlate(Map<String, dynamic>.from(car), sep: ' | ');
        final label = vin.isEmpty ? base : "$base | VIN $vin";
        return DropdownMenuItem<int>(
          value: car['id'] as int,
          child: Text(label, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: _opsRestricted
          ? null
          : (val) async {
        if (val == null) return;
        setState(() => _selectedCarId = val);
        await DatabaseHelper().reassignOrderCar(widget.order['id'], val);
        final selectedCar = _clientCars.firstWhere((c) => c['id'] == val);
        await DatabaseHelper().addOrderEvent(
          widget.order['id'],
          "Изменено авто на: ${formatCarMakePlate(Map<String, dynamic>.from(selectedCar), sep: ' | ')}",
        );
        _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
        if (mounted) setState(() {});
      },
    );
  }

// --- ORDER WINDOW SHELL (ui-order) ---
  IconData _serviceIconFor(Map<String, dynamic> w) {
    final n = (w['name']?.toString() ?? '').toLowerCase();
    final ws = _resolvedWorkWorkshop(w).toLowerCase();
    if (n.contains('мойк') || ws.contains('мойк')) return Icons.local_car_wash_outlined;
    if (n.contains('хим') || n.contains('интерьер') || ws.contains('интерьер')) {
      return Icons.airline_seat_recline_extra_outlined;
    }
    if (n.contains('полир') || n.contains('керам') || n.contains('покрыт') || n.contains('защит')) {
      return Icons.shield_outlined;
    }
    if (n.contains('оклей') || n.contains('плён') || n.contains('плен') || ws.contains('оклей')) {
      return Icons.layers_outlined;
    }
    if (n.contains('тонир') || n.contains('стекл')) return Icons.brightness_6_outlined;
    if (n.contains('фар') || n.contains('свет')) return Icons.highlight_outlined;
    if (n.contains('двиг') || n.contains('мотор')) return Icons.settings_outlined;
    if (n.contains('кузов') || n.contains('вмят') || n.contains('рихт')) return Icons.car_repair_outlined;
    if (n.contains('шин') || n.contains('диск')) return Icons.tire_repair_outlined;
    return Icons.handyman_outlined;
  }

  Future<void> _contactClient() async {
    final phone = widget.order['client_phone']?.toString() ?? '';
    if (phone.trim().isEmpty) {
      showAppToast(context, 'У клиента нет телефона');
      return;
    }
    final r = await DebtReminder.sharePickChannel(
      context,
      phone: phone,
      text: 'Здравствуйте! Пишем по заказу #${widget.order['id']}.',
      title: 'Написать клиенту',
    );
    if (!mounted || r == 'cancelled') return;
    if (r == 'no_phone') {
      showAppToast(context, 'Некорректный телефон');
      return;
    }
    final msg = DebtReminder.toastForResult(r);
    if (msg.isNotEmpty) showAppToast(context, msg);
  }

  Future<void> _confirmDeleteThisOrder() async {
    if (_opsRestricted) return;
    final id = (widget.order['id'] as num).toInt();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Удалить заказ?', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: Text(
          'Все данные заказа #$id будут безвозвратно удалены.',
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
    );
    if (ok != true) return;
    try {
      await DatabaseHelper().deleteOrder(id);
      if (!mounted) return;
      await _closeDialog();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Не удалось удалить: $e');
    }
  }

  Future<void> _openEditOrderDialog() async {
    if (_opsRestricted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            _orderModalRebuild = () {
              if (ctx.mounted) setModal(() {});
            };
            return Dialog(
              backgroundColor: AppColors.surface,
              insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: SizedBox(
                width: math.min(920, MediaQuery.sizeOf(ctx).width - 72),
                height: math.min(780, MediaQuery.sizeOf(ctx).height - 56),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Изменить заказ',
                              style: GoogleFonts.manrope(
                                color: AppColors.text,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close, color: AppColors.textDim),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: _buildWorksColumn(fill: true, showTitle: false),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    _orderModalRebuild = null;
    if (mounted) setState(() {});
  }

  Future<void> _openPaymentDialog() async {
    if (_opsRestricted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            _orderModalRebuild = () {
              if (ctx.mounted) setModal(() {});
            };
            return Dialog(
              backgroundColor: AppColors.surface,
              insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: SizedBox(
                width: math.min(980, MediaQuery.sizeOf(ctx).width - 72),
                height: math.min(720, MediaQuery.sizeOf(ctx).height - 56),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Оплата',
                              style: GoogleFonts.manrope(
                                color: AppColors.text,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close, color: AppColors.textDim),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildDesktopFooter(),
                            const SizedBox(height: 16),
                            _paymentsList(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    _orderModalRebuild = null;
    if (mounted) setState(() {});
  }

  Future<bool> _setOrderStatus(String val) async {
    if (_opsRestricted) return false;
    if (val == 'Выдан') {
      if (!_canIssueOrder) {
        showAppToast(context, 'Нет доступа к выдаче');
        return false;
      }
      final ready = await _ensureHandoverCompleteForIssue();
      if (!mounted || !ready) return false;
    }
    final ok = await tryUpdateOrderStatus(
      context,
      widget.order['id'] as int,
      val,
    );
    if (!mounted || !ok) return false;
    setState(() => _status = val);
    await DatabaseHelper().addOrderEvent(widget.order['id'], 'Статус изменен на: $val');
    _events = await DatabaseHelper().getOrderEvents(widget.order['id']);
    if (mounted) setState(() {});
    return true;
  }

  /// Статус «до выдачи»: последний цех из работ или «Принят в работу».
  String _statusBeforePrep() {
    final prepIdx = STATUSES.indexOf('Подготовка к выдаче');
    var best = 'Принят в работу';
    var bestIdx = STATUSES.indexOf(best);
    for (final w in _selectedWorks) {
      final ws = _resolvedWorkWorkshop(w);
      final i = STATUSES.indexOf(ws);
      if (i > bestIdx && (prepIdx < 0 || i < prepIdx)) {
        best = ws;
        bestIdx = i;
      }
    }
    return best;
  }

  /// Плашка мастеров: «Имя» или «Имя +N», полный список — в tooltip.
  String _mastersCompactLabel(String joinedShortNames) {
    final parts = joinedShortNames
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'Мастер';
    if (parts.length == 1) return parts.first;
    return '${parts.first} +${parts.length - 1}';
  }

  Widget _owPanel({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSoft.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _owSectionTitle(String title, {Widget? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.manrope(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  String _shortPersonName(String full) {
    final parts = full.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return full;
    if (parts.length == 1) return parts.first;
    final second = parts[1];
    final initial = second.isEmpty ? '' : '${second[0].toUpperCase()}.';
    return '${parts.first} $initial'.trim();
  }

  Widget _owRoundIconBtn({
    required IconData icon,
    required VoidCallback? onPressed,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Ink(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: onPressed == null ? 0.06 : 0.16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
            ),
            child: Icon(
              icon,
              size: 17,
              color: onPressed == null ? AppColors.textDim : AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _owStatusMenu({String? overrideLabel}) {
    final accent = kOrderStatusColors[_status] ?? AppColors.primary;
    return PopupMenuButton<String>(
      tooltip: 'Сменить статус',
      enabled: !_opsRestricted,
      color: AppColors.surface,
      onSelected: (v) => _setOrderStatus(v),
      itemBuilder: (_) => STATUSES
          .map(
            (s) => PopupMenuItem(
              value: s,
              child: Text(s, style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
            ),
          )
          .toList(),
      child: StatusPill(label: overrideLabel ?? _status, color: accent),
    );
  }

  Widget _buildOrderWindowHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 14, 12),
      child: Row(
        children: [
          Text(
            'Заказ',
            style: GoogleFonts.manrope(
              color: AppColors.text,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              '#${widget.order['id']}',
              style: GoogleFonts.manrope(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _owStatusMenu(),
          const Spacer(),
          if (!_opsRestricted) ...[
            IconButton(
              tooltip: 'Печать заказ-наряда',
              onPressed: _printWorkOrder,
              icon: const Icon(Icons.print_outlined, color: AppColors.textMuted),
            ),
            IconButton(
              tooltip: 'Удалить заказ',
              onPressed: _confirmDeleteThisOrder,
              icon: Icon(Icons.delete_outline_rounded, color: AppColors.danger.withValues(alpha: 0.9)),
            ),
          ],
          IconButton(
            tooltip: 'Дефекты',
            onPressed: () => _openDefectsSheet(),
            icon: const Icon(Icons.report_problem_outlined, color: AppColors.danger),
          ),
          _feedIconButton(),
          IconButton(
            tooltip: 'Закрыть',
            onPressed: _closeDialog,
            icon: const Icon(Icons.close, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderWindowLeft() {
    final make = widget.order['make_model']?.toString() ?? '';
    final plate = widget.order['plate']?.toString() ?? '';
    final client = widget.order['client_name']?.toString() ?? '';
    final phone = widget.order['client_phone']?.toString() ?? '';
    final works = _standaloneWorks();
    final wrapH = _wrapPackageHeader();
    final tintH = _tintPackageHeader();
    final serviceRows = <Map<String, dynamic>>[
      if (wrapH != null) wrapH,
      if (tintH != null) tintH,
      ...works,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _owPanel(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: CarBrandMark(make, size: 84),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          make.isEmpty ? 'Авто не указано' : make,
                          style: GoogleFonts.manrope(
                            color: AppColors.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (plate.isNotEmpty) PlateBadge(plate),
                        const SizedBox(height: 8),
                        Text(
                          '— · —',
                          style: GoogleFonts.manrope(
                            color: AppColors.textDim,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!_opsRestricted) ...[
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () async {
                              await showDialog<void>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: AppColors.surface,
                                  title: Text(
                                    'Автомобиль',
                                    style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                                  ),
                                  content: SizedBox(width: 360, child: _carDropdown()),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Готово'),
                                    ),
                                  ],
                                ),
                              );
                              if (mounted) setState(() {});
                            },
                            child: Text(
                              'Сменить авто',
                              style: GoogleFonts.manrope(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: AppColors.borderSoft.withValues(alpha: 0.9)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          client.isEmpty ? 'Без клиента' : client,
                          style: GoogleFonts.manrope(
                            color: AppColors.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            phone,
                            style: GoogleFonts.manrope(
                              color: AppColors.textMuted,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _owRoundIconBtn(
                    icon: Icons.chat_bubble_outline_rounded,
                    tooltip: 'Написать клиенту',
                    onPressed: phone.isEmpty ? null : _contactClient,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              KeyedSubtree(
                key: TourKeys.orderDetailsSchedule,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _owMetaRow(
                      label: 'Приём',
                      value: _orderStartTime == null || _orderStartTime!.isEmpty
                          ? 'Не задано'
                          : _formatDT(_orderStartTime, 'Приём'),
                      onEdit: _opsRestricted ? null : _setOrderStartTime,
                    ),
                    const SizedBox(height: 8),
                    _owMetaRow(
                      label: 'Выдача',
                      value: _orderEndTime == null || _orderEndTime!.isEmpty
                          ? 'Не задано'
                          : _formatDT(_orderEndTime, 'Выдача'),
                      onEdit: _opsRestricted ? null : _setOrderEndTime,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _owPanel(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _owSectionTitle('Услуги'),
                if (_carLocationWorkshop != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Сейчас: $_carLocationWorkshop',
                    style: GoogleFonts.manrope(
                      color: _carLocationAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      if (serviceRows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Text(
                              'Нет услуг',
                              style: GoogleFonts.manrope(color: AppColors.textDim),
                            ),
                          ),
                        )
                      else
                        ...List.generate(serviceRows.length, (i) {
                          final w = serviceRows[i];
                          final price = (w['price'] as num?)?.toDouble() ?? 0;
                          final done = (w['is_done'] as num?)?.toInt() == 1;
                          final ws = _resolvedWorkWorkshop(w);
                          final atCar = _workMatchesCarLocation(w);
                          final locAccent = _carLocationAccent;
                          final hasLoc = _carLocationWorkshop != null;
                          return Padding(
                            padding: EdgeInsets.only(bottom: i == serviceRows.length - 1 ? 0 : 10),
                            child: Opacity(
                              opacity: hasLoc && !atCar ? 0.62 : 1,
                              child: Container(
                                padding: atCar
                                    ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
                                    : EdgeInsets.zero,
                                decoration: atCar
                                    ? BoxDecoration(
                                        color: locAccent.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: locAccent.withValues(alpha: 0.45)),
                                      )
                                    : null,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            (atCar ? locAccent : AppColors.primary).withValues(alpha: 0.28),
                                            (atCar ? locAccent : AppColors.primaryDeep).withValues(alpha: 0.18),
                                          ],
                                        ),
                                        border: Border.all(
                                          color: (atCar ? locAccent : AppColors.primary).withValues(alpha: 0.35),
                                        ),
                                      ),
                                      child: Icon(
                                        _serviceIconFor(w),
                                        size: 17,
                                        color: atCar ? locAccent : AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            w['name']?.toString() ?? '',
                                            style: GoogleFonts.manrope(
                                              color: AppColors.text,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13.5,
                                              decoration: done ? TextDecoration.lineThrough : null,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            [
                                              if (ws.isNotEmpty) ws else (done ? 'Выполнено' : 'В заказе'),
                                              if (atCar) 'сейчас',
                                            ].join(' · '),
                                            style: GoogleFonts.manrope(
                                              color: atCar ? locAccent : AppColors.textDim,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '${_formatMoney(price)} ₽',
                                      style: GoogleFonts.manrope(
                                        color: AppColors.text,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      if (!_opsRestricted) ...[
                        const SizedBox(height: 10),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              _priceListOpen = true;
                              _openEditOrderDialog();
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border.withValues(alpha: 0.85)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.add_rounded, size: 18, color: AppColors.primary.withValues(alpha: 0.95)),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Добавить услугу',
                                    style: GoogleFonts.manrope(
                                      color: AppColors.textMuted,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Text(
                        'Итого',
                        style: GoogleFonts.manrope(
                          color: AppColors.textDim,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatMoney(_initialPrice)} ₽',
                        style: GoogleFonts.manrope(
                          color: AppColors.text,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _owMoneyLine('Предоплата', _paidAmount, muted: true),
                      const SizedBox(height: 2),
                      _owMoneyLine(
                        'Остаток к оплате',
                        _debt,
                        color: _debt > 0.01 ? AppColors.danger : AppColors.success,
                      ),
                      if (!_opsRestricted) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String?>(
                          initialValue: _leadSource.isEmpty ? null : _leadSource,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Источник заказа', isDense: true),
                          dropdownColor: AppColors.surface2,
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('Не указан')),
                            ...OrderLeadSources.all.map(
                              (s) => DropdownMenuItem<String?>(value: s, child: Text(s)),
                            ),
                          ],
                          onChanged: (v) async {
                            final next = v ?? OrderLeadSources.unset;
                            setState(() => _leadSource = next);
                            await DatabaseHelper().updateOrderLeadSource(widget.order['id'] as int, next);
                            widget.order['lead_source'] = next;
                          },
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Маржа',
                          style: GoogleFonts.manrope(
                            color: AppColors.textDim,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatMoney((_margin['margin'] as num?)?.toDouble() ?? 0)} ₽'
                          '  ·  ${((_margin['margin_pct'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}%',
                          style: GoogleFonts.manrope(
                            color: AppColors.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _owMoneyLine('Материалы', (_margin['materials'] as num?)?.toDouble() ?? 0, muted: true),
                        _owMoneyLine('ЗП цехов', (_margin['payroll'] as num?)?.toDouble() ?? 0, muted: true),
                        if (((_margin['outsource'] as num?)?.toDouble() ?? 0) > 0.01)
                          _owMoneyLine('Аутсорс', (_margin['outsource'] as num?)?.toDouble() ?? 0, muted: true),
                        if (_depositRequired > 0.01) ...[
                          const SizedBox(height: 4),
                          _owMoneyLine('Депозит (нужен)', _depositRequired, muted: true),
                        ],
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _editDepositRequired,
                            child: Text(
                              _depositRequired > 0.01
                                  ? 'Депозит: ${_formatMoney(_depositRequired)} ₽'
                                  : 'Задать депозит',
                              style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _addWarrantyFromOrder,
                            child: Text(
                              'Гарантия на авто',
                              style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        _owClientNotifyMenu(),
                        if (_depositRequired > 0.01 && _paidAmount + 0.01 < _depositRequired)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Депозит не закрыт: нужно ${_formatMoney(_depositRequired)} ₽, внесено ${_formatMoney(_paidAmount)} ₽',
                              style: GoogleFonts.manrope(
                                color: AppColors.danger,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _openEditOrderDialog,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.text,
                                  side: BorderSide(color: AppColors.border.withValues(alpha: 0.95)),
                                  backgroundColor: AppColors.bg.withValues(alpha: 0.55),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text(
                                  'Изменить',
                                  style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 13),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _openPaymentDialog,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: AppColors.onPrimary,
                                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Оплата',
                                      style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 13),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _owClientNotifyMenu() {
    final orderPayload = <String, dynamic>{
      ...widget.order,
      'price': _initialPrice,
      'paid_amount': _paidAmount,
    };
    return PopupMenuButton<String>(
      tooltip: 'Сообщение клиенту',
      color: AppColors.surface,
      offset: const Offset(0, 8),
      onSelected: (v) {
        if (v == 'tg_bind') {
          final cid = (widget.order['client_id'] as num?)?.toInt();
          if (cid == null) {
            showAppToast(context, 'Нет клиента');
            return;
          }
          ClientNotify.copyBindLink(context, clientId: cid);
          return;
        }
        ClientNotify.sendForOrder(context, order: orderPayload, kind: v);
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'booking',
          child: Text('Запись', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
        ),
        PopupMenuItem(
          value: 'tomorrow',
          child: Text('Завтра', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
        ),
        PopupMenuItem(
          value: 'ready',
          child: Text('Готов к выдаче', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
        ),
        if (_debt > 0.01)
          PopupMenuItem(
            value: 'debt',
            child: Text('Долг', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'tg_bind',
          child: Text('Привязать Telegram', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
        ),
      ],
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.9)),
          color: AppColors.bg.withValues(alpha: 0.4),
        ),
        child: Row(
          children: [
            Icon(Icons.campaign_outlined, size: 18, color: AppColors.primary.withValues(alpha: 0.95)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Клиенту',
                style: GoogleFonts.manrope(
                  color: AppColors.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded, size: 20, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Future<void> _editDepositRequired() async {
    final ctrl = TextEditingController(
      text: _depositRequired == 0 ? '' : _formatMoney(_depositRequired),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Депозит', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Нужная предоплата, ₽',
            helperText: '0 = не требуется',
            isDense: true,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(ctrl.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
    await DatabaseHelper().updateOrderDepositRequired(widget.order['id'] as int, v);
    if (!mounted) return;
    setState(() {
      _depositRequired = v < 0 ? 0 : v;
      widget.order['deposit_required'] = _depositRequired;
    });
  }

  Future<void> _addWarrantyFromOrder() async {
    final carId = (_selectedCarId ?? widget.order['car_id'] as num?)?.toInt();
    if (carId == null) {
      showAppToast(context, 'Сначала выберите авто');
      return;
    }
    var kind = 'Керамика';
    final titleCtrl = TextEditingController();
    final monthsCtrl = TextEditingController(text: '12');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Гарантия', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Тип', isDense: true),
                dropdownColor: AppColors.surface2,
                items: const [
                  DropdownMenuItem(value: 'Керамика', child: Text('Керамика')),
                  DropdownMenuItem(value: 'ППФ', child: Text('ППФ')),
                  DropdownMenuItem(value: 'Тонировка', child: Text('Тонировка')),
                  DropdownMenuItem(value: 'Прочее', child: Text('Прочее')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setLocal(() => kind = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Название / зона', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: monthsCtrl,
                decoration: const InputDecoration(labelText: 'Срок, мес.', isDense: true),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Создать')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final months = int.tryParse(monthsCtrl.text.trim()) ?? 12;
    await DatabaseHelper().addCarWarranty(
      carId: carId,
      orderId: widget.order['id'] as int,
      kind: kind,
      title: titleCtrl.text,
      startedAt: DateTime.now(),
      months: months,
    );
    if (!mounted) return;
    showAppToast(context, 'Гарантия сохранена');
  }

  Widget _owMoneyLine(String label, double amount, {Color? color, bool muted = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.manrope(
              color: AppColors.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          '${_formatMoney(amount)} ₽',
          style: GoogleFonts.manrope(
            color: color ?? (muted ? AppColors.textMuted : AppColors.text),
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _owMetaRow({
    required String label,
    required String value,
    VoidCallback? onEdit,
  }) {
    final body = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.manrope(
              color: AppColors.textDim,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.manrope(
              color: AppColors.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    if (onEdit == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: body,
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _worksGroupedByWorkshop() {
    final map = <String, List<Map<String, dynamic>>>{};
    void add(Map<String, dynamic> w) {
      final ws = _resolvedWorkWorkshop(w);
      final key = ws.isEmpty ? 'Без цеха' : ws;
      map.putIfAbsent(key, () => []).add(w);
    }

    // Пакеты — только шапка (зоны рисуем внутри раскрывающегося блока).
    final wrapH = _wrapPackageHeader();
    if (wrapH != null) add(wrapH);
    final tintH = _tintPackageHeader();
    if (tintH != null) add(tintH);
    for (final w in _standaloneWorks()) {
      add(w);
    }
    return map;
  }

  String _zoneDisplayName(String? raw) {
    final n = (raw ?? '').trim();
    if (n.isEmpty) return '';
    final sep = n.indexOf('·');
    if (sep >= 0 && sep + 1 < n.length) return n.substring(sep + 1).trim();
    // Устаревшие «Оклейка капота»
    for (final prefix in ['Оклейка ', 'Тонировка ']) {
      if (n.startsWith(prefix) && n != prefix.trim()) {
        return n.substring(prefix.length).trim();
      }
    }
    return n;
  }

  Widget _buildShopPackageBlock(Map<String, dynamic> header) {
    final headerId = (header['id'] as num?)?.toInt();
    if (headerId == null) return const SizedBox.shrink();
    final children = _wrapPackageChildren(headerId);
    final packageName = header['name']?.toString() ?? 'Пакет';
    final expanded = !_collapsedShopPackages.contains(headerId);
    final doneCount = children.where((c) => (c['is_done'] as num?)?.toInt() == 1).length;
    final allDone = children.isNotEmpty && doneCount == children.length;
    final someDone = doneCount > 0 && !allDone;
    final masters = _masterNamesFor(header);
    final shortMasters = masters.isEmpty
        ? ''
        : masters
            .split(',')
            .map((e) => _shortPersonName(e.trim()))
            .where((e) => e.isNotEmpty)
            .toSet() // убрать дубли вроде «Орлов И., Орлов И.»
            .join(', ');
    final hasMasters = shortMasters.isNotEmpty;
    final commentOpen = _expandedWorkComments.contains(headerId);
    final packageWs = _resolvedWorkWorkshop(header);
    final canEditPkg = _canEditWorkshopOps(packageWs.isNotEmpty ? packageWs : 'Оклейка');
    final zonesHint = children.isEmpty
        ? 'Без зон'
        : (children.length == 1
            ? _zoneDisplayName(children.first['name']?.toString())
            : '${children.length} зоны · ${children.map((c) => _zoneDisplayName(c['name']?.toString())).where((e) => e.isNotEmpty).take(3).join(', ')}${children.length > 3 ? '…' : ''}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              // Тристейт: все / частично / ничего
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  tristate: true,
                  value: children.isEmpty ? ((header['is_done'] as num?)?.toInt() == 1) : (allDone ? true : (someDone ? null : false)),
                  side: BorderSide(color: canEditPkg ? AppColors.primary : AppColors.textDim),
                  activeColor: AppColors.primary,
                  onChanged: !canEditPkg
                      ? null
                      : children.isEmpty
                          ? (v) {
                              final idx = _selectedWorks.indexWhere((e) => e['id'] == headerId);
                              if (idx >= 0) _toggleWorkDone(idx, v == true);
                            }
                          : (_) => _toggleWrapPackageDone(header, children, !allDone),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: children.isEmpty
                      ? null
                      : () => setState(() {
                            if (_collapsedShopPackages.contains(headerId)) {
                              _collapsedShopPackages.remove(headerId);
                            } else {
                              _collapsedShopPackages.add(headerId);
                            }
                          }),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          packageName,
                          style: GoogleFonts.manrope(
                            color: allDone ? AppColors.textMuted : AppColors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            decoration: allDone ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        Text(
                          children.isEmpty
                              ? zonesHint
                              : (allDone
                                  ? 'Выполнено · $zonesHint'
                                  : (someDone ? '$doneCount из ${children.length} · $zonesHint' : zonesHint)),
                          style: GoogleFonts.manrope(
                            color: AppColors.textDim,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: hasMasters ? masters : 'Назначить мастера',
                child: MasterPill(
                  label: hasMasters ? _mastersCompactLabel(shortMasters) : 'Мастер',
                  hasValue: hasMasters,
                  onTap: canEditPkg ? () => _pickMastersForWrapPackage(header) : null,
                ),
              ),
              IconButton(
                tooltip: 'Комментарий',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 17,
                  color: commentOpen ? AppColors.primary : AppColors.textDim,
                ),
                onPressed: () {
                  setState(() {
                    if (_expandedWorkComments.contains(headerId)) {
                      _expandedWorkComments.remove(headerId);
                    } else {
                      _expandedWorkComments
                        ..clear()
                        ..add(headerId);
                    }
                  });
                },
              ),
              if (children.isNotEmpty)
                IconButton(
                  tooltip: expanded ? 'Свернуть' : 'Зоны',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                  icon: Icon(
                    expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 22,
                    color: AppColors.textMuted,
                  ),
                  onPressed: () => setState(() {
                    if (expanded) {
                      _collapsedShopPackages.add(headerId);
                    } else {
                      _collapsedShopPackages.remove(headerId);
                    }
                  }),
                ),
            ],
          ),
        ),
        if (commentOpen) _workCommentField(header),
        if (expanded && children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 18, bottom: 4),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: AppColors.primary.withValues(alpha: 0.35), width: 2),
                ),
              ),
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                children: [
                  for (final c in children) _buildShopZoneRow(c, canEdit: canEditPkg),
                ],
              ),
            ),
          ),
        // Расход плёнки — только у пакета оклейки, сразу под зонами.
        if (isWrapPackageHeader(packageName) &&
            (!_opsRestricted || _editableWorkshops.contains('Оклейка'))) ...[
          const SizedBox(height: 8),
          OrderWrapFilmsPanel(
            orderId: widget.order['id'] as int,
            collapsible: true,
            initiallyExpanded: false,
            filmCategories: _orderFilmCategories(),
          ),
        ],
      ],
    );
  }

  Widget _buildShopZoneRow(Map<String, dynamic> w, {required bool canEdit}) {
    final index = _selectedWorks.indexWhere((e) => e['id'] == w['id']);
    if (index < 0) return const SizedBox.shrink();
    final isDone = (w['is_done'] as num?)?.toInt() == 1;
    final label = _zoneDisplayName(w['name']?.toString());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          PremiumCheck(
            value: isDone,
            onChanged: canEdit ? (val) => _toggleWorkDone(index, val) : null,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label.isEmpty ? '${w['name']}' : label,
              style: GoogleFonts.manrope(
                color: isDone ? AppColors.textMuted : AppColors.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                decoration: isDone ? TextDecoration.lineThrough : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopChecklistRow(Map<String, dynamic> w) {
    if (isZonePackageHeader(w['name']?.toString())) {
      final parent = w['parent_id'];
      final isRoot = parent == null || parent == '' || ((parent is num) && parent == 0);
      if (isRoot) return _buildShopPackageBlock(w);
    }
    final index = _selectedWorks.indexWhere((e) => e['id'] == w['id']);
    if (index < 0) return const SizedBox.shrink();
    final masters = _masterNamesFor(w);
    final shortMasters = masters.isEmpty
        ? ''
        : masters
            .split(',')
            .map((e) => _shortPersonName(e.trim()))
            .where((e) => e.isNotEmpty)
            .toSet()
            .join(', ');
    final hasMasters = shortMasters.isNotEmpty;
    final isDone = (w['is_done'] as num?)?.toInt() == 1;
    final itemId = (w['id'] as num?)?.toInt();
    final commentOpen = itemId != null && _expandedWorkComments.contains(itemId);
    final payrollWs = _resolvedWorkWorkshop(w);
    final canEditWork = _canEditWorkshopOps(payrollWs.isNotEmpty ? payrollWs : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              PremiumCheck(
                value: isDone,
                onChanged: canEditWork ? (val) => _toggleWorkDone(index, val) : null,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${w['name']}',
                  style: GoogleFonts.manrope(
                    color: isDone ? AppColors.textMuted : AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                    decorationColor: AppColors.textDim,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Tooltip(
                message: hasMasters ? masters : 'Назначить мастера',
                child: MasterPill(
                  label: hasMasters ? _mastersCompactLabel(shortMasters) : 'Мастер',
                  hasValue: hasMasters,
                  onTap: canEditWork ? () => _pickMastersForWork(index, w) : null,
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                tooltip: 'Комментарий',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 17,
                  color: commentOpen ? AppColors.primary : AppColors.textDim,
                ),
                onPressed: itemId == null
                    ? null
                    : () {
                        setState(() {
                          if (_expandedWorkComments.contains(itemId)) {
                            _expandedWorkComments.remove(itemId);
                          } else {
                            _expandedWorkComments
                              ..clear()
                              ..add(itemId);
                          }
                        });
                      },
              ),
            ],
          ),
        ),
        if (commentOpen) _workCommentField(w),
      ],
    );
  }

  Widget _buildFinalStageBlock({required int stageNumber}) {
    final statusIdx = STATUSES.indexOf(_status);
    final prepIdx = STATUSES.indexOf('Подготовка к выдаче');
    final prepDone = statusIdx >= 0 && prepIdx >= 0 && statusIdx >= prepIdx;
    final issueDone = _status == 'Выдан';
    final done = _handoverDoneCount;
    final total = _handoverItems.length;
    final complete = _handoverComplete;
    final accent = complete ? AppColors.success : AppColors.primary;

    Widget stageRow({
      required String title,
      String? subtitle,
      required bool value,
      required Future<void> Function(bool) onChanged,
      Widget? trailing,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            PremiumCheck(
              value: value,
              enabled: !_opsRestricted,
              onChanged: _opsRestricted
                  ? null
                  : (v) async {
                      await onChanged(v);
                    },
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      color: AppColors.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: GoogleFonts.manrope(
                        color: AppColors.textDim,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );
    }

    Widget checklistRow(MapEntry<String, String> entry) {
      final key = entry.key;
      final checked = _handoverValue(key);
      final isNotify = key == 'handover_notified';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            PremiumCheck(
              value: checked,
              enabled: !_opsRestricted,
              onChanged: _opsRestricted
                  ? null
                  : (v) => _setHandoverValue(key, v),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                entry.value,
                style: GoogleFonts.manrope(
                  color: checked ? AppColors.textMuted : AppColors.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  decoration: checked ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (isNotify)
              IconButton(
                tooltip: 'Клиенту: готов к выдаче',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(
                  Icons.chat_outlined,
                  size: 18,
                  color: checked ? AppColors.success : AppColors.primary,
                ),
                onPressed: _opsRestricted ? null : _notifyReadyWhatsApp,
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$stageNumber. Финал',
                style: GoogleFonts.manrope(
                  color: AppColors.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: Text(
                complete ? 'Готово' : '$done/$total',
                style: GoogleFonts.manrope(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        stageRow(
          title: 'Подготовка к выдаче',
          subtitle: prepDone ? 'Статус заказа' : 'Перевести заказ в подготовку',
          value: prepDone,
          onChanged: (v) async {
            if (v) {
              await _setOrderStatus('Подготовка к выдаче');
              if (mounted) setState(() => _handoverExpanded = true);
            } else {
              if (_status == 'Выдан') {
                await _setHandoverValue('handover_keys', false);
              }
              await _setOrderStatus(_statusBeforePrep());
            }
          },
        ),
        // Карточка чек-листа
        Container(
          margin: const EdgeInsets.only(top: 4, bottom: 4),
          decoration: BoxDecoration(
            color: AppColors.bg.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: complete
                  ? AppColors.success.withValues(alpha: 0.35)
                  : AppColors.borderSoft,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _handoverExpanded = !_handoverExpanded),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Row(
                      children: [
                        Icon(
                          complete ? Icons.verified_outlined : Icons.checklist_rtl_rounded,
                          size: 18,
                          color: accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Чек-лист выдачи',
                            style: GoogleFonts.manrope(
                              color: AppColors.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          complete ? 'Готово к выдаче' : 'Отмечено $done из $total',
                          style: GoogleFonts.manrope(
                            color: complete ? AppColors.success : AppColors.textDim,
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                          ),
                        ),
                        Icon(
                          _handoverExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_handoverExpanded) ...[
                Divider(height: 1, color: AppColors.borderSoft.withValues(alpha: 0.9)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                  child: Column(
                    children: [
                      for (final e in _handoverItems.entries) checklistRow(e),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        stageRow(
          title: 'Выдача автомобиля',
          subtitle: complete
              ? 'Можно перевести в «Выдан»'
              : 'Сначала закройте чек-лист ($done/$total)',
          value: issueDone,
          onChanged: (v) async {
            if (v) {
              await _setHandoverValue('handover_keys', true);
              final ok = await _setOrderStatus('Выдан');
              if (!ok) {
                await _setHandoverValue('handover_keys', false);
                if (mounted) setState(() => _handoverExpanded = true);
              }
            } else {
              await _setHandoverValue('handover_keys', false);
              if (_status == 'Выдан') {
                await _setOrderStatus('Подготовка к выдаче');
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildOrderWindowWorkshop() {
    final grouped = _worksGroupedByWorkshop();
    final entries = grouped.entries.toList();
    final total = _selectedWorks.length;
    final done = _selectedWorks.where((w) => (w['is_done'] as num?)?.toInt() == 1).length;
    final inProgress = total - done;
    final waiting = grouped.values.where((list) => list.every((w) => (w['is_done'] as num?)?.toInt() != 1)).length;
    final progress = total == 0 ? 0.0 : done / total;
    final stages = entries.length + 1;

    Widget stat(String label, String value, {Color? color}) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.bg.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.manrope(
                  color: color ?? AppColors.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.manrope(
                  color: AppColors.textDim,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _owPanel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Цех',
                style: GoogleFonts.manrope(
                  color: AppColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 10),
              _owStatusMenu(overrideLabel: _status == 'Предварительная запись' ? 'Запись' : null),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              stat('Этапов', '$stages'),
              const SizedBox(width: 8),
              stat('Выполнено', '$done', color: AppColors.success),
              const SizedBox(width: 8),
              stat('В работе', '$inProgress', color: AppColors.primary),
              const SizedBox(width: 8),
              stat('Ожидают', '$waiting'),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.bg.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderSoft),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Прогресс ${(progress * 100).round()}%',
                        style: GoogleFonts.manrope(
                          color: AppColors.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 7,
                          backgroundColor: AppColors.borderSoft,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 4 : 14, bottom: 6),
                    child: Text(
                      '${i + 1}. ${entries[i].key}',
                      style: GoogleFonts.manrope(
                        color: AppColors.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  for (final w in entries[i].value) _buildShopChecklistRow(w),
                ],
                const SizedBox(height: 14),
                _buildFinalStageBlock(stageNumber: entries.length + 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _mastersOnShiftRail() {
    return OnShiftController.instance.onShiftMasters;
  }

  Widget _buildOrderWindowRail() {
    return ListenableBuilder(
      listenable: OnShiftController.instance,
      builder: (context, _) {
        final masters = _mastersOnShiftRail();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _owPanel(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Мастера на смене',
                    style: GoogleFonts.manrope(
                      color: AppColors.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (masters.isEmpty)
                    Text(
                      'Никого на смене',
                      style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                    )
                  else
                    ...masters.take(8).map((m) {
                      final name = m['name']?.toString() ?? '';
                      final role = m['role']?.toString() ?? '';
                      final shortRole = role.split(',').first.trim();
                      final initials = name.trim().isEmpty
                          ? '?'
                          : name.trim().split(RegExp(r'\s+')).take(2).map((e) => e[0]).join().toUpperCase();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                                  child: Text(
                                    initials,
                                    style: GoogleFonts.manrope(
                                      color: AppColors.primary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: -1,
                                  bottom: -1,
                                  child: Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      color: AppColors.success,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppColors.surface2, width: 1.5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _shortPersonName(name),
                                    style: GoogleFonts.manrope(
                                      color: AppColors.text,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (shortRole.isNotEmpty)
                                    Text(
                                      shortRole,
                                      style: GoogleFonts.manrope(
                                        color: AppColors.textDim,
                                        fontSize: 10.5,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  if (!_opsRestricted)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _pickAdministrator,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          '+ Админ заказа',
                          style: GoogleFonts.manrope(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _owPanel(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
              Text(
                'Файлы',
                style: GoogleFonts.manrope(
                  color: AppColors.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: List.generate(2, (row) {
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: row == 0 ? 6 : 0),
                      child: AspectRatio(
                        aspectRatio: 1.15,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.bg.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.borderSoft),
                          ),
                          child: Icon(
                            Icons.image_outlined,
                            size: 18,
                            color: AppColors.textDim.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _openDefectsSheet(initialSource: ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined, size: 15),
                      label: Text(
                        'Камера',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openDefectsSheet(initialSource: ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined, size: 15),
                      label: Text(
                        'Галерея',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.text,
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.55)),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOrderWindowBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: KeyedSubtree(
              key: TourKeys.orderDetailsWorks,
              child: PulseAnchor(
                active: isPulseActive('od_works') || isPulseActive('od_masters'),
                child: _buildOrderWindowLeft(),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 6,
            child: _buildOrderWindowWorkshop(),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 220,
            child: KeyedSubtree(
              key: TourKeys.orderDetailsNotes,
              child: _buildOrderWindowRail(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorksColumn({bool fill = true, bool showTitle = true}) {
    // Кнопки прайса и список работ — в одном скролле (ЗП внутри карточек работ).
    final list = _buildWorksListView(
      shrinkWrap: !fill,
      leading: [
        if (!_opsRestricted) ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _priceListOpen = !_priceListOpen),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    side: BorderSide(
                      color: _priceListOpen ? AppColors.primary : AppColors.border,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                  ),
                  icon: Icon(
                    _priceListOpen ? Icons.expand_less : Icons.menu_book_outlined,
                    size: 18,
                    color: _priceListOpen ? AppColors.primary : AppColors.textMuted,
                  ),
                  label: Text(
                    "Из прайса",
                    style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addCustomWork,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                  ),
                  icon: const Icon(Icons.add, size: 18, color: AppColors.textMuted),
                  label: Text(
                    "Своя работа",
                    style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          if (_priceListOpen) ...[
            const SizedBox(height: 8),
            Container(
              height: 280,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.bg.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppTheme.radius),
                border: Border.all(color: AppColors.border),
              ),
              child: ServiceCategoryBrowser(
                services: _services,
                carCategory: _currentCarCategory,
                onAdd: _addWork,
                onConfigurePackage: _openZonePackageFromCategory,
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ],
    );
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
            if (_carLocationWorkshop != null) ...[
              const SizedBox(height: 4),
              Text(
                'Сейчас авто: ${_carLocationWorkshop}',
                style: GoogleFonts.manrope(
                  color: _carLocationAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
          ],
          WorksProgressBar.fromItems(_selectedWorks),
          const SizedBox(height: 12),
          if (fill) Expanded(child: list) else list,
        ],
      ),
    );
  }

  Map<String, dynamic>? _zonePackageHeader(String headerName) {
    for (final w in _selectedWorks) {
      if ((w['name']?.toString() ?? '').trim() != headerName) continue;
      final parent = w['parent_id'];
      final isRoot = parent == null || parent == '' || ((parent is num) && parent == 0);
      if (isRoot) return w;
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
      if (mounted) setState(() => _priceListOpen = false);
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
    if (done) {
      final orderId = widget.order['id'] as int;
      final car = [
        widget.order['make_model']?.toString() ?? '',
        widget.order['plate']?.toString() ?? '',
      ].where((s) => s.trim().isNotEmpty).join(' · ');
      await AppNotifications.postPackageDone(
        orderId: orderId,
        packageName: label,
        positions: children.length,
        clientName: widget.order['client_name']?.toString(),
        carLabel: car,
      );
      await AppNotifications.maybePostWorkshopAllDone(
        orderId: orderId,
        workshop: 'Оклейка',
        clientName: widget.order['client_name']?.toString(),
        carLabel: car,
      );
    }
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
    if (_opsRestricted && !_editableWorkshops.contains('Оклейка')) {
      showAppToast(context, 'Мастер может править только свой цех');
      return;
    }
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
    if (_opsRestricted && !_editableWorkshops.contains(workshop)) {
      showAppToast(context, 'Мастер может назначать только свой цех');
      return;
    }
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

    if (filtered.isEmpty && mounted) {
      showAppToast(context, missingMastersMessage([workshop]));
    }

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
                  "Исполнитель · $workshop (пакет)",
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                ),
                content: SizedBox(
                  width: 280,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.handshake_outlined, color: AppColors.primary),
                        title: Text('Аутсорс…', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 14)),
                        onTap: () {
                          Navigator.pop(context);
                          final idx = _selectedWorks.indexWhere((e) => e['id'] == header['id']);
                          if (idx >= 0) _assignOutsourceToWork(idx, _selectedWorks[idx]);
                        },
                      ),
                      const Divider(height: 16),
                      if (filtered.isEmpty)
                        Text(
                          "Нет мастеров с ролью для цеха «$workshop».\nДобавь их в разделе Сотрудники.",
                          style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.35),
                        )
                      else
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                          ),
                          child: ListView(
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
                    ],
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
    final itemId = (child['id'] as num?)?.toInt();
    final commentOpen = itemId != null && _expandedWorkComments.contains(itemId);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(4, 0, 2, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDone ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8, left: 4),
                child: PremiumCheck(
                  value: isDone,
                  enabled: canToggleZones,
                  onChanged: !canToggleZones
                      ? null
                      : (val) async {
                          final id = (child['id'] as num).toInt();
                          final idx = _selectedWorks.indexWhere((w) => (w['id'] as num?)?.toInt() == id);
                          if (idx >= 0) await _toggleWorkDone(idx, val);
                        },
                ),
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
              _workCommentToggle(child),
              if (!workshopView)
                IconButton(
                  tooltip: "Убрать из пакета",
                  icon: const Icon(Icons.close, color: AppColors.danger, size: 18),
                  onPressed: () => _removeWork(child),
                ),
            ],
          ),
          if (commentOpen)
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
    final headerId = (header['id'] as num?)?.toInt();
    final commentOpen = headerId != null && _expandedWorkComments.contains(headerId);
    final packageWs = _resolvedWorkWorkshop(header);
    final canEditPkg = _canEditWorkshopOps(packageWs.isNotEmpty ? packageWs : 'Оклейка');
    final atCar = _carLocationWorkshop != null &&
        (_workMatchesCarLocation(header) ||
            _resolvedWorkWorkshop(header) == _carLocationWorkshop ||
            (_carLocationWorkshop == 'Оклейка' &&
                (packageName == 'Оклейка' || packageName == 'Тонировка')));
    final locAccent = _carLocationAccent;
    final hasLoc = _carLocationWorkshop != null;

    return Opacity(
      opacity: hasLoc && !atCar ? 0.72 : 1,
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: atCar
            ? Color.alphaBlend(locAccent.withValues(alpha: 0.14), AppColors.surface2)
            : AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: atCar
              ? locAccent.withValues(alpha: 0.55)
              : (allDone ? AppColors.primary.withValues(alpha: 0.45) : AppColors.border),
          width: atCar ? 1.4 : 1,
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
                      [
                        if (atCar) 'сейчас',
                        if (allDone)
                          'Выполнено'
                        else if (someDone)
                          'Частично · $doneCount из ${children.length}'
                        else
                          'Не выполнено',
                      ].join(' · '),
                      style: GoogleFonts.manrope(
                        color: atCar
                            ? locAccent
                            : (allDone ? AppColors.primary : AppColors.textDim),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (!workshopView) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Tooltip(
                    message: "Зоны и сумма",
                    child: InkWell(
                      onTap: () => _openZonePackageEditor(kind),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "${_formatMoney(price)} ₽",
                              style: GoogleFonts.manrope(
                                color: AppColors.success,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: AppColors.success.withValues(alpha: 0.75),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
                Flexible(
                  child: _masterActionChip(
                    masters: masters,
                    hasMasters: hasMasters,
                    onTap: canEditPkg ? () => _pickMastersForWrapPackage(header) : null,
                  ),
                ),
                const SizedBox(width: 8),
                _timeIconChip(
                  value: header['start_time']?.toString(),
                  icon: Icons.play_arrow_rounded,
                  tooltip: canEditPkg ? "Начало" : "Только просмотр",
                  color: AppColors.success,
                  onTap: !canEditPkg
                      ? null
                      : () async {
                    final dt = await _pickDateTime(current: header['start_time']?.toString());
                    if (dt == null) return;
                    await _saveWrapPackageSchedule(
                      header: header,
                      start: dt,
                      logText: "Пакет оклейки: начало ${_formatDT(dt, dt)}",
                    );
                  },
                ),
                const SizedBox(width: 6),
                _timeIconChip(
                  value: header['end_time']?.toString(),
                  icon: Icons.stop_rounded,
                  tooltip: canEditPkg ? "Конец" : "Только просмотр",
                  color: AppColors.danger,
                  onTap: !canEditPkg
                      ? null
                      : () async {
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
                const SizedBox(width: 6),
                _workCommentToggle(header),
              ],
            ),
          ] else ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: _workCommentToggle(header),
            ),
          ],
          if (commentOpen) _workCommentField(header),
          if (_showPayrollOnPackageHeader(header) && canEditPkg) ...[
            Builder(
              builder: (context) {
                final ws = _resolvedWorkWorkshop(header);
                return _buildWorkshopPayrollEditor(
                  ws.isNotEmpty ? ws : 'Оклейка',
                  embedded: true,
                );
              },
            ),
          ],
          const SizedBox(height: 4),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              // В цехе сразу раскрыт — мастер видит зоны (тонировка/оклейка).
              // В админке свёрнут, иначе список забивает экран.
              initiallyExpanded: workshopView,
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
    ),
    );
  }

  Widget _buildWorksListView({bool shrinkWrap = false, List<Widget> leading = const []}) {
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

    final emptyWorks = wrapHeader == null && tintHeader == null && standalone.isEmpty;
    if (emptyWorks && leading.isEmpty) {
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
        ...leading,
        if (emptyWorks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              "Нет услуг в заказе",
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(color: AppColors.textDim),
            ),
          ),
        if (wrapHeader != null) _buildWrapPackageBlock(wrapHeader, wrapChildren),
        if (tintHeader != null) _buildWrapPackageBlock(tintHeader, tintChildren),
        for (final w in standalone)
          _buildWorkCard(w, showPayroll: _showPayrollOnStandalone(w, standalone)),
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

  /// Компактная подпись в ряду графика (2 строки на телефоне).
  String get _techWashChipLabelCompact {
    if (!_isTechWash) return '+ Тех.\nмойка';
    final a = _formatDT(_techWashStart, '');
    final b = _formatDT(_techWashEnd, '');
    if (a.isNotEmpty && b.isNotEmpty) return 'Тех. мойка\n$a–$b';
    if (a.isNotEmpty) return 'Тех. мойка\nс $a';
    if (b.isNotEmpty) return 'Тех. мойка\nдо $b';
    return 'Тех.\nмойка';
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
                        activeThumbColor: AppColors.primary,
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
    final label = compact ? _techWashChipLabelCompact : _techWashChipLabel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openTechWashDialog,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: compact ? null : double.infinity,
          constraints: compact ? const BoxConstraints(minHeight: 48) : null,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 6 : 12,
          ),
          decoration: BoxDecoration(
            color: active ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surface2,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(
              color: active ? AppColors.primary.withValues(alpha: 0.55) : AppColors.border,
            ),
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Icon(
                active ? Icons.local_car_wash : Icons.local_car_wash_outlined,
                size: compact ? 17 : 18,
                color: active ? AppColors.primary : AppColors.textMuted,
              ),
              SizedBox(width: compact ? 6 : 8),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.manrope(
                    color: active ? AppColors.text : AppColors.textMuted,
                    fontSize: compact ? 11.5 : 13,
                    fontWeight: FontWeight.w700,
                    height: compact ? 1.15 : null,
                  ),
                  maxLines: compact ? 2 : 1,
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
    if (_opsRestricted) return;
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
    if (_opsRestricted) return;
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
                  onTap: _opsRestricted ? null : _setOrderStartTime,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _timeBadge(
                  value: _orderEndTime,
                  emptyLabel: 'Выдача',
                  color: AppColors.danger,
                  onTap: _opsRestricted ? null : _setOrderEndTime,
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
                  color: AppColors.bg.withValues(alpha: 0.45),
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
                      enabled: !_opsRestricted,
                      decoration: const InputDecoration(labelText: "От клиента", isDense: true),
                      textInputAction: TextInputAction.send,
                      onSubmitted: _opsRestricted
                          ? null
                          : (val) => _submitNoteToTimeline(
                                text: val,
                                eventPrefix: "От клиента",
                                controller: _clientNotesController,
                                persist: (t) => DatabaseHelper().updateOrderClientNotes(widget.order['id'], t),
                              ),
                      onChanged: _opsRestricted
                          ? null
                          : (val) async {
                              await DatabaseHelper().updateOrderClientNotes(widget.order['id'], val);
                            },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _visibleNotesController,
                      enabled: !_opsRestricted,
                      decoration: const InputDecoration(labelText: "Для клиента", isDense: true),
                      textInputAction: TextInputAction.send,
                      onSubmitted: _opsRestricted
                          ? null
                          : (val) => _submitNoteToTimeline(
                                text: val,
                                eventPrefix: "Для клиента",
                                controller: _visibleNotesController,
                                persist: (t) =>
                                    DatabaseHelper().updateOrderClientVisibleNotes(widget.order['id'], t),
                              ),
                      onChanged: _opsRestricted
                          ? null
                          : (val) async {
                              await DatabaseHelper().updateOrderClientVisibleNotes(widget.order['id'], val);
                            },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
          _feedIconButton(),
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

  Widget _buildWorkshopWorkRow(int index, {bool showPayroll = false}) {
    final w = _selectedWorks[index];
    final isDone = (w['is_done'] as num?)?.toInt() == 1;
    final ws = _resolvedWorkWorkshop(w);
    final canToggle = _canToggleWorkInWorkshop(w);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
      decoration: BoxDecoration(
        color: isDone ? AppColors.primary.withValues(alpha: 0.08) : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDone ? AppColors.primary.withValues(alpha: 0.35) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8, left: 4),
                child: PremiumCheck(
                  value: isDone,
                  enabled: canToggle,
                  onChanged: canToggle ? (val) => _toggleWorkDone(index, val) : null,
                ),
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
          if (showPayroll && ws.isNotEmpty && _canEditWorkshopOps(ws))
            _buildWorkshopPayrollEditor(ws, embedded: true),
        ],
      ),
    );
  }

  /// Список работ цеха: пакеты оклейки/тонировки — блоками, без дубля шапка+зоны.
  /// Чужие цеха тоже видны (мастер видит весь заказ), но галочка только у своего цеха.
  Widget _buildWorkshopWorksList({bool shrinkWrap = false}) {
    final isWrapShop = widget.workshop == 'Оклейка';

    final wrapHeader = isWrapShop ? _wrapPackageHeader() : null;
    final wrapChildren = wrapHeader != null
        ? _wrapPackageChildren((wrapHeader['id'] as num).toInt())
        : <Map<String, dynamic>>[];
    final tintHeader = isWrapShop ? _tintPackageHeader() : null;
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
      final cat = w['category']?.toString();

      // Шапка пакета уже в блоке (если цех Оклейка).
      if (isZonePackageHeader(name)) {
        // В другом цехе шапку/зоны пакета показываем строками (read-only).
        if (!isWrapShop) otherIndexes.add(i);
        continue;
      }

      // Зона: в Оклейке — в блоке пакета или сиротой-строкой; в других цехах — строкой.
      if (isZonePackageLine(category: cat, name: name)) {
        final underPackage = id != null && packageIds.contains(id);
        if (underPackage) continue;
        otherIndexes.add(i);
        continue;
      }

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
        for (final i in otherIndexes)
          _buildWorkshopWorkRow(
            i,
            showPayroll: _showPayrollOnStandalone(
              _selectedWorks[i],
              otherIndexes.map((j) => _selectedWorks[j]).toList(),
            ),
          ),
      ],
    );
  }

  /// Входящие «Для цеха …» для текущего цеха (лента не трогаем).
  List<Map<String, dynamic>> _workshopInboxEvents() {
    final ws = widget.workshop;
    if (ws == null || ws.isEmpty) return const [];
    final out = <Map<String, dynamic>>[];
    for (final ev in _events) {
      final raw = ev['event_text']?.toString() ?? '';
      final parsed = _parseTimelineEvent(raw);
      if (parsed.direction != 'forShop') continue;
      if (parsed.workshop != ws) continue;
      out.add(ev);
    }
    return out;
  }

  /// События для бейджа непрочитанных.
  List<Map<String, dynamic>> _feedBadgeEvents() {
    if (_isWorkshopMode) return _workshopInboxEvents();
    final out = <Map<String, dynamic>>[];
    for (final ev in _events) {
      final raw = ev['event_text']?.toString() ?? '';
      if (_isFromClientEvent(raw)) {
        out.add(ev);
        continue;
      }
      final parsed = _parseTimelineEvent(raw);
      if (parsed.direction == 'forShop') out.add(ev);
    }
    return out;
  }

  String get _feedSeenKey {
    final oid = widget.order['id'];
    if (_isWorkshopMode) {
      final ws = widget.workshop ?? '';
      return 'ws_feed_seen_${oid}_$ws';
    }
    return 'order_feed_seen_$oid';
  }

  Future<void> _loadFeedSeen() async {
    final raw = await DatabaseHelper().getAppSetting(_feedSeenKey);
    if (raw == null) {
      var maxId = 0;
      for (final ev in _feedBadgeEvents()) {
        final id = (ev['id'] as num?)?.toInt() ?? 0;
        if (id > maxId) maxId = id;
      }
      _feedSeenId = maxId;
      if (maxId > 0) {
        await DatabaseHelper().setAppSetting(_feedSeenKey, '$maxId');
      }
      return;
    }
    _feedSeenId = int.tryParse(raw) ?? 0;
  }

  int get _feedUnreadCount {
    var n = 0;
    for (final ev in _feedBadgeEvents()) {
      final id = (ev['id'] as num?)?.toInt() ?? 0;
      if (id > _feedSeenId) n++;
    }
    return n;
  }

  Future<void> _markFeedSeen() async {
    var maxId = _feedSeenId;
    for (final ev in _feedBadgeEvents()) {
      final id = (ev['id'] as num?)?.toInt() ?? 0;
      if (id > maxId) maxId = id;
    }
    if (maxId == _feedSeenId) return;
    _feedSeenId = maxId;
    await DatabaseHelper().setAppSetting(_feedSeenKey, '$maxId');
    if (mounted) setState(() {});
  }

  Widget _feedIconButton({bool largeTap = false}) {
    return IconButton(
      tooltip: 'Лента',
      style: largeTap ? IconButton.styleFrom(minimumSize: const Size(44, 44)) : null,
      onPressed: _openOrderFeedSheet,
      icon: Badge(
        isLabelVisible: _feedUnreadCount > 0,
        backgroundColor: AppColors.danger,
        label: Text(
          _feedUnreadCount > 9 ? '9+' : '$_feedUnreadCount',
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        child: const Icon(Icons.forum_outlined, color: AppColors.primary),
      ),
    );
  }

  Future<void> _openOrderFeedSheet() async {
    await _markFeedSeen();
    if (!mounted) return;
    final workshop = _isWorkshopMode;
    final title = workshop ? 'Лента · ${widget.workshop ?? ''}' : 'Лента событий';
    final hint = workshop ? 'Комментарий от цеха (Enter)…' : 'Комментарий в ленту (Enter)…';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final h = MediaQuery.sizeOf(ctx).height;
            Future<void> send() async {
              if (workshop) {
                await _addWorkshopMasterComment();
              } else {
                await _addCommentToTimeline();
              }
              await _markFeedSeen();
              setModal(() {});
            }

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
              child: Container(
                height: h * 0.92,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
                        child: Row(
                          children: [
                            const SizedBox(width: 8),
                            const Icon(Icons.forum_outlined, color: AppColors.primary, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                title,
                                style: GoogleFonts.manrope(
                                  color: AppColors.text,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Закрыть',
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                          child: _buildPinnedTimelineBody(
                            composer: TextField(
                              controller: _commentController,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => send(),
                              style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: hint,
                                hintStyle: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
                                isDense: true,
                                filled: true,
                                fillColor: AppColors.bg.withValues(alpha: 0.45),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: 'Отправить',
                                  icon: const Icon(Icons.send, size: 18, color: AppColors.primary),
                                  onPressed: send,
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
            );
          },
        );
      },
    );
    if (mounted) await _markFeedSeen();
  }

  Widget _workshopInner() {
    final isWrapShop = widget.workshop == 'Оклейка';
    return Column(
      children: [
        _buildWorkshopHeader(),
        const Divider(height: 1),
        Expanded(
          // Один скролл на весь контент (мастера + плёнки + работы) —
          // иначе Expanded-список работ обрезается раскрытой панелью плёнок.
          child: SingleChildScrollView(
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
                  "Все работы заказа видны · галочка только у цеха «${widget.workshop}»",
                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                ),
                const SizedBox(height: 10),
                _buildWorkshopWorksList(shrinkWrap: true),
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
        width: math.min(720, MediaQuery.sizeOf(context).width - 96),
        height: math.min(820, MediaQuery.sizeOf(context).height - 72),
        child: _workshopInner(),
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
          childrenPadding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "Заказ #${widget.order['id']}  ·  ${widget.order['client_name']}",
              style: GoogleFonts.manrope(
                color: AppColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: "Печать заказ-наряда",
            style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
            onPressed: _printWorkOrder,
            icon: const Icon(Icons.print_outlined, color: AppColors.primary),
          ),
          IconButton(
            tooltip: 'Дефекты',
            style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
            onPressed: () => _openDefectsSheet(),
            icon: const Icon(Icons.report_problem_outlined, color: AppColors.danger),
          ),
          _feedIconButton(largeTap: true),
          IconButton(
            style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
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
                    _staffAssignRow(),
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
              _buildHandoverChecklist(),
              if (_selectedWorks.any((work) => work['workshop']?.toString() == 'Оклейка'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
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
                subtitle: "Диалог с клиентом",
                child: _buildNotesColumn(fill: false),
              ),
              if (!_opsRestricted)
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
        KeyedSubtree(key: TourKeys.orderDetailsHeader, child: _buildOrderWindowHeader()),
        const Divider(height: 1),
        Expanded(
          child: PulseAnchor(
            active: isPulseActive('od_pay') || isPulseActive('od_promo'),
            child: KeyedSubtree(
              key: TourKeys.orderDetailsPayment,
              child: _buildOrderWindowBody(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminBody() {
    final content = GestureDetector(
      onTap: () {
        setState(() {
          _priceListOpen = false;
          _expandedWorkComments.clear();
        });
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
        width: math.min(1500, MediaQuery.sizeOf(context).width - 56),
        height: math.min(1200, MediaQuery.sizeOf(context).height - 40),
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
        final sz = MediaQuery.sizeOf(context);
        panel = Dialog(
          backgroundColor: AppColors.surface,
          child: SizedBox(
            width: math.min(_isWorkshopMode ? 720 : 1500, sz.width - 56),
            height: math.min(_isWorkshopMode ? 820 : 1200, sz.height - 40),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
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

