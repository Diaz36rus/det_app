import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:async';
import 'app_menu.dart';
import 'app_notifications.dart';
import 'app_theme.dart';
import 'auth/auth_controller.dart';
import 'board_export.dart';
import 'database.dart';
import 'db_refresh_mixin.dart';
import 'issue_guard.dart';
import 'order_details_dialog.dart';
import 'pulse_anchor.dart';
import 'quick_payment_dialog.dart';
import 'ready_notify_actions.dart';
import 'responsive.dart';
import 'tour_keys.dart';
import 'work_order_actions.dart';
import 'ui_kit.dart';

class KanbanScreen extends StatefulWidget {
  const KanbanScreen({super.key, this.onNewOrder, this.onNavigateMenu});

  final VoidCallback? onNewOrder;
  final ValueChanged<int>? onNavigateMenu;

  @override
  State<KanbanScreen> createState() => _KanbanScreenState();
}

class _KanbanScreenState extends State<KanbanScreen> with DbRefreshMixin, PulseHighlightMixin {
  @override
  void onDatabaseChanged() => _loadOrders();

  static final _money = NumberFormat('#,##0', 'ru_RU');

  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  String _currentDateTime = "";
  Timer? _timer;
  final ScrollController _kanbanController = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  String _selectedStatusFilter = "Все статусы";
  bool _debtOnly = false;
  bool _todayOnly = false;

  String _fmtMoney(num? v) => '${_money.format(v ?? 0)} ₽';

  String _serviceLine(Map<String, dynamic> o, String status) {
    final notes = o['notes']?.toString().trim() ?? '';
    if (notes.isNotEmpty) {
      final line = notes.split('\n').first.trim();
      if (line.isNotEmpty) {
        final compact = compactOrderServicesLine(line);
        return compact.isNotEmpty ? compact : line;
      }
    }
    return status;
  }

  String _cardWhenLabel(Map<String, dynamic> o) {
    final raw = (o['start_time'] ?? o['due_date'] ?? o['end_time'] ?? '')
        .toString()
        .trim();
    if (raw.isEmpty) return '';
    final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    final dt = DateTime.tryParse(normalized);
    if (dt == null) {
      return raw.length > 16 ? raw.substring(0, 16) : raw;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final time = DateFormat('HH:mm').format(dt);
    if (day == today) return 'Сегодня, $time';
    if (day == today.add(const Duration(days: 1))) return 'Завтра, $time';
    return DateFormat('dd.MM, HH:mm').format(dt);
  }

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _startTimer();
    AppNotifications.refreshUnread();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _currentDateTime = DateFormat('dd.MM.yyyy HH:mm:ss').format(DateTime.now());
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _kanbanController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  static String _dayOf(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final s = raw.replaceAll('T', ' ').trim();
    return s.length >= 10 ? s.substring(0, 10) : '';
  }

  bool _isTodayOrder(Map<String, dynamic> o) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return _dayOf(o['start_time']?.toString()) == today ||
        _dayOf(o['end_time']?.toString()) == today ||
        _dayOf(o['due_date']?.toString()) == today ||
        _dayOf(o['end_date']?.toString()) == today;
  }

  bool _matchesBoardFilters(Map<String, dynamic> o) {
    if (_debtOnly) {
      final price = (o['price'] as num?)?.toDouble() ?? 0;
      final paid = (o['paid_amount'] as num?)?.toDouble() ?? 0;
      if (price - paid <= 0.01) return false;
    }
    if (_todayOnly && !_isTodayOrder(o)) return false;

    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final id = o['id']?.toString() ?? '';
    final hay = [
      id,
      '#$id',
      o['client_name']?.toString() ?? '',
      o['client_phone']?.toString() ?? '',
      o['make_model']?.toString() ?? '',
      o['plate']?.toString() ?? '',
      o['master_name']?.toString() ?? '',
      o['notes']?.toString() ?? '',
    ].join(' ').toLowerCase();
    return hay.contains(q);
  }

  bool get _hasExtraFilters =>
      _debtOnly || _todayOnly || _searchCtrl.text.trim().isNotEmpty;

