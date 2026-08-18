import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_theme.dart';
import 'crm_api.dart';
import 'crm_models.dart';

class CloudServicesScreen extends StatefulWidget {
  const CloudServicesScreen({super.key});

  @override
  State<CloudServicesScreen> createState() => _CloudServicesScreenState();
}

class _CloudServicesScreenState extends State<CloudServicesScreen> {
  final _api = CrmApi();
  List<CrmService> _items = [];
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
      final list = await _api.listServices();
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
    final cat = TextEditingController(text: 'Прочее');
    final price = TextEditingController(text: '0');
    final ws = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Услуга', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Название')),
              TextField(controller: cat, decoration: const InputDecoration(labelText: 'Категория')),
              TextField(
                controller: price,
                decoration: const InputDecoration(labelText: 'Цена'),
                keyboardType: TextInputType.number,
              ),
              TextField(controller: ws, decoration: const InputDecoration(labelText: 'Цех')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Создать')),
        ],
      ),
    );
    final n = name.text.trim();
    final c = cat.text.trim();
    final p = double.tryParse(price.text.replaceAll(',', '.')) ?? 0;
    final w = ws.text.trim();
    name.dispose();
    cat.dispose();
    price.dispose();
    ws.dispose();
    if (ok != true || n.isEmpty) return;
    try {
      await _api.createService(name: n, category: c.isEmpty ? 'Прочее' : c, price: p, workshop: w);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.danger));
    }
  }

  Future<void> _edit(CrmService s) async {
    final name = TextEditingController(text: s.name);
    final cat = TextEditingController(text: s.category);
    final price = TextEditingController(text: s.price.toStringAsFixed(0));
    final ws = TextEditingController(text: s.workshop);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Прайс', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Название')),
              TextField(controller: cat, decoration: const InputDecoration(labelText: 'Категория')),
              TextField(
                controller: price,
                decoration: const InputDecoration(labelText: 'Цена'),
                keyboardType: TextInputType.number,
              ),
              TextField(controller: ws, decoration: const InputDecoration(labelText: 'Цех')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx, false);
              try {
                await _api.patchService(s.id, {'is_active': !s.isActive});
                await _reload();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.danger));
              }
            },
            child: Text(s.isActive ? 'Выкл' : 'Вкл'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    final n = name.text.trim();
    final c = cat.text.trim();
    final p = double.tryParse(price.text.replaceAll(',', '.')) ?? s.price;
    final w = ws.text.trim();
    name.dispose();
    cat.dispose();
    price.dispose();
    ws.dispose();
    if (ok != true || n.isEmpty) return;
    try {
      await _api.patchService(s.id, {
        'name': n,
        'category': c,
        'price': p,
        'workshop': w,
      });
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: GoogleFonts.manrope(color: AppColors.danger)),
            OutlinedButton(onPressed: _reload, child: const Text('Повторить')),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(
            children: [
              Expanded(child: Text('Прайс', style: AppTheme.pageTitle)),
              IconButton(onPressed: _reload, icon: const Icon(Icons.refresh, color: AppColors.textMuted)),
              ElevatedButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Услуга'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final s = _items[i];
              return ListTile(
                tileColor: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: Text(s.name, style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${s.category}${s.workshop.isEmpty ? '' : ' · ${s.workshop}'}'
                  '${s.isActive ? '' : ' · выкл'}',
                  style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12),
                ),
                trailing: Text(
                  s.price.toStringAsFixed(0),
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                ),
                onTap: () => _edit(s),
              );
            },
          ),
        ),
      ],
    );
  }
}
