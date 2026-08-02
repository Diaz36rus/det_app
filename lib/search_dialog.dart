import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'database.dart';
import 'order_details_dialog.dart';

class SearchDialog extends StatefulWidget {
  const SearchDialog({super.key});

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _orders = [];
  bool _searched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _doSearch(String q) async {
    if (q.length < 2) {
      setState(() {
        _searched = false;
        _clients.clear();
        _orders.clear();
      });
      return;
    }
    final res = await DatabaseHelper().searchGlobal(q);
    if (!mounted) return;
    setState(() {
      _clients = res["clients"]!;
      _orders = res["orders"]!;
      _searched = true;
    });
  }

  Future<void> _openOrder(int orderId) async {
    final fullOrder = await DatabaseHelper().getOrderById(orderId);
    if (fullOrder == null || !mounted) return;
    await OrderDetailsDialog.open(context, fullOrder);
    if (_controller.text.length >= 2) _doSearch(_controller.text);
  }

  Future<void> _openClient(Map<String, dynamic> client) async {
    final cars = await DatabaseHelper().getClientCars(client['id'] as int);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          "${client['name']} · ${client['phone']}",
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: 400,
          child: cars.isEmpty
              ? Text("Нет автомобилей в базе", style: GoogleFonts.manrope(color: AppColors.textDim))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Автомобили",
                      style: GoogleFonts.manrope(color: AppColors.textMuted, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    ...cars.map(
                      (car) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.directions_car_outlined, color: AppColors.primary),
                        title: Text(
                          "${car['make_model']} · ${car['plate']}",
                          style: GoogleFonts.manrope(color: AppColors.text, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          "VIN: ${car['vin'] ?? ''} · класс ${car['category'] ?? '1'}",
                          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Закрыть"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 640,
        height: 520,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Text("Поиск", style: AppTheme.sectionTitle),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Клиент, авто или заказ…',
                prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.textDim),
                        onPressed: () {
                          setState(() {
                            _controller.clear();
                            _clients.clear();
                            _orders.clear();
                            _searched = false;
                          });
                        },
                      )
                    : null,
                isDense: true,
              ),
              onChanged: (v) {
                setState(() {});
                _doSearch(v);
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: !_searched
                  ? Center(
                      child: Text(
                        "Введите минимум 2 символа",
                        style: GoogleFonts.manrope(color: AppColors.textDim),
                      ),
                    )
                  : ListView(
                      children: [
                        if (_clients.isNotEmpty) ...[
                          Text(
                            "Клиенты",
                            style: GoogleFonts.manrope(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ..._clients.map(
                            (c) => Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: AppColors.surface2,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: ListTile(
                                leading: const Icon(Icons.person_outline, color: AppColors.primary),
                                title: Text(
                                  "${c['name']} · ${c['phone']}",
                                  style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
                                ),
                                onTap: () => _openClient(c),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_orders.isNotEmpty) ...[
                          Text(
                            "Заказы",
                            style: GoogleFonts.manrope(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ..._orders.map(
                            (o) => Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: AppColors.surface2,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: ListTile(
                                leading: const Icon(Icons.receipt_long_outlined, color: AppColors.primary),
                                title: Text(
                                  "Заказ #${o['id']} · ${o['name']}",
                                  style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  "${o['make_model']} · ${o['status']}",
                                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                                ),
                                onTap: () => _openOrder(o['id'] as int),
                              ),
                            ),
                          ),
                        ],
                        if (_clients.isEmpty && _orders.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                "Ничего не найдено",
                                style: GoogleFonts.manrope(color: AppColors.textDim),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
