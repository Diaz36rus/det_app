import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'app_toast.dart';
import 'database.dart';
import 'issue_guard.dart';
import 'master_picker.dart';
import 'order_details_dialog.dart';
import 'works_progress_bar.dart';

class WorkshopsScreen extends StatefulWidget {
  final String selectedWorkshop;
  const WorkshopsScreen({super.key, required this.selectedWorkshop});

  @override
  State<WorkshopsScreen> createState() => _WorkshopsScreenState();
}

class _WorkshopsScreenState extends State<WorkshopsScreen> {
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _masters = [];
  /// orderId → имена мастеров цеха
  Map<int, String> _workshopMasters = {};
  bool _isLoading = true;

  @override
  void didUpdateWidget(covariant WorkshopsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedWorkshop != oldWidget.selectedWorkshop) {
      _loadOrders(widget.selectedWorkshop);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadOrders(widget.selectedWorkshop);
  }

  Future<void> _openMoveDialog(Map<String, dynamic> order) async {
    String? newStatus = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text("Куда переводим заказ?", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 300,
          child: ListView(
            shrinkWrap: true,
            children: STATUSES.map((s) {
              final isCurrent = s == order['status'];
              return ListTile(
                title: Text(
                  s,
                  style: GoogleFonts.manrope(
                    color: isCurrent ? AppColors.primary : AppColors.text,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                onTap: () => Navigator.pop(context, s),
              );
            }).toList(),
          ),
        ),
      ),
    );

    if (newStatus != null) {
      final workshop = widget.selectedWorkshop;
      final moved = newStatus != order['status'];
      final eventText = moved
          ? 'Цех «$workshop»: готово → $newStatus'
          : 'Цех «$workshop»: готово';

      if (!mounted) return;
      final ok = await tryUpdateOrderStatus(
        context,
        order['id'] as int,
        newStatus,
      );
      if (!ok) return;

      await DatabaseHelper().addOrderEvent(order['id'], eventText);

      if (!moved) {
        await DatabaseHelper().setWorkshopTaskCompleted(order['id'] as int, 1);
      } else {
        await DatabaseHelper().setWorkshopTaskCompleted(order['id'] as int, 0);
      }

      if (mounted) {
        final client = order['client_name']?.toString() ?? '';
        final car = "${order['make_model'] ?? ''} · ${order['plate'] ?? ''}".trim();
        final toast = moved
            ? "$client\n$car\nЦех «$workshop» → $newStatus"
            : "$client\n$car\nЦех «$workshop»: готово";
        showAppToast(context, toast);
      }

      _loadOrders(widget.selectedWorkshop);
    }
  }

  Future<void> _loadOrders(String workshop) async {
    setState(() => _isLoading = true);
    final allOrders = await DatabaseHelper().getAllOrders();
    final masters = await DatabaseHelper().getAllMastersFull();
    final filtered = allOrders.where((o) => o['status'] == workshop).toList();
    final names = <int, String>{};
    for (final o in filtered) {
      final id = (o['id'] as num).toInt();
      names[id] = await DatabaseHelper().getWorkshopMasterNames(id, workshop);
    }
    if (!mounted) return;
    setState(() {
      _orders = filtered;
      _masters = masters;
      _workshopMasters = names;
      _isLoading = false;
    });
  }

  Future<void> _assignWorkshopMasters(Map<String, dynamic> order) async {
    final orderId = (order['id'] as num).toInt();
    final workshop = widget.selectedWorkshop;

    // Текущие id — из первой работы цеха (все должны совпадать после назначения)
    final items = await DatabaseHelper().getOrderItems(orderId);
    final idSet = <int>{};
    for (final item in items) {
      final raw = (item['workshop'] as String?)?.trim() ?? '';
      String resolved = raw;
      if (resolved.isEmpty || !WORKSHOPS.contains(resolved)) {
        resolved = workshopForService(name: item['name']?.toString()) ?? '';
      }
      if (resolved != workshop) continue;
      idSet.addAll(parseMasterIds(item['master_ids']));
    }

    if (!mounted) return;
    final picked = await pickWorkshopMasters(
      context,
      workshop: workshop,
      masters: _masters,
      initialIds: idSet.toList(),
    );
    if (picked == null) return;

    await DatabaseHelper().assignMastersToWorkshop(orderId, workshop, picked);
    final names = masterNamesFromIds(_masters, picked);
    final event = names.isEmpty
        ? 'Цех «$workshop»: сняты все мастера'
        : 'Цех «$workshop»: назначены $names';
    await DatabaseHelper().addOrderEvent(orderId, event);
    if (mounted) _loadOrders(workshop);
  }

  Widget _buildWorkshopCard(Map<String, dynamic> o) {
    final isDone = o['is_workshop_completed'] == 1;
    final orderId = (o['id'] as num).toInt();
    final workshopMasters = _workshopMasters[orderId] ?? '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () async {
          final shouldRefresh = await OrderDetailsDialog.open(
            context,
            o,
            workshop: widget.selectedWorkshop,
          );
          if (shouldRefresh == true) {
            _loadOrders(widget.selectedWorkshop);
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(
              color: isDone ? AppColors.success.withOpacity(0.45) : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: isDone ? AppColors.success : AppColors.primary,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radius)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isDone) ...[
                          const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            "${o['client_name'] ?? ''}",
                            style: GoogleFonts.manrope(
                              color: isDone ? AppColors.textMuted : AppColors.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          "${o['price']} ₽",
                          style: GoogleFonts.manrope(
                            color: AppColors.success,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ],
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
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            workshopMasters.isEmpty
                                ? "Мастер цеха не назначен"
                                : "Мастер: $workshopMasters",
                            style: GoogleFonts.manrope(
                              color: workshopMasters.isEmpty ? AppColors.textDim : AppColors.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: "Назначить мастера цеха",
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            workshopMasters.isEmpty ? Icons.person_add_alt_1 : Icons.groups,
                            color: workshopMasters.isEmpty ? AppColors.textDim : AppColors.primary,
                            size: 20,
                          ),
                          onPressed: () => _assignWorkshopMasters(o),
                        ),
                      ],
                    ),
                    if (o['notes'] != null && o['notes'].toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        "${o['notes']}",
                        style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, height: 1.25),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    WorksProgressBar.fromOrder(o, compact: true),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDone ? AppColors.surface : AppColors.primary,
                          foregroundColor: isDone ? AppColors.textMuted : Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        ),
                        onPressed: () => _openMoveDialog(o),
                        child: Text(isDone ? "Перевести" : "Готово", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(
              children: [
                Text("Цех", style: AppTheme.pageTitle),
                const SizedBox(width: 12),
                Text(
                  widget.selectedWorkshop,
                  style: GoogleFonts.manrope(
                    color: AppColors.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  "${_orders.length}",
                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _orders.isEmpty
                    ? Center(
                        child: Text(
                          "Нет заказов в этом цехе",
                          style: GoogleFonts.manrope(color: AppColors.textDim),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        itemCount: _orders.length,
                        itemBuilder: (context, index) => _buildWorkshopCard(_orders[index]),
                      ),
          ),
        ],
      ),
    );
  }
}
