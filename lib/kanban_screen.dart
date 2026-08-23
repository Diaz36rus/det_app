import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'app_theme.dart';
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
import 'works_progress_bar.dart';

class KanbanScreen extends StatefulWidget {
  const KanbanScreen({super.key});

  @override
  State<KanbanScreen> createState() => _KanbanScreenState();
}

class _KanbanScreenState extends State<KanbanScreen> with DbRefreshMixin, PulseHighlightMixin {
  @override
  void onDatabaseChanged() => _loadOrders();

  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  String _currentDateTime = "";
  Timer? _timer;
  final ScrollController _kanbanController = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  String _selectedStatusFilter = "Все статусы";
  bool _debtOnly = false;
  bool _todayOnly = false;

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _startTimer();
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

  Widget _filterChip(String label, bool selected, ValueChanged<bool> onSelected, {Color? accent}) {
    final activeColor = accent ?? AppColors.primary;
    return FilterChip(
      label: Text(
        label,
        style: GoogleFonts.manrope(
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
          color: selected ? AppColors.text : AppColors.textMuted,
        ),
      ),
      selected: selected,
      onSelected: onSelected,
      selectedColor: activeColor,
      backgroundColor: AppColors.surface2,
      side: BorderSide(color: selected ? activeColor : AppColors.border),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _statusDropdown({required bool expanded}) {
    return Container(
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
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchCtrl,
      decoration: InputDecoration(
        hintText: 'Клиент, номер, #заказа…',
        prefixIcon: const Icon(Icons.search, color: AppColors.primary, size: 20),
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
        filled: true,
        fillColor: AppColors.surface2.withOpacity(0.92),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          borderSide: BorderSide.none,
        ),
      ),
      style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
      onChanged: (_) => setState(() {}),
    );
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

  Widget _buildOrderCard(
    Map<String, dynamic> o,
    String status, {
    bool isFeedback = false,
    bool showStatusButton = false,
  }) {
    final accent = kOrderStatusColors[status] ?? AppColors.primary;
    final orderId = (o['id'] as num?)?.toInt();
    return PulseAnchor(
      active: !isFeedback && orderId != null && isPulseActive(orderId),
      accent: AppColors.danger,
      child: Container(
      width: isFeedback ? 240 : double.infinity,
      margin: isFeedback ? EdgeInsets.zero : const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2.withOpacity(0.92),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border(
          left: BorderSide(color: accent.withOpacity(0.85), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${o['client_name'] ?? ''}",
                  style: GoogleFonts.manrope(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  "${o['make_model'] ?? ''}",
                  style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                if ((o['plate']?.toString() ?? "").isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    "${o['plate']}",
                    style: GoogleFonts.manrope(
                      color: AppColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
                if (!isFeedback && o['master_name'] != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    "${o['master_name']}",
                    style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (!isFeedback && o['notes'] != null && o['notes'].toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    "${o['notes']}",
                    style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, height: 1.25),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ],
                if (showStatusButton && !isFeedback) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _changeOrderStatus(o),
                      icon: const Icon(Icons.flag_outlined, size: 16),
                      label: Text(
                        status,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 12.5),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side: BorderSide(color: accent.withOpacity(0.55)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
                if (!isFeedback) ...[
                  const SizedBox(height: 8),
                  WorksProgressBar.fromOrder(o, compact: true),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (_) {
                      final price = (o['price'] as num?)?.toDouble() ?? 0;
                      final paid = (o['paid_amount'] as num?)?.toDouble() ?? 0;
                      final debt = price - paid;
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "${o['price']} ₽",
                                  style: GoogleFonts.manrope(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                if (debt > 0.01)
                                  Text(
                                    'долг ${debt == debt.roundToDouble() ? debt.toInt() : debt.toStringAsFixed(0)} ₽',
                                    style: GoogleFonts.manrope(
                                      color: AppColors.danger,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (debt > 0.01)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Быстрая оплата',
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
                            tooltip: 'WhatsApp: готов к выдаче',
                            icon: const Icon(Icons.chat_outlined, color: AppColors.success, size: 18),
                            onPressed: () async {
                              final id = (o['id'] as num).toInt();
                              await runWithPulseHighlight(
                                id,
                                () => ReadyNotifyActions.notifyOrder(context, order: o),
                              );
                            },
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Заказ-наряд PDF',
                            icon: const Icon(Icons.print_outlined, color: AppColors.textMuted, size: 18),
                            onPressed: () async {
                              final id = (o['id'] as num).toInt();
                              await runWithPulseHighlight(
                                id,
                                () => WorkOrderActions.previewByOrderId(context, id),
                              );
                            },
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: "Удалить",
                            icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                            onPressed: () async {
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
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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

    final columnBody = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: colWidth,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border(
          top: BorderSide(color: accent.withOpacity(0.55), width: 3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  style: GoogleFonts.manrope(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                "${colOrders.length}",
                style: GoogleFonts.manrope(
                  color: AppColors.textDim,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: cardList()),
        ],
      ),
    );

    if (mobile) return columnBody;

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
        final hovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: colWidth,
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: hovering
                ? AppColors.primarySoft.withOpacity(0.45)
                : AppColors.surface.withOpacity(0.55),
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border(
              top: BorderSide(color: accent.withOpacity(hovering ? 0.9 : 0.55), width: 3),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status,
                      style: GoogleFonts.manrope(
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    "${colOrders.length}",
                    style: GoogleFonts.manrope(
                      color: AppColors.textDim,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(child: cardList()),
            ],
          ),
        );
      },
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
    final colWidth = mobile ? (MediaQuery.sizeOf(context).width * 0.78).clamp(240.0, 300.0) : 280.0;
    final filteredOrders = _orders.where(_matchesBoardFilters).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: KeyedSubtree(
        key: TourKeys.kanbanArea,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(mobile ? 12 : 24, mobile ? 12 : 20, mobile ? 12 : 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (mobile) ...[
                    _searchField(),
                    const SizedBox(height: 8),
                    _statusDropdown(expanded: true),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _filterChip('С долгом', _debtOnly, (v) => setState(() => _debtOnly = v), accent: AppColors.danger),
                        const SizedBox(width: 8),
                        _filterChip('Сегодня', _todayOnly, (v) => setState(() => _todayOnly = v)),
                        const Spacer(),
                        Text(
                          _currentDateTime,
                          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ] else
                    Row(
                      children: [
                        SizedBox(width: 280, child: _searchField()),
                        const SizedBox(width: 10),
                        Flexible(child: _statusDropdown(expanded: true)),
                        const SizedBox(width: 10),
                        _filterChip('С долгом', _debtOnly, (v) => setState(() => _debtOnly = v), accent: AppColors.danger),
                        const SizedBox(width: 8),
                        _filterChip('Сегодня', _todayOnly, (v) => setState(() => _todayOnly = v)),
                        const SizedBox(width: 12),
                        Text(
                          _currentDateTime,
                          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  if (_hasExtraFilters) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Показано ${filteredOrders.length} из ${_orders.length}',
                      style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
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
                          trackVisibility: true,
                          thumbVisibility: true,
                          child: ListView.builder(
                            controller: _kanbanController,
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.fromLTRB(mobile ? 10 : 16, 12, mobile ? 10 : 16, 16),
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
