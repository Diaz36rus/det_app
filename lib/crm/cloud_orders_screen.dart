import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_theme.dart';
import '../auth/auth_controller.dart';
import 'crm_api.dart';
import 'crm_models.dart';

/// Узкий экран C1: список облачных заказов + быстрое создание.
class CloudOrdersScreen extends StatefulWidget {
  const CloudOrdersScreen({super.key});

  @override
  State<CloudOrdersScreen> createState() => _CloudOrdersScreenState();
}

class _CloudOrdersScreenState extends State<CloudOrdersScreen> {
  final _api = CrmApi();
  List<CrmOrder> _orders = [];
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
      final list = await _api.listOrders();
      if (!mounted) return;
      setState(() {
        _orders = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openCreate() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _CreateCloudOrderDialog(),
    );
    if (created == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthController.instance.user;
    return Padding(
      padding: AppTheme.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Облачные заказы', style: AppTheme.pageTitle),
                    const SizedBox(height: 4),
                    Text(
                      'Общий список на сервере (без LAN). '
                      '${user?.email ?? ''}',
                      style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Обновить',
                onPressed: _loading ? null : _reload,
                icon: const Icon(Icons.refresh, color: AppColors.textMuted),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _loading ? null : _openCreate,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Новый'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(color: AppColors.danger, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Для облака войдите как owner@demo.det-app.ru '
                        '(не platform admin).',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(onPressed: _reload, child: const Text('Повторить')),
                    ],
                  ),
                ),
              ),
            )
          else if (_orders.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'Пока нет облачных заказов.\nСоздайте первый — он появится на всех устройствах.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.4),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final o = _orders[i];
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: AppTheme.cardDecoration,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '#${o.id}  ${o.clientName ?? 'Клиент'}',
                                style: GoogleFonts.manrope(
                                  color: AppColors.text,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                o.carLabel ?? 'Авто',
                                style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
                              ),
                              if (o.items.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  o.items.map((e) => e.name).join(', '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              o.status,
                              style: GoogleFonts.manrope(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${o.price.toStringAsFixed(0)} ₽',
                              style: GoogleFonts.manrope(
                                color: AppColors.text,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
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

class _CreateCloudOrderDialog extends StatefulWidget {
  const _CreateCloudOrderDialog();

  @override
  State<_CreateCloudOrderDialog> createState() => _CreateCloudOrderDialogState();
}

class _CreateCloudOrderDialogState extends State<_CreateCloudOrderDialog> {
  final _api = CrmApi();
  final _clientName = TextEditingController();
  final _phone = TextEditingController();
  final _car = TextEditingController();
  final _plate = TextEditingController();
  final _work = TextEditingController(text: 'Мойка кузова');
  final _price = TextEditingController(text: '3000');
  bool _busy = false;

  @override
  void dispose() {
    _clientName.dispose();
    _phone.dispose();
    _car.dispose();
    _plate.dispose();
    _work.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = _clientName.text.trim();
    final make = _car.text.trim();
    final work = _work.text.trim();
    final price = double.tryParse(_price.text.replaceAll(',', '.').trim()) ?? 0;
    if (name.isEmpty || make.isEmpty || work.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Заполните клиента, авто и работу', style: GoogleFonts.manrope())),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final client = await _api.createClient(name: name, phone: _phone.text.trim());
      final car = await _api.createCar(
        clientId: client.id,
        makeModel: make,
        plate: _plate.text.trim(),
      );
      await _api.createOrder(
        clientId: client.id,
        carId: car.id,
        items: [CrmOrderItem(name: work, price: price, workshop: 'Мойка')],
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e', style: GoogleFonts.manrope()),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Новый облачный заказ', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _clientName,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Клиент'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Телефон'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _car,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Авто (марка/модель)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _plate,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Номер'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _work,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Работа'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _price,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Цена'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Создать'),
        ),
      ],
    );
  }
}
