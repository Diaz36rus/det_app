import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'database.dart';
import 'order_details_dialog.dart';

class CompletedOrdersScreen extends StatefulWidget {
  const CompletedOrdersScreen({super.key});

  @override
  State<CompletedOrdersScreen> createState() => _CompletedOrdersScreenState();
}

class _CompletedOrdersScreenState extends State<CompletedOrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  final _money = NumberFormat('#,##0.##', 'ru_RU');

  @override
  void initState() {
    super.initState();
    _load("");
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    setState(() => _isLoading = true);
    final orders = await DatabaseHelper().getCompletedOrders(query);
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _isLoading = false;
    });
  }

  Future<void> _openOrder(Map<String, dynamic> order) async {
    final full = await DatabaseHelper().getOrderById(order['id'] as int);
    if (full == null || !mounted) return;
    await OrderDetailsDialog.open(context, full);
    _load(_searchController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Row(
              children: [
                Text("Завершённые", style: AppTheme.pageTitle),
                const Spacer(),
                Text(
                  "${_orders.length}",
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
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
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
                  hintText: "Клиент, телефон, номер, VIN, № заказа…",
                  prefixIcon: Icon(Icons.search, color: AppColors.textMuted, size: 20),
                  isDense: true,
                ),
                onChanged: _load,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _orders.isEmpty
                    ? Center(
                        child: Text(
                          "Нет завершённых заказов",
                          style: GoogleFonts.manrope(color: AppColors.textDim),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        itemCount: _orders.length,
                        itemBuilder: (context, index) {
                          final o = _orders[index];
                          final price = (o['price'] as num?)?.toDouble() ?? 0;
                          return InkWell(
                            onTap: () => _openOrder(o),
                            borderRadius: BorderRadius.circular(AppTheme.radius),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.surface2,
                                borderRadius: BorderRadius.circular(AppTheme.radius),
                                border: Border.all(color: AppColors.border),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  Container(
                                    height: 3,
                                    width: double.infinity,
                                    color: AppColors.success,
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "#${o['id']} · ${o['client_name'] ?? ''}",
                                              style: GoogleFonts.manrope(
                                                color: AppColors.text,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "${o['make_model'] ?? ''} · ${o['plate'] ?? ''}",
                                              style: GoogleFonts.manrope(
                                                color: AppColors.textMuted,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "${o['created_at'] ?? ''} · ${o['status'] ?? 'Выдан'}",
                                              style: GoogleFonts.manrope(
                                                color: AppColors.textDim,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        "${_money.format(price)} ₽",
                                        style: GoogleFonts.manrope(
                                          color: AppColors.success,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if ((o['notes']?.toString() ?? "").isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        o['notes'].toString(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.manrope(
                                          color: AppColors.textDim,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
