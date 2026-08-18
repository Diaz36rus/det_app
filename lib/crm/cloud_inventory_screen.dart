import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_theme.dart';
import 'crm_api.dart';
import 'crm_models.dart';

class CloudInventoryScreen extends StatefulWidget {
  const CloudInventoryScreen({super.key});

  @override
  State<CloudInventoryScreen> createState() => _CloudInventoryScreenState();
}

class _CloudInventoryScreenState extends State<CloudInventoryScreen> {
  final _api = CrmApi();
  List<CrmInventoryItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.listInventory();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final qty = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Позиция склада', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Название')),
            TextField(controller: qty, decoration: const InputDecoration(labelText: 'Кол-во'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Создать')),
        ],
      ),
    );
    if (ok != true) return;
    final n = name.text.trim();
    final q = double.tryParse(qty.text.replaceAll(',', '.')) ?? 0;
    name.dispose();
    qty.dispose();
    if (n.isEmpty) return;
    try {
      await _api.createInventory(name: n, quantity: q);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.danger));
    }
  }

  Future<void> _move(CrmInventoryItem item, double delta) async {
    try {
      await _api.inventoryMove(itemId: item.id, delta: delta, reason: delta >= 0 ? 'приход' : 'расход');
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppTheme.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Склад (облако)', style: AppTheme.pageTitle)),
              IconButton(onPressed: _loading ? null : _reload, icon: const Icon(Icons.refresh)),
              ElevatedButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 18), label: const Text('Добавить')),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(child: Center(child: Text(_error!, style: GoogleFonts.manrope(color: AppColors.danger))))
          else if (_items.isEmpty)
            Expanded(
              child: Center(
                child: Text('Склад пуст', style: GoogleFonts.manrope(color: AppColors.textMuted)),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final it = _items[i];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: AppTheme.cardDecoration,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(it.name, style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
                              Text('${it.category} · ${it.quantity} ${it.unit}',
                                  style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12)),
                            ],
                          ),
                        ),
                        IconButton(onPressed: () => _move(it, -1), icon: const Icon(Icons.remove_circle_outline)),
                        IconButton(onPressed: () => _move(it, 1), icon: const Icon(Icons.add_circle_outline)),
                      ],
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
