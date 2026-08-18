import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_theme.dart';
import 'crm_api.dart';
import 'crm_models.dart';

class CloudStaffScreen extends StatefulWidget {
  const CloudStaffScreen({super.key});

  @override
  State<CloudStaffScreen> createState() => _CloudStaffScreenState();
}

class _CloudStaffScreenState extends State<CloudStaffScreen> {
  final _api = CrmApi();
  List<CrmMaster> _items = [];
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
      final list = await _api.listMasters();
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
    final role = TextEditingController(text: 'Универсал');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Сотрудник', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Имя')),
            TextField(controller: role, decoration: const InputDecoration(labelText: 'Роль / цех')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Создать')),
        ],
      ),
    );
    final n = name.text.trim();
    final r = role.text.trim();
    name.dispose();
    role.dispose();
    if (ok != true || n.isEmpty) return;
    try {
      await _api.createMaster(name: n, role: r.isEmpty ? 'Универсал' : r);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.danger));
    }
  }

  Future<void> _edit(CrmMaster m) async {
    final name = TextEditingController(text: m.name);
    final role = TextEditingController(text: m.role);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Сотрудник', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Имя')),
            TextField(controller: role, decoration: const InputDecoration(labelText: 'Роль / цех')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Активен'),
              value: m.isActive,
              onChanged: null,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx, false);
              try {
                await _api.patchMaster(m.id, {'is_active': !m.isActive});
                await _reload();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.danger));
              }
            },
            child: Text(m.isActive ? 'Деактивировать' : 'Активировать'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    final n = name.text.trim();
    final r = role.text.trim();
    name.dispose();
    role.dispose();
    if (ok != true || n.isEmpty) return;
    try {
      await _api.patchMaster(m.id, {'name': n, 'role': r});
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
              Expanded(child: Text('Сотрудники', style: AppTheme.pageTitle)),
              IconButton(onPressed: _reload, icon: const Icon(Icons.refresh, color: AppColors.textMuted)),
              ElevatedButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Добавить'),
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
              final m = _items[i];
              return ListTile(
                tileColor: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: Text(m.name, style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                subtitle: Text(m.role, style: GoogleFonts.manrope(color: AppColors.textMuted)),
                trailing: Text(
                  m.isActive ? 'активен' : 'выкл',
                  style: GoogleFonts.manrope(
                    color: m.isActive ? AppColors.primary : AppColors.textDim,
                    fontSize: 12,
                  ),
                ),
                onTap: () => _edit(m),
              );
            },
          ),
        ),
      ],
    );
  }
}
