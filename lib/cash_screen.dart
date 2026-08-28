import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_datetime.dart';
import 'app_theme.dart';
import 'app_toast.dart';
import 'cash_catalog.dart';
import 'cash_csv_export.dart';
import 'cash_operation_dialog.dart';
import 'cash_register_tx_dialog.dart';
import 'cash_shift_panel.dart';
import 'database.dart';
import 'db_refresh_mixin.dart';
import 'debt_reminder.dart';
import 'order_details_dialog.dart';
import 'payment_edit_dialog.dart';
import 'pulse_anchor.dart';
import 'quick_payment_dialog.dart';
import 'responsive.dart';
import 'tour_keys.dart';

class CashScreen extends StatefulWidget {
  const CashScreen({super.key});

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> with DbRefreshMixin, PulseHighlightMixin {
  @override
  void onDatabaseChanged() => _loadData();
  String _period = 'today';
  String _startDate = '';
  String _endDate = '';
  List<Map<String, dynamic>> _journal = [];
  Map<String, dynamic>? _shift;
  double _debtTotal = 0;
  List<Map<String, dynamic>> _registerSnapshots = [];
  int? _selectedRegisterId;

  static const _pulseOp = 'cash_op';
  static const _pulseTemplates = 'cash_templates';
  static const _pulseJournal = 'cash_journal';
  static const _pulseDebts = 'cash_debts';

  double _cashSum = 0;
  double _cardSum = 0;
  double _transferSum = 0;
  double _invoiceSum = 0;
  double _expenseSum = 0;

  String _filterSource = 'all'; // all | payment | flow
  String _filterType = 'all'; // all | Приход | Расход
  String? _filterMethod;

  bool _isLoading = true;
  DateTime? _loadedAt;
  int _paymentsShown = 8;
  final _money = NumberFormat('#,##0.##', 'ru_RU');
  final _shiftPanelKey = GlobalKey<CashShiftPanelState>();

  static const _refundTemplate = CashTemplate(
    key: 'refund',
    label: 'Возврат',
    type: 'Расход',
    category: 'Прочее',
    method: CashMethods.cash,
    defaultDescription: 'Возврат клиенту',
  );

  @override
  void initState() {
    super.initState();
    _setPeriod('today');
  }

  Future<void> _setPeriod(String type) async {
    final now = DateTime.now();
    setState(() {
      _period = type;
      _isLoading = true;
    });
    if (type == 'today') {
      _startDate = _endDate = DateFormat('yyyy-MM-dd').format(now);
    } else if (type == 'week') {
      _startDate = DateFormat('yyyy-MM-dd').format(now.subtract(Duration(days: now.weekday - 1)));
      _endDate = DateFormat('yyyy-MM-dd').format(now);
    } else if (type == 'month') {
      _startDate = DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month, 1));
      _endDate = DateFormat('yyyy-MM-dd').format(now);
    }
    await _loadData();
  }

  Future<void> _pickCustomRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(2035),
      initialDateRange: DateTimeRange(
        start: DateTime.tryParse(_startDate) ?? DateTime.now(),
        end: DateTime.tryParse(_endDate) ?? DateTime.now(),
      ),
      locale: const Locale('ru', 'RU'),
    );
    if (range == null) return;
    setState(() {
      _period = 'custom';
      _startDate = DateFormat('yyyy-MM-dd').format(range.start);
      _endDate = DateFormat('yyyy-MM-dd').format(range.end);
      _isLoading = true;
    });
    await _loadData();
  }

  Future<void> _loadData() async {
    final journal = await DatabaseHelper().getCashJournal(_startDate, _endDate);
    final shift = await DatabaseHelper().getCurrentShift();
    List<Map<String, dynamic>> snaps;
    if (shift != null) {
      final sid = (shift['id'] as num).toInt();
      snaps = await DatabaseHelper().getShiftRegisterSnapshots(sid);
    } else {
      final regs = await DatabaseHelper().getCashRegisters();
      snaps = regs
          .map((r) => {
                ...r,
                'opening': 0.0,
                'expected': 0.0,
              })
          .toList();
    }
    final debt = await DatabaseHelper().getTotalDebt();

    double cash = 0, card = 0, transfer = 0, invoice = 0, expense = 0;
    for (final row in journal) {
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      final type = row['type']?.toString() ?? '';
      final method = row['method']?.toString() ?? '';

      if (type == 'Расход') {
        expense += amount;
        continue;
      }
      switch (method) {
        case CashMethods.cash:
          cash += amount;
          break;
        case CashMethods.card:
          card += amount;
          break;
        case CashMethods.transfer:
          transfer += amount;
          break;
        case CashMethods.invoice:
          invoice += amount;
          break;
        default:
          // «Не указан» и прочее — не кладём в «Карта»
          break;
      }
    }

    if (!mounted) return;
    setState(() {
      _journal = journal;
      _shift = shift;
      _registerSnapshots = snaps;
      if (_selectedRegisterId != null &&
          !snaps.any((s) => (s['id'] as num).toInt() == _selectedRegisterId)) {
        _selectedRegisterId = snaps.isEmpty ? null : (snaps.first['id'] as num).toInt();
      }
      _selectedRegisterId ??= snaps.isEmpty ? null : (snaps.first['id'] as num).toInt();
      _debtTotal = debt;
      _cashSum = cash;
      _cardSum = card;
      _transferSum = transfer;
      _invoiceSum = invoice;
      _expenseSum = expense;
      _isLoading = false;
      _loadedAt = DateTime.now();
    });
  }

  double get _registerBalance {
    var sum = 0.0;
    for (final s in _registerSnapshots) {
      sum += (s['expected'] as num?)?.toDouble() ?? (s['opening'] as num?)?.toDouble() ?? 0;
    }
    return sum;
  }

  double get _cashOnHand {
    var sum = 0.0;
    for (final s in _registerSnapshots) {
      if (s['money_type']?.toString() != CashMethods.cash) continue;
      sum += (s['expected'] as num?)?.toDouble() ?? (s['opening'] as num?)?.toDouble() ?? 0;
    }
    return sum;
  }

  List<Map<String, dynamic>> get _recentPayments {
    final payments = _journal.where((r) => r['source']?.toString() == 'payment').toList();
    final src = payments.isNotEmpty ? payments : _journal;
    return src.take(_paymentsShown).toList();
  }

  int get _incomeCount =>
      _journal.where((r) => r['type']?.toString() == 'Приход').length;

  String get _updatedLabel {
    final t = _loadedAt;
    if (t == null) return 'Обновлено только что';
    final min = DateTime.now().difference(t).inMinutes;
    if (min <= 0) return 'Обновлено только что';
    if (min == 1) return 'Обновлено 1 мин назад';
    return 'Обновлено $min мин назад';
  }

  double get _totalIncome => _cashSum + _cardSum + _transferSum + _invoiceSum;

  List<Map<String, dynamic>> get _filteredJournal {
    return _journal.where((row) {
      final source = row['source']?.toString() ?? '';
      final type = row['type']?.toString() ?? '';
      final method = row['method']?.toString() ?? '';
      if (_filterSource == 'payment' && source != 'payment') return false;
      if (_filterSource == 'flow' && source != 'flow') return false;
      if (_filterType != 'all' && type != _filterType) return false;
      if (_filterMethod != null && method != _filterMethod) return false;
      return true;
    }).toList();
  }

  String _fmtDt(String? raw) => AppDateTime.formatShort(raw);

  Future<void> _openOp({CashTemplate? template, int? editFlowId}) async {
    final pulseId = editFlowId != null
        ? _pulseJournal
        : (template != null ? _pulseTemplates : _pulseOp);
    final ok = await runWithPulseHighlight(
      pulseId,
      () => CashOperationDialog.open(
        context,
        template: template,
        registerId: _selectedRegisterId,
        editFlowId: editFlowId,
      ),
    );
    if (ok == true) _loadData();
  }

  Future<void> _openOrder(int orderId) async {
    final order = await DatabaseHelper().getOrderById(orderId);
    if (order == null || !mounted) return;
    final refreshed = await OrderDetailsDialog.open(context, order);
    if (refreshed == true) _loadData();
  }

  String _registerPeriodStart() {
    final opened = _shift?['opened_at']?.toString() ?? '';
    if (opened.length >= 10) return opened.substring(0, 10);
    return _startDate;
  }

  Future<void> _openRegisterTx(Map<String, dynamic> snap) async {
    final rid = (snap['id'] as num).toInt();
    setState(() => _selectedRegisterId = rid);
    final changed = await runWithPulseHighlight(
      rid,
      () => CashRegisterTxDialog.open(
        context,
        registerId: rid,
        registerName: snap['name']?.toString() ?? 'Касса',
        moneyType: snap['money_type']?.toString() ?? '',
        expected: (snap['expected'] as num?)?.toDouble() ??
            (snap['opening'] as num?)?.toDouble() ??
            0,
        startDate: _registerPeriodStart(),
        endDate: _endDate,
      ),
    );
    if (changed == true) _loadData();
  }

  int? get _pulsingRegisterId {
    final id = pulseHighlightId;
    return id is int ? id : null;
  }

  Future<void> _editJournalRow(Map<String, dynamic> row) async {
    final source = row['source']?.toString() ?? '';
    final id = (row['id'] as num?)?.toInt();
    if (id == null) return;

    if (source == 'flow') {
      await _openOp(editFlowId: id);
      return;
    }
    if (source == 'payment') {
      final result = await runWithPulseHighlight(
        _pulseJournal,
        () => PaymentEditDialog.open(
          context,
          paymentId: id,
          amount: (row['amount'] as num?)?.toDouble() ?? 0,
          method: row['method']?.toString() ?? '',
          registerId: (row['register_id'] as num?)?.toInt(),
          orderId: (row['order_id'] as num?)?.toInt(),
          title: row['title']?.toString() ?? 'Оплата',
        ),
      );
      if (result == 'saved' || result == 'voided') {
        _loadData();
      } else if (result == 'order') {
        final oid = (row['order_id'] as num?)?.toInt();
        if (oid != null) await _openOrder(oid);
      }
    }
  }

  Future<void> _deleteJournalRow(Map<String, dynamic> row) async {
    final source = row['source']?.toString() ?? '';
    final id = (row['id'] as num?)?.toInt();
    if (id == null) return;

    final confirm = await runWithPulseHighlight(
      _pulseJournal,
      () => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            source == 'payment' ? 'Отменить оплату?' : 'Удалить операцию?',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
          ),
          content: Text(
            source == 'payment'
                ? 'Платёж будет удалён, сумма в заказе пересчитается.'
                : 'Операция будет удалена безвозвратно.',
            style: GoogleFonts.manrope(color: AppColors.textMuted),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger.withOpacity(0.9)),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(source == 'payment' ? 'Отменить' : 'Удалить'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    if (source == 'flow') {
      await DatabaseHelper().deleteCashFlow(id);
    } else {
      await DatabaseHelper().voidPayment(id);
    }
    _loadData();
  }

  Future<void> _exportCsv() async {
    if (_journal.isEmpty) {
      if (!mounted) return;
      showAppToast(context, 'Нет операций за период');
      return;
    }
    try {
      final path = await CashCsvExport.writeAndOpen(
        journal: _filteredJournal,
        startDate: _startDate,
        endDate: _endDate,
      );
      if (!mounted) return;
      if (path == null) {
        showAppToast(context, 'Не удалось сохранить CSV');
      } else {
        showAppToast(context, 'CSV сохранён и открыт');
      }
    } catch (e) {
      if (mounted) showAppToast(context, 'Ошибка CSV: $e');
    }
  }

  Future<void> _showDebts() async {
    var debts = await DatabaseHelper().getOrderDebts();
    if (!mounted) return;

    Future<void> remind(Map<String, dynamic> d, {required bool whatsapp}) async {
      final id = (d['id'] as num).toInt();
      final debt = (d['debt'] as num?)?.toDouble() ?? 0;
      final text = await DebtReminder.buildTextAsync(
        clientName: d['client_name']?.toString() ?? '',
        orderId: id,
        debt: debt,
        plate: d['plate']?.toString(),
        car: d['make_model']?.toString(),
      );
      if (whatsapp) {
        final r = await DebtReminder.share(
          phone: d['client_phone']?.toString(),
          text: text,
        );
        if (!mounted) return;
        if (r == 'opened') {
          showAppToast(context, 'Открыт WhatsApp');
        } else if (r == 'copied_link') {
          showAppToast(context, 'Ссылка WhatsApp скопирована');
        } else if (r == 'no_phone') {
          showAppToast(context, 'Нет телефона — текст скопирован');
        } else {
          showAppToast(context, 'Текст скопирован');
        }
      } else {
        await DebtReminder.copyText(text);
        if (mounted) showAppToast(context, 'Текст напоминания скопирован');
      }
    }

    await runWithPulseHighlight(
      _pulseDebts,
      () => showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('Долги по заказам', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
            content: SizedBox(
              width: AppResponsive.dialogWidth(ctx, desktop: 520),
              height: AppResponsive.isMobile(ctx) ? MediaQuery.sizeOf(ctx).height * 0.55 : 440,
              child: debts.isEmpty
                  ? Center(child: Text('Долгов нет', style: GoogleFonts.manrope(color: AppColors.textDim)))
                  : ListView.separated(
                      itemCount: debts.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                      itemBuilder: (_, i) {
                        final d = debts[i];
                        final id = (d['id'] as num).toInt();
                        final debt = (d['debt'] as num?)?.toDouble() ?? 0;
                        return ListTile(
                          dense: true,
                          title: Text(
                            '#$id · ${d['client_name']}',
                            style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          subtitle: Text(
                            '${d['make_model']} · ${d['plate']}',
                            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${_money.format(debt)} ₽',
                                style: GoogleFonts.manrope(
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                tooltip: 'Скопировать текст',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.copy_outlined, size: 18),
                                onPressed: () => remind(d, whatsapp: false),
                              ),
                              IconButton(
                                tooltip: 'WhatsApp',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.chat_outlined, size: 18, color: AppColors.success),
                                onPressed: () => remind(d, whatsapp: true),
                              ),
                              IconButton(
                                tooltip: 'Оплатить',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.payments_outlined, size: 18, color: AppColors.primary),
                                onPressed: () async {
                                  final paid = await QuickPaymentDialog.open(
                                    context,
                                    orderId: id,
                                  );
                                  if (paid == true) {
                                    debts = await DatabaseHelper().getOrderDebts();
                                    setLocal(() {});
                                    _loadData();
                                  }
                                },
                              ),
                            ],
                          ),
                          onTap: () async {
                            Navigator.pop(ctx);
                            await _openOrder(id);
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _periodChip(String id, String label) {
    final active = _period == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          label,
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: active ? AppColors.text : AppColors.textMuted,
          ),
        ),
        selected: active,
        onSelected: (_) => id == 'custom' ? _pickCustomRange() : _setPeriod(id),
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.surface2,
        side: BorderSide(color: active ? AppColors.primary : AppColors.border),
        showCheckmark: false,
      ),
    );
  }

  Widget _shiftHost() {
    return CashShiftPanel(
      key: _shiftPanelKey,
      headless: true,
      shift: _shift,
      registerSnapshots: _registerSnapshots,
      selectedRegisterId: _selectedRegisterId,
      onSelectRegister: (id) => setState(() => _selectedRegisterId = id),
      onOpenRegister: _openRegisterTx,
      onChanged: _loadData,
      pulsingRegisterId: _pulsingRegisterId,
    );
  }

  Widget _header(bool mobile) {
    final open = _shift != null;
    final openedAt = AppDateTime.formatShort(_shift?['opened_at']?.toString());
    final hPad = mobile ? AppResponsive.pagePadHMobile : AppResponsive.pagePadHDesktop;
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, mobile ? 8 : 20, hPad, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mobile)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Касса', style: AppTheme.pageTitle),
                      const SizedBox(height: 4),
                      Text(
                        'Управление кассой и приём платежей',
                        style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              if (!mobile) ...[
                _periodChip('today', 'Сегодня'),
                _periodChip('week', 'Неделя'),
                _periodChip('month', 'Месяц'),
                _periodChip('custom', _period == 'custom' ? '$_startDate — $_endDate' : 'Период'),
                IconButton(
                  tooltip: 'CSV',
                  onPressed: _exportCsv,
                  icon: const Icon(Icons.table_view_outlined, size: 20),
                ),
                const SizedBox(width: 8),
              ],
              if (!mobile)
                KeyedSubtree(
                  key: TourKeys.cashShift,
                  child: open
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.success.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: AppColors.success.withOpacity(0.35)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: AppColors.success,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    openedAt.isEmpty ? 'Смена открыта' : 'Смена открыта · $openedAt',
                                    style: GoogleFonts.manrope(
                                      color: AppColors.success,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () => _shiftPanelKey.currentState?.closeShiftDialog(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                                side: BorderSide(color: AppColors.danger.withOpacity(0.5)),
                              ),
                              child: Text('Закрыть', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        )
                      : OutlinedButton.icon(
                          onPressed: () => _shiftPanelKey.currentState?.openShiftDialog(),
                          icon: const Icon(Icons.calendar_today_outlined, size: 16),
                          label: Text('Открыть смену', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: BorderSide(color: AppColors.primary.withOpacity(0.55)),
                          ),
                        ),
                ),
            ],
          ),
          if (mobile) ...[
            KeyedSubtree(
              key: TourKeys.cashShift,
              child: open
                  ? Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.success.withOpacity(0.35)),
                            ),
                            child: Text(
                              openedAt.isEmpty ? 'Смена открыта' : 'Смена · $openedAt',
                              style: GoogleFonts.manrope(
                                color: AppColors.success,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => _shiftPanelKey.currentState?.closeShiftDialog(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            minimumSize: const Size(48, 48),
                            side: BorderSide(color: AppColors.danger.withOpacity(0.5)),
                          ),
                          child: Text('Закрыть', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _shiftPanelKey.currentState?.openShiftDialog(),
                        icon: const Icon(Icons.calendar_today_outlined, size: 18),
                        label: Text('Открыть смену', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          minimumSize: const Size(48, 48),
                          side: BorderSide(color: AppColors.primary.withOpacity(0.55)),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _periodChip('today', 'Сегодня'),
                  _periodChip('week', 'Неделя'),
                  _periodChip('month', 'Месяц'),
                  _periodChip('custom', _period == 'custom' ? 'Период' : 'Период'),
                  IconButton(
                    tooltip: 'CSV',
                    onPressed: _exportCsv,
                    icon: const Icon(Icons.table_view_outlined, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _balanceCard() {
    return KeyedSubtree(
      key: TourKeys.cashKpi,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          color: AppColors.surface2.withOpacity(0.9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderSoft.withOpacity(0.7)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primaryDeep.withOpacity(0.22),
              AppColors.surface2.withOpacity(0.95),
            ],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Баланс кассы',
                    style: GoogleFonts.manrope(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_money.format(_registerBalance)} ₽',
                    style: GoogleFonts.manrope(
                      color: AppColors.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 32,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: _loadData,
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded, size: 15, color: AppColors.textDim),
                        const SizedBox(width: 6),
                        Text(
                          _updatedLabel,
                          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.directions_car_filled_rounded, size: 72, color: AppColors.primary.withOpacity(0.28)),
          ],
        ),
      ),
    );
  }

  Widget _methodSplitCard({
    required String title,
    required IconData icon,
    required double amount,
    required Color color,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.surface2.withOpacity(0.88),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderSoft.withOpacity(0.65)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: GoogleFonts.manrope(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${_money.format(amount)} ₽',
                  style: GoogleFonts.manrope(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickAction({
    required String label,
    required IconData icon,
    required Color accent,
    required VoidCallback? onTap,
    Key? key,
    bool pulse = false,
    bool compact = false,
  }) {
    return Expanded(
      child: PulseAnchor(
        active: pulse,
        borderRadius: BorderRadius.circular(14),
        child: Material(
          key: key,
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: compact ? 84 : 96,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface2.withOpacity(0.88),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderSoft.withOpacity(0.65)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: compact ? 36 : 40,
                    height: compact ? 36 : 40,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: accent, size: compact ? 20 : 22),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      color: AppColors.text,
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 12.5 : 12,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickActionsRow({bool mobile = false}) {
    final collect = cashTemplateByKey('collect');
    final actions = [
      () => _quickAction(
            label: 'Новый платёж',
            icon: Icons.add_rounded,
            accent: AppColors.primary,
            pulse: isPulseActive(_pulseOp) || isPulseActive(_pulseTemplates),
            key: TourKeys.cashTemplates,
            onTap: () => _openOp(),
            compact: mobile,
          ),
      () => _quickAction(
            label: 'Возврат',
            icon: Icons.replay_rounded,
            accent: AppColors.danger,
            onTap: () => _openOp(template: _refundTemplate),
            compact: mobile,
          ),
      () => _quickAction(
            label: 'Инкассация',
            icon: Icons.south_rounded,
            accent: const Color(0xFFF59E0B),
            onTap: collect == null ? null : () => _openOp(template: collect),
            compact: mobile,
          ),
      () => _quickAction(
            label: 'Отчёт по смене',
            icon: Icons.description_outlined,
            accent: const Color(0xFF38BDF8),
            onTap: () => _shiftPanelKey.currentState?.showZReportDialog(),
            compact: mobile,
          ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Быстрые действия',
          style: GoogleFonts.manrope(
            color: AppColors.text,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 10),
        if (mobile) ...[
          Row(children: [actions[0](), const SizedBox(width: 10), actions[1]()]),
          const SizedBox(height: 10),
          Row(children: [actions[2](), const SizedBox(width: 10), actions[3]()]),
        ] else
          Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                actions[i](),
              ],
            ],
          ),
      ],
    );
  }

  Widget _registersStrip({required bool mobile}) {
    if (_registerSnapshots.isEmpty) {
      return Text(
        'Касс пока нет — откройте смену или добавьте кассу в панели смены',
        style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
      );
    }
    return SizedBox(
      height: mobile ? 72 : 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _registerSnapshots.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final s = _registerSnapshots[i];
          final type = s['money_type']?.toString() ?? '';
          final color = switch (type) {
            CashMethods.cash => AppColors.success,
            CashMethods.card => AppColors.primary,
            CashMethods.transfer => const Color(0xFF38BDF8),
            CashMethods.invoice => const Color(0xFFA78BFA),
            _ => AppColors.textMuted,
          };
          final expected = (s['expected'] as num?)?.toDouble() ?? (s['opening'] as num?)?.toDouble() ?? 0;
          final selected = _selectedRegisterId == (s['id'] as num).toInt();
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openRegisterTx(s),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: mobile ? 140 : 160,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: selected ? color.withOpacity(0.14) : AppColors.surface2.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(selected ? 0.7 : 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s['name']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    const Spacer(),
                    Text(
                      '${_money.format(expected)} ₽',
                      style: GoogleFonts.manrope(color: color, fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _paymentTile(Map<String, dynamic> row) {
    final isIncome = row['type']?.toString() == 'Приход';
    final method = row['method']?.toString() ?? '';
    final amount = (row['amount'] as num?)?.toDouble() ?? 0;
    final isCash = method == CashMethods.cash;
    final accent = isIncome
        ? (isCash ? AppColors.success : AppColors.primary)
        : AppColors.danger;
    final orderId = (row['order_id'] as num?)?.toInt();
    final time = _fmtDt(row['created_at']?.toString());
    final title = row['title']?.toString() ?? '';
    final subtitle = orderId != null ? 'Заказ №$orderId · $time' : time;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _editJournalRow(row),
        onLongPress: () => _deleteJournalRow(row),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isCash ? Icons.account_balance_wallet_outlined : Icons.credit_card_rounded,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isIncome ? '+' : '−'}${_money.format(amount)} ₽',
                    style: GoogleFonts.manrope(color: accent, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    method.isEmpty ? (isIncome ? 'Приход' : 'Расход') : method,
                    style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentPaymentsCard({required bool mobile}) {
    final rows = _recentPayments;
    final total = _journal.length;
    return PulseAnchor(
      active: isPulseActive(_pulseJournal),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        key: TourKeys.cashJournal,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface2.withOpacity(0.9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderSoft.withOpacity(0.65)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Последние платежи',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _filterSource = 'all';
                      _filterType = 'all';
                      _paymentsShown = 40;
                    });
                  },
                  child: Text(
                    'Все платежи',
                    style: GoogleFonts.manrope(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
            else if (rows.isEmpty)
              Expanded(
                child: Center(
                  child: Text('Нет операций за период', style: GoogleFonts.manrope(color: AppColors.textDim)),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.borderSoft.withOpacity(0.7)),
                  itemBuilder: (_, i) => _paymentTile(rows[i]),
                ),
              ),
            if (!_isLoading && total > rows.length) ...[
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => setState(() => _paymentsShown += 12),
                icon: const Icon(Icons.expand_more_rounded, size: 18),
                label: Text('Показать больше', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              ),
            ],
            if (!mobile) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _showDebts,
                  icon: Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.danger.withOpacity(0.9)),
                  label: Text(
                    'Долги · ${_money.format(_debtTotal)} ₽',
                    style: GoogleFonts.manrope(color: AppColors.danger, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bottomStats({required bool mobile}) {
    final cardPct = _totalIncome <= 0 ? 0 : (_cardSum / _totalIncome * 100);
    final cashPct = _totalIncome <= 0 ? 0 : (_cashSum / _totalIncome * 100);
    final avg = _incomeCount == 0 ? 0.0 : _totalIncome / _incomeCount;
    final items = <({String label, String value, Color color, String sub})>[
      (
        label: 'Выручка за период',
        value: '${_money.format(_totalIncome)} ₽',
        color: AppColors.success,
        sub: 'Расходы ${_money.format(_expenseSum)} ₽',
      ),
      (
        label: 'Платежи картой',
        value: '${_money.format(_cardSum)} ₽',
        color: AppColors.primary,
        sub: '${cardPct.round()}% от общей суммы',
      ),
      (
        label: 'Платежи наличными',
        value: '${_money.format(_cashSum)} ₽',
        color: AppColors.success,
        sub: '${cashPct.round()}% от общей суммы',
      ),
      (
        label: 'Средний чек',
        value: '${_money.format(avg)} ₽',
        color: AppColors.text,
        sub: '$_incomeCount платежей',
      ),
    ];

    Widget cell(({String label, String value, Color color, String sub}) it) {
      return Container(
        padding: EdgeInsets.fromLTRB(mobile ? 12 : 16, 12, mobile ? 12 : 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface2.withOpacity(0.88),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderSoft.withOpacity(0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(it.label, style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(it.value, style: GoogleFonts.manrope(color: it.color, fontWeight: FontWeight.w800, fontSize: mobile ? 16 : 18)),
            const SizedBox(height: 4),
            Text(it.sub, style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11.5)),
          ],
        ),
      );
    }

    if (mobile) {
      return Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            cell(items[i]),
          ],
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: cell(items[i])),
        ],
      ],
    );
  }

  Widget _buildMobileCash() {
    final hPad = AppResponsive.pagePadHMobile;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            _shiftHost(),
            ListView(
              padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
              children: [
                _header(true),
                _balanceCard(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _methodSplitCard(
                      title: 'Наличные',
                      icon: Icons.account_balance_wallet_outlined,
                      amount: _cashOnHand,
                      color: AppColors.success,
                      subtitle: 'В кассе ${_money.format(_cashOnHand)} ₽',
                      onTap: _showDebts,
                    ),
                    const SizedBox(width: 10),
                    _methodSplitCard(
                      title: 'Картой',
                      icon: Icons.credit_card_rounded,
                      amount: _cardSum,
                      color: AppColors.primary,
                      subtitle: 'За период ${_money.format(_cardSum)} ₽',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _quickActionsRow(mobile: true),
                const SizedBox(height: 14),
                Text('Кассы', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 8),
                _registersStrip(mobile: true),
                const SizedBox(height: 14),
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.38,
                  child: _recentPaymentsCard(mobile: true),
                ),
                const SizedBox(height: 12),
                _bottomStats(mobile: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = AppResponsive.isMobile(context);
    if (mobile) return _buildMobileCash();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          _shiftHost(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(false),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 58,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _balanceCard(),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _methodSplitCard(
                                  title: 'Наличные',
                                  icon: Icons.account_balance_wallet_outlined,
                                  amount: _cashOnHand,
                                  color: AppColors.success,
                                  subtitle: 'В кассе ${_money.format(_cashOnHand)} ₽',
                                ),
                                const SizedBox(width: 10),
                                _methodSplitCard(
                                  title: 'Картой',
                                  icon: Icons.credit_card_rounded,
                                  amount: _cardSum,
                                  color: AppColors.primary,
                                  subtitle: 'За период ${_money.format(_cardSum)} ₽',
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _quickActionsRow(),
                            const SizedBox(height: 14),
                            Text('Кассы', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 14)),
                            const SizedBox(height: 8),
                            _registersStrip(mobile: false),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 42,
                        child: _recentPaymentsCard(mobile: false),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: _bottomStats(mobile: false),
              ),
            ],
          ),
        ],
      ),
    );
  }

}