  Widget _filterChip(
    String label,
    bool selected,
    ValueChanged<bool> onSelected, {
    Color? accent,
    Key? key,
  }) {
    final activeColor = accent ?? AppColors.primary;
    final mobile = AppResponsive.isMobile(context);
    return KeyedSubtree(
      key: key,
      child: FilterChip(
        label: Text(
          label,
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w600,
            fontSize: mobile ? 13.5 : 12.5,
            color: selected ? AppColors.text : AppColors.textMuted,
          ),
        ),
        selected: selected,
        onSelected: onSelected,
        selectedColor: activeColor,
        backgroundColor: AppColors.surface2,
        side: BorderSide(color: selected ? activeColor : AppColors.border),
        showCheckmark: false,
        visualDensity: mobile ? VisualDensity.standard : VisualDensity.compact,
        materialTapTargetSize: mobile ? MaterialTapTargetSize.padded : MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.symmetric(horizontal: mobile ? 10 : 4, vertical: mobile ? 2 : 0),
      ),
    );
  }

  Widget _statusDropdown({required bool expanded}) {
    return KeyedSubtree(
      key: TourKeys.kanbanStatusFilter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: AppTheme.panelDecoration,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: expanded,
            value: _selectedStatusFilter,
            dropdownColor: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
            icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textMuted),
            items: ["Все статусы", ...STATUSES.where((s) => s != "Выдан")].map((status) {
              return DropdownMenuItem<String>(
                value: status,
                child: Text(status, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (val) {
              if (val == null) return;
              setState(() => _selectedStatusFilter = val);
            },
          ),
        ),
      ),
    );
  }

  Widget _searchField() {
    return KeyedSubtree(
      key: TourKeys.kanbanSearch,
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Поиск заказов, клиентов, авто…',
          hintStyle: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13.5, fontWeight: FontWeight.w500),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  tooltip: 'Очистить',
                  icon: const Icon(Icons.clear, color: AppColors.textDim, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() {});
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          filled: true,
          fillColor: AppColors.surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.borderSoft),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.borderSoft),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primary.withOpacity(0.55)),
          ),
        ),
        style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _newOrderButton({bool expanded = false}) {
    final btn = FilledButton.icon(
      onPressed: widget.onNewOrder,
      icon: const Icon(Icons.add_rounded, size: 20),
      label: Text(
        'Новый заказ',
        style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 13.5),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
    );
    if (!expanded) return btn;
    return SizedBox(width: double.infinity, child: btn);
  }

  Future<void> _loadOrders() async {
    final orders = await DatabaseHelper().getAllOrders();
    setState(() {
      _orders = orders;
      _isLoading = false;
    });
  }

  Future<void> _changeOrderStatus(Map<String, dynamic> o) async {
    final current = o['status']?.toString() ?? '';
    final options = List<String>.from(STATUSES);
    final next = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Text(
                  'Статус заказа #${o['id']}',
                  style: GoogleFonts.manrope(
                    color: AppColors.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              for (final s in options)
                ListTile(
                  leading: Icon(
                    s == current ? Icons.check_circle : Icons.circle_outlined,
                    color: s == current
                        ? (kOrderStatusColors[s] ?? AppColors.primary)
                        : AppColors.textDim,
                    size: 20,
                  ),
                  title: Text(
                    s,
                    style: GoogleFonts.manrope(
                      color: AppColors.text,
                      fontWeight: s == current ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, s),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (next == null || next == current || !mounted) return;
    final ok = await tryUpdateOrderStatus(context, (o['id'] as num).toInt(), next);
    if (!ok) {
      if (mounted) setState(() {});
      return;
    }
    await DatabaseHelper().addOrderEvent((o['id'] as num).toInt(), 'Статус изменен на: $next');
    _loadOrders();
  }

  Future<void> _confirmDeleteOrder(Map<String, dynamic> o) async {
    final id = (o['id'] as num).toInt();
    final confirm = await runWithPulseHighlight(
      id,
      () => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Удалить заказ?", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          content: Text(
            "Все данные заказа будут безвозвратно удалены.",
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
      ),
    );
    if (confirm == true) {
      try {
        await DatabaseHelper().deleteOrder(id);
        _loadOrders();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось удалить: $e')),
        );
      }
    }
  }

  Widget _buildOrderCard(
    Map<String, dynamic> o,
    String status, {
    bool isFeedback = false,
    bool showStatusButton = false,
  }) {
    final accent = kOrderStatusColors[status] ?? AppColors.primary;
    final orderId = (o['id'] as num?)?.toInt();
    final plate = o['plate']?.toString() ?? '';
    final make = o['make_model']?.toString() ?? '';
    final client = o['client_name']?.toString() ?? '';
    final master = (o['master_name']?.toString() ?? '').trim();
    final when = _cardWhenLabel(o);
    final service = _serviceLine(o, status);
    final price = (o['price'] as num?)?.toDouble() ?? 0;
    final paid = (o['paid_amount'] as num?)?.toDouble() ?? 0;
    final debt = price - paid;
    final title = make.isNotEmpty ? make : (client.isNotEmpty ? client : 'Заказ');

    return PulseAnchor(
      active: !isFeedback && orderId != null && isPulseActive(orderId),
      accent: AppColors.danger,
      child: Container(
        width: isFeedback ? 260 : double.infinity,
        margin: isFeedback ? EdgeInsets.zero : const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderSoft),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CarBrandMark(make, size: 60),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (plate.isNotEmpty) Expanded(child: Align(alignment: Alignment.centerLeft, child: PlateBadge(plate))),
                          if (plate.isEmpty) const Spacer(),
                          if (!isFeedback)
                            IconButton(
                              tooltip: 'Удалить',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: AppColors.danger.withOpacity(0.85),
                              ),
                              onPressed: () => _confirmDeleteOrder(o),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: GoogleFonts.manrope(
                          color: AppColors.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          height: 1.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              service,
              style: GoogleFonts.manrope(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (!isFeedback) ...[
              if (client.isNotEmpty || when.isNotEmpty || master.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (client.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_outline_rounded, size: 14, color: AppColors.textDim),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: Text(
                              client,
                              style: GoogleFonts.manrope(
                                color: AppColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    if (when.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule_rounded, size: 14, color: AppColors.textDim),
                          const SizedBox(width: 4),
                          Text(
                            when,
                            style: GoogleFonts.manrope(
                              color: AppColors.textDim,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    if (master.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.handyman_outlined, size: 14, color: AppColors.primary.withOpacity(0.85)),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 110),
                            child: Text(
                              master,
                              style: GoogleFonts.manrope(
                                color: AppColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  if (debt > 0.01)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Быстрая оплата',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: const Icon(Icons.payments_outlined, color: AppColors.primary, size: 18),
                      onPressed: () async {
                        final id = (o['id'] as num).toInt();
                        final ok = await runWithPulseHighlight(
                          id,
                          () => QuickPaymentDialog.open(context, orderId: id),
                        );
                        if (ok == true) _loadOrders();
                      },
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'WhatsApp: готов',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: const Icon(Icons.chat_outlined, color: AppColors.success, size: 18),
                    onPressed: () async {
                      await runWithPulseHighlight(
                        (o['id'] as num).toInt(),
                        () => ReadyNotifyActions.notifyOrder(context, order: o),
                      );
                    },
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Заказ-наряд PDF',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: const Icon(Icons.print_outlined, color: AppColors.textMuted, size: 18),
                    onPressed: () async {
                      final id = (o['id'] as num).toInt();
                      await runWithPulseHighlight(
                        id,
                        () => WorkOrderActions.previewByOrderId(context, id),
                      );
                    },
                  ),
                  const Spacer(),
                  Text(
                    _fmtMoney(price),
                    style: GoogleFonts.manrope(
                      color: debt > 0.01 ? AppColors.danger : AppColors.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                ],
              ),
              if (showStatusButton) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _changeOrderStatus(o),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      status,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _columnChrome({
    required String status,
    required List<Map<String, dynamic>> colOrders,
    required double colWidth,
    required Color accent,
    required bool hovering,
    required Widget cardList,
  }) {
    final sum = colOrders.fold<double>(
      0,
      (a, o) => a + ((o['price'] as num?)?.toDouble() ?? 0),
    );

    // Стеклянная колонка: лёгкий цвет сверху → почти прозрачно вниз, фон доски читается.
    final topTint = accent.withOpacity(hovering ? 0.10 : 0.055);
    final midTint = accent.withOpacity(hovering ? 0.035 : 0.018);
    final base = AppColors.surface.withOpacity(hovering ? 0.10 : 0.06);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: colWidth,
      margin: const EdgeInsets.only(right: 14),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hovering ? accent.withOpacity(0.75) : accent.withOpacity(0.45),
          width: hovering ? 1.55 : 1.25,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topTint, midTint, base],
          stops: const [0.0, 0.32, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(hovering ? 0.14 : 0.04),
            blurRadius: hovering ? 16 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: accent.withOpacity(0.45), blurRadius: 6),
                  ],
                ),
              ),
              Expanded(
                child: Text(
                  status,
                  style: GoogleFonts.manrope(
                    color: AppColors.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accent.withOpacity(0.4)),
                ),
                child: Text(
                  '${colOrders.length}',
                  style: GoogleFonts.manrope(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _fmtMoney(sum),
            style: GoogleFonts.manrope(
              color: AppColors.textDim,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: cardList),
          if (widget.onNewOrder != null) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: widget.onNewOrder,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(
                'Добавить заказ',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textMuted,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusColumn({
    required String status,
    required List<Map<String, dynamic>> colOrders,
    required double colWidth,
    required bool mobile,
    required Color accent,
  }) {
    Widget cardList() {
      return ListView.builder(
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: colOrders.length,
        itemBuilder: (context, i) {
          final o = colOrders[i];
          final card = GestureDetector(
            onTap: () async {
              final shouldRefresh = await OrderDetailsDialog.open(context, o);
              if (shouldRefresh == true) _loadOrders();
            },
            child: _buildOrderCard(o, status, showStatusButton: mobile),
          );
          if (mobile) return card;
          return Draggable<Map<String, dynamic>>(
            data: o,
            feedback: Material(
              color: Colors.transparent,
              elevation: 8,
              child: Opacity(
                opacity: 0.92,
                child: SizedBox(
                  width: colWidth - 24,
                  child: _buildOrderCard(o, status, isFeedback: true),
                ),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.25,
              child: _buildOrderCard(o, status),
            ),
            child: card,
          );
        },
      );
    }

    if (mobile) {
      return _columnChrome(
        status: status,
        colOrders: colOrders,
        colWidth: colWidth,
        accent: accent,
        hovering: false,
        cardList: cardList(),
      );
    }

    return DragTarget<Map<String, dynamic>>(
      onAcceptWithDetails: (details) async {
        final order = details.data;
        if (order['status'] != status) {
          final ok = await tryUpdateOrderStatus(
            context,
            order['id'] as int,
            status,
          );
          if (!ok) {
            if (mounted) setState(() {});
            return;
          }
          await DatabaseHelper().addOrderEvent(order['id'], "Статус изменен на: $status");
          _loadOrders();
        }
      },
      builder: (context, candidateData, rejectedData) {
        return _columnChrome(
          status: status,
          colOrders: colOrders,
          colWidth: colWidth,
          accent: accent,
          hovering: candidateData.isNotEmpty,
          cardList: cardList(),
        );
      },
    );
  }

  Future<void> _exportBoard(List<Map<String, dynamic>> orders) async {
    try {
      final file = await BoardExport.writeCsv(orders);
      final r = await OpenFilex.open(file.path);
      if (!mounted) return;
      if (r.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Файл сохранён:\n${file.path}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Экспорт: ${orders.length} заказов → CSV')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось экспортировать: $e')),
      );
    }
  }

  Widget _adminChip() {
    return ListenableBuilder(
      listenable: AuthController.instance,
      builder: (context, _) {
        final u = AuthController.instance.user;
        final name = u?.displayLabel ?? 'Админ';
        final role = u?.isPlatformAdmin == true
            ? 'Владелец'
            : (u != null && u.roles.isNotEmpty ? u.roles.first : 'Администратор');
        final initials = name.trim().isEmpty
            ? 'А'
            : name.trim().split(RegExp(r'\s+')).take(2).map((e) => e[0]).join().toUpperCase();
        return Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.primarySoft,
                child: Text(
                  initials,
                  style: GoogleFonts.manrope(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.manrope(
                      color: AppColors.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  Text(
                    role,
                    style: GoogleFonts.manrope(
                      color: AppColors.textDim,
                      fontWeight: FontWeight.w600,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _notifyButton() {
    return ListenableBuilder(
      listenable: AppNotifications.unreadRevision,
      builder: (context, _) {
        final n = AppNotifications.unreadRevision.value;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Уведомления',
              onPressed: () {
                widget.onNavigateMenu?.call(AppMenuIds.notifications);
              },
              icon: const Icon(Icons.notifications_none_rounded, color: AppColors.textMuted),
            ),
            if (n > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    n > 9 ? '9+' : '$n',
                    style: GoogleFonts.manrope(
                      color: AppColors.onPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _exportButton(List<Map<String, dynamic>> orders) {
    return OutlinedButton.icon(
      onPressed: orders.isEmpty ? null : () => _exportBoard(orders),
      icon: const Icon(Icons.file_download_outlined, size: 18),
      label: Text('Экспорт', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.border),
        backgroundColor: AppColors.surface2,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _boardHeader({required bool mobile, required List<Map<String, dynamic>> filteredOrders}) {
    final titleBlock = Text(
      'Доска',
      style: AppTheme.pageTitle.copyWith(fontSize: mobile ? 22 : 28),
    );

    final filters = Row(
      children: [
        _filterChip(
          'С долгом',
          _debtOnly,
          (v) => setState(() => _debtOnly = v),
          accent: AppColors.danger,
          key: TourKeys.kanbanDebtFilter,
        ),
        const SizedBox(width: 8),
        _filterChip(
          'Сегодня',
          _todayOnly,
          (v) => setState(() => _todayOnly = v),
          key: TourKeys.kanbanTodayFilter,
        ),
      ],
    );

    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title уже в AppBar — не дублируем.
          _searchField(),
          const SizedBox(height: 10),
          _statusDropdown(expanded: true),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: filters,
          ),
          if (_hasExtraFilters) ...[
            const SizedBox(height: 8),
            Text(
              'Показано ${filteredOrders.length} из ${_orders.length}',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: titleBlock,
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 300, child: _searchField()),
                    const SizedBox(width: 8),
                    _notifyButton(),
                    const SizedBox(width: 4),
                    _adminChip(),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _exportButton(filteredOrders),
                    if (widget.onNewOrder != null) ...[
                      const SizedBox(width: 8),
                      _newOrderButton(),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(width: 200, child: _statusDropdown(expanded: true)),
            const SizedBox(width: 10),
            filters,
            const Spacer(),
            Text(
              _currentDateTime,
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        if (_hasExtraFilters) ...[
          const SizedBox(height: 8),
          Text(
            'Показано ${filteredOrders.length} из ${_orders.length}',
            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return KeyedSubtree(
        key: TourKeys.kanbanArea,
        child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final mobile = AppResponsive.isMobile(context);
    final colWidth = AppResponsive.kanbanColumnWidth(context);
    final filteredOrders = _orders.where(_matchesBoardFilters).toList();
    final hPad = AppResponsive.pagePadH(context);

    // Прозрачный Scaffold — иначе перекрывает MenuBackgrounds (bg_board.jpg).
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: mobile && widget.onNewOrder != null
          ? FloatingActionButton(
              onPressed: widget.onNewOrder,
              tooltip: 'Новый заказ',
              child: const Icon(Icons.add_rounded),
            )
          : null,
      body: KeyedSubtree(
        key: TourKeys.kanbanArea,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, mobile ? 8 : 24, hPad, 8),
              child: _boardHeader(mobile: mobile, filteredOrders: filteredOrders),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _loadOrders,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: constraints.maxHeight,
                        child: Scrollbar(
                          controller: _kanbanController,
                          trackVisibility: !mobile,
                          thumbVisibility: !mobile,
                          child: ListView.builder(
                            controller: _kanbanController,
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.fromLTRB(hPad - 2, 8, hPad, mobile ? 72 : 16),
                            itemCount: STATUSES.length,
                            itemBuilder: (context, index) {
                              final status = STATUSES[index];
                              if (status == "Выдан") return const SizedBox.shrink();
                              if (_selectedStatusFilter != "Все статусы" && status != _selectedStatusFilter) {
                                return const SizedBox.shrink();
                              }

                              final colOrders = filteredOrders.where((o) => o['status'] == status).toList();
                              if (_hasExtraFilters &&
                                  _selectedStatusFilter == "Все статусы" &&
                                  colOrders.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              final accent = kOrderStatusColors[status] ?? AppColors.primary;

                              return _buildStatusColumn(
                                status: status,
                                colOrders: colOrders,
                                colWidth: colWidth,
                                mobile: mobile,
                                accent: accent,
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
