import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_theme.dart';
import '../auth/auth_controller.dart';
import '../crm/crm_api.dart';
import '../crm/crm_models.dart';
import 'cash_cloud_api.dart';
import 'cash_cloud_models.dart';

/// Узкий экран C2: облачная смена, журнал, операции и оплата облачных заказов.
class CloudCashScreen extends StatefulWidget {
  const CloudCashScreen({super.key});

  @override
  State<CloudCashScreen> createState() => _CloudCashScreenState();
}

class _CloudCashScreenState extends State<CloudCashScreen> {
  final _api = CashCloudApi();
  final _crm = CrmApi();

  CloudCashShift? _shift;
  List<CloudCashJournalEntry> _journal = [];
  List<CloudCashRegister> _registers = [];
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
      final regs = await _api.listRegisters();
      final shift = await _api.currentShift();
      final journal = await _api.journal();
      if (!mounted) return;
      setState(() {
        _registers = regs;
        _shift = shift;
        _journal = journal;
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

  Future<void> _openShift() async {
    try {
      await _api.openShift();
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _closeShift() async {
    final shift = _shift;
    if (shift == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Закрыть смену?', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: Text(
          'Смена #${shift.id} будет закрыта на всех устройствах.',
          style: GoogleFonts.manrope(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Закрыть')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.closeShift(shift.id);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _addFlow() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => _FlowDialog(registers: _registers),
    );
    if (created == true) await _reload();
  }

  Future<void> _payOrder() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => _PayOrderDialog(crm: _crm, cash: _api, registers: _registers),
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
                    Text('Облачная касса', style: AppTheme.pageTitle),
                    const SizedBox(height: 4),
                    Text(
                      'Смена и оплаты заказов на сервере. ${user?.email ?? ''}',
                      style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loading ? null : _reload,
                icon: const Icon(Icons.refresh, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildShiftBar(),
          const SizedBox(height: 12),
          if (_shift?.isOpen == true)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _addFlow,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Операция'),
                ),
                OutlinedButton.icon(
                  onPressed: _payOrder,
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Оплата заказа'),
                ),
              ],
            ),
          const SizedBox(height: 12),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(color: AppColors.danger, height: 1.4),
                ),
              ),
            )
          else if (_journal.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'Журнал пуст. Откройте смену и добавьте операцию или оплату.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(color: AppColors.textMuted),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _journal.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final e = _journal[i];
                  final isExpense = e.flowType == 'Расход';
                  final color = e.isVoided
                      ? AppColors.textDim
                      : (isExpense ? AppColors.danger : AppColors.success);
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
                                e.title,
                                style: GoogleFonts.manrope(
                                  color: e.isVoided ? AppColors.textDim : AppColors.text,
                                  fontWeight: FontWeight.w700,
                                  decoration: e.isVoided ? TextDecoration.lineThrough : null,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${e.kind == 'payment' ? 'Оплата' : (e.flowType ?? 'Операция')} · ${e.method}',
                                style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${isExpense ? '−' : '+'}${e.amount.toStringAsFixed(0)} ₽',
                          style: GoogleFonts.manrope(color: color, fontWeight: FontWeight.w800),
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

  Widget _buildShiftBar() {
    final open = _shift?.isOpen == true;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration,
      child: Row(
        children: [
          Icon(
            open ? Icons.lock_open : Icons.lock_outline,
            color: open ? AppColors.success : AppColors.textDim,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              open ? 'Смена #${_shift!.id} открыта' : 'Смена закрыта',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
            ),
          ),
          if (open)
            TextButton(onPressed: _closeShift, child: const Text('Закрыть'))
          else
            ElevatedButton(onPressed: _openShift, child: const Text('Открыть')),
        ],
      ),
    );
  }
}

class _FlowDialog extends StatefulWidget {
  const _FlowDialog({required this.registers});
  final List<CloudCashRegister> registers;

