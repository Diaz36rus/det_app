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

  final Map<String, Color> _statusColors = {
    "Предварительная запись": AppColors.textDim,
    "Принят в работу": AppColors.primary,
    "Мойка": const Color(0xFF22D3EE),
    "Химчистка": const Color(0xFFA78BFA),
    "Полировка": const Color(0xFFF59E0B),
    "Оклейка": AppColors.danger,
    "Интерьер": const Color(0xFF14B8A6),
    "Оборудование": const Color(0xFFD97706),
    "Подготовка к выдаче": const Color(0xFF6366F1),
    "Выдан": AppColors.success,
  };

  String _selectedStatusFilter = "Все статусы";

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
    super.dispose();
  }

  Future<void> _loadOrders() async {
    final orders = await DatabaseHelper().getAllOrders();
    setState(() {
      _orders = orders;
      _isLoading = false;
    });
  }

  Widget _buildOrderCard(Map<String, dynamic> o, String status, {bool isFeedback = false}) {
    final accent = _statusColors[status] ?? AppColors.primary;
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
                                await DatabaseHelper().deleteOrder(id);
                                _loadOrders();
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: KeyedSubtree(
        key: TourKeys.kanbanArea,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(mobile ? 12 : 24, mobile ? 12 : 20, mobile ? 12 : 24, 12),
              child: mobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: AppTheme.panelDecoration,
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
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
                                setState(() => _selectedStatusFilter = val!);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _currentDateTime,
                          textAlign: TextAlign.right,
                          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: AppTheme.panelDecoration,
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedStatusFilter,
                                dropdownColor: AppColors.surface,
                                borderRadius: BorderRadius.circular(AppTheme.radius),
                                style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
                                icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textMuted),
                                items: ["Все статусы", ...STATUSES.where((s) => s != "Выдан")].map((status) {
                                  return DropdownMenuItem<String>(value: status, child: Text(status));
                                }).toList(),
                                onChanged: (val) {
                                  setState(() => _selectedStatusFilter = val!);
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _currentDateTime,
                          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 14, fontWeight: FontWeight.w500),
                        ),
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

                    final colOrders = _orders.where((o) => o['status'] == status).toList();
                    final accent = _statusColors[status] ?? AppColors.primary;

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
                              Expanded(
                                child: ListView.builder(
                                  itemCount: colOrders.length,
                                  itemBuilder: (context, i) {
                                    final o = colOrders[i];
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
                                      child: GestureDetector(
                                        onTap: () async {
                                          final shouldRefresh = await OrderDetailsDialog.open(context, o);
                                          if (shouldRefresh == true) _loadOrders();
                                        },
                                        child: _buildOrderCard(o, status),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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
