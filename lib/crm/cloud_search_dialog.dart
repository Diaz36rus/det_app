import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_theme.dart';
import 'crm_api.dart';
import 'crm_models.dart';

class CloudSearchDialog extends StatefulWidget {
  const CloudSearchDialog({super.key});

  @override
  State<CloudSearchDialog> createState() => _CloudSearchDialogState();
}

class _CloudSearchDialogState extends State<CloudSearchDialog> {
  final _api = CrmApi();
  final _ctrl = TextEditingController();
  List<CrmClient> _clients = [];
  List<CrmOrder> _orders = [];
  bool _loading = false;
  String? _error;
  bool _ready = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _ensureLoaded() async {
    if (_ready) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await _api.listClients();
      final o = await _api.listOrders();
      if (!mounted) return;
      setState(() {
        _clients = c;
        _orders = o;
        _ready = true;
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

  @override
  void initState() {
    super.initState();
    _ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final q = _ctrl.text.trim().toLowerCase();
    final clients = q.isEmpty
        ? const <CrmClient>[]
        : _clients
            .where((c) => c.name.toLowerCase().contains(q) || c.phone.toLowerCase().contains(q))
            .take(20)
            .toList();
    final orders = q.isEmpty
        ? const <CrmOrder>[]
        : _orders.where((o) {
            final id = '${o.id}';
            final name = (o.clientName ?? '').toLowerCase();
            final car = (o.carLabel ?? '').toLowerCase();
            return id.contains(q) || name.contains(q) || car.contains(q);
          }).take(20).toList();

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Поиск', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Клиент, телефон, № заказа, авто',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Text(_error!, style: GoogleFonts.manrope(color: AppColors.danger, fontSize: 12)),
            Expanded(
              child: ListView(
                children: [
                  if (clients.isNotEmpty) ...[
                    Text('Клиенты', style: GoogleFonts.manrope(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                    ...clients.map(
                      (c) => ListTile(
                        dense: true,
                        title: Text(c.name),
                        subtitle: Text(c.phone),
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (orders.isNotEmpty) ...[
                    Text('Заказы', style: GoogleFonts.manrope(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                    ...orders.map(
                      (o) => ListTile(
                        dense: true,
                        title: Text('#${o.id} · ${o.clientName ?? ''}'),
                        subtitle: Text('${o.status} · ${o.carLabel ?? ''}'),
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                  if (q.isNotEmpty && clients.isEmpty && orders.isEmpty && !_loading)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Ничего не найдено', style: GoogleFonts.manrope(color: AppColors.textMuted)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
      ],
    );
  }
}