  @override
  State<_FlowDialog> createState() => _FlowDialogState();
}

class _FlowDialogState extends State<_FlowDialog> {
  final _api = CashCloudApi();
  final _amount = TextEditingController();
  final _desc = TextEditingController();
  String _type = 'Приход';
  String _method = 'Наличные';
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '.').trim()) ?? 0;
    if (amount <= 0) return;
    setState(() => _busy = true);
    try {
      await _api.createFlow(
        type: _type,
        amount: amount,
        method: _method,
        description: _desc.text.trim().isEmpty ? _type : _desc.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final methods = widget.registers.where((r) => r.isActive).map((r) => r.moneyType).toSet().toList();
    if (methods.isEmpty) methods.addAll(const ['Наличные', 'Карта', 'Перевод', 'Счёт']);
    if (!methods.contains(_method)) _method = methods.first;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Операция', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _type,
              items: const [
                DropdownMenuItem(value: 'Приход', child: Text('Приход')),
                DropdownMenuItem(value: 'Расход', child: Text('Расход')),
              ],
              onChanged: _busy ? null : (v) => setState(() => _type = v ?? 'Приход'),
              decoration: const InputDecoration(labelText: 'Тип'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _method,
              items: methods.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: _busy ? null : (v) => setState(() => _method = v ?? 'Наличные'),
              decoration: const InputDecoration(labelText: 'Метод'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Сумма'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _desc,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Описание'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Отмена')),
        ElevatedButton(onPressed: _busy ? null : _submit, child: const Text('Сохранить')),
      ],
    );
  }
}

class _PayOrderDialog extends StatefulWidget {
  const _PayOrderDialog({
    required this.crm,
    required this.cash,
    required this.registers,
  });

  final CrmApi crm;
  final CashCloudApi cash;
  final List<CloudCashRegister> registers;

  @override
  State<_PayOrderDialog> createState() => _PayOrderDialogState();
}

class _PayOrderDialogState extends State<_PayOrderDialog> {
  List<CrmOrder> _orders = [];
  CrmOrder? _selected;
  final _amount = TextEditingController();
  String _method = 'Наличные';
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final all = await widget.crm.listOrders();
      final debts = all.where((o) => o.price - o.paidAmount > 0.01).toList();
      if (!mounted) return;
      setState(() {
        _orders = debts;
        _loading = false;
        if (debts.isNotEmpty) {
          _selected = debts.first;
          _amount.text = (debts.first.price - debts.first.paidAmount).toStringAsFixed(0);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final order = _selected;
    final amount = double.tryParse(_amount.text.replaceAll(',', '.').trim()) ?? 0;
    if (order == null || amount <= 0) return;
    setState(() => _busy = true);
    try {
      await widget.cash.createPayment(orderId: order.id, amount: amount, method: _method);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final methods = widget.registers.where((r) => r.isActive).map((r) => r.moneyType).toSet().toList();
    if (methods.isEmpty) methods.addAll(const ['Наличные', 'Карта']);
    if (!methods.contains(_method)) _method = methods.first;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Оплата облачного заказа', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 400,
        child: _loading
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : _error != null
                ? Text(_error!, style: GoogleFonts.manrope(color: AppColors.danger))
                : _orders.isEmpty
                    ? Text(
                        'Нет облачных заказов с долгом. Создайте заказ в «Облачные заказы».',
                        style: GoogleFonts.manrope(color: AppColors.textMuted),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButtonFormField<CrmOrder>(
                            value: _selected,
                            items: _orders
                                .map(
                                  (o) => DropdownMenuItem(
                                    value: o,
                                    child: Text(
                                      '#${o.id} ${o.clientName ?? ''} · долг ${(o.price - o.paidAmount).toStringAsFixed(0)}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _busy
                                ? null
                                : (o) {
                                    setState(() {
                                      _selected = o;
                                      if (o != null) {
                                        _amount.text = (o.price - o.paidAmount).toStringAsFixed(0);
                                      }
                                    });
                                  },
                            decoration: const InputDecoration(labelText: 'Заказ'),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: _method,
                            items: methods.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                            onChanged: _busy ? null : (v) => setState(() => _method = v ?? 'Наличные'),
                            decoration: const InputDecoration(labelText: 'Метод'),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _amount,
                            enabled: !_busy,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Сумма'),
                          ),
                        ],
                      ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: _busy || _orders.isEmpty ? null : _submit,
          child: const Text('Оплатить'),
        ),
      ],
    );
  }
}
