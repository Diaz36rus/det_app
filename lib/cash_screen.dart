import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_datetime.dart';
import 'app_theme.dart';
import 'cash_catalog.dart';
import 'cash_operation_dialog.dart';
import 'cash_register_tx_dialog.dart';
import 'cash_shift_panel.dart';
import 'database.dart';
import 'db_refresh_mixin.dart';
import 'order_details_dialog.dart';
import 'payment_edit_dialog.dart';
import 'pulse_anchor.dart';
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
  final _money = NumberFormat('#,##0.##', 'ru_RU');

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
    });
  }

  double get _totalIncome => _cashSum + _cardSum + _transferSum + _invoiceSum;
  double get _net => _totalIncome - _expenseSum;

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

  Future<void> _showDebts() async {
    final debts = await DatabaseHelper().getOrderDebts();
    if (!mounted) return;
    await runWithPulseHighlight(
      _pulseDebts,
      () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Долги по заказам', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: AppResponsive.dialogWidth(ctx, desktop: 480),
            height: AppResponsive.isMobile(ctx) ? MediaQuery.sizeOf(ctx).height * 0.55 : 420,
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
                        trailing: Text(
                          '${_money.format(debt)} ₽',
                          style: GoogleFonts.manrope(color: AppColors.danger, fontWeight: FontWeight.w800),
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

  Widget _kpi({
    required String title,
    required double amount,
    required Color color,
    VoidCallback? onTap,
    bool emphasize = false,
    /// false — фиксированная ширина (горизонтальный скролл на mobile).
    bool expand = true,
    bool compact = false,
    bool pulse = false,
  }) {
    final child = PulseAnchor(
      active: pulse,
      accent: color,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: Container(
        width: expand ? null : 132,
        height: compact ? 56 : 72,
        padding: EdgeInsets.fromLTRB(compact ? 12 : 14, compact ? 8 : 10, compact ? 10 : 14, compact ? 8 : 10),
        decoration: AppTheme.kpiDecoration(accent: color, emphasize: emphasize || onTap != null),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: GoogleFonts.manrope(
                color: AppColors.textMuted,
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: compact ? 2 : 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '${_money.format(amount)} ₽',
                style: GoogleFonts.manrope(
                  color: color,
                  fontSize: compact ? 15 : 18,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final tappable = onTap == null
        ? child
        : Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(AppTheme.radius), child: child),
          );
    if (!expand) return tappable;
    return Expanded(child: tappable);
  }

  Widget _templateChip(CashTemplate t, {bool emphasize = false}) {
    final income = t.type == 'Приход';
    final accent = income ? AppColors.success : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openOp(template: t),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: emphasize ? 40 : 36,
            padding: EdgeInsets.symmetric(horizontal: emphasize ? 14 : 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withOpacity(emphasize ? 0.18 : 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              t.label,
              style: GoogleFonts.manrope(
                color: accent,
                fontWeight: FontWeight.w800,
                fontSize: emphasize ? 13.5 : 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _templateRow(String title, Color titleColor, List<CashTemplate> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              title,
              style: GoogleFonts.manrope(
                color: titleColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: items.map((t) => _templateChip(t, emphasize: true)).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _journalRow(Map<String, dynamic> row, bool alt, {bool desktopActions = false}) {
    final isIncome = row['type']?.toString() == 'Приход';
    final color = isIncome ? AppColors.success : AppColors.danger;
    final sign = isIncome ? '+' : '−';
    final amount = (row['amount'] as num?)?.toDouble() ?? 0;
    final orderId = (row['order_id'] as num?)?.toInt();
    final source = row['source']?.toString() ?? '';
    final clickable = orderId != null && source == 'payment' && !desktopActions;
    final meta = [
      row['category']?.toString() ?? '',
      row['method']?.toString() ?? '',
      if (source == 'payment') 'оплата',
      if (source == 'flow') 'операция',
    ].where((s) => s.isNotEmpty).join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: desktopActions
            ? () => _editJournalRow(row)
            : (clickable ? () => _openOrder(orderId) : null),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: alt ? AppColors.surface2.withOpacity(0.55) : Colors.transparent,
            border: const Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 88,
                child: Text(
                  _fmtDt(row['created_at']?.toString()),
                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row['title']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        color: (clickable || desktopActions) ? AppColors.primary : AppColors.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: Text(
                  '$sign${_money.format(amount)} ₽',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.manrope(color: color, fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              if (desktopActions) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Изменить',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _editJournalRow(row),
                ),
                IconButton(
                  tooltip: 'Удалить',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline, size: 18, color: AppColors.danger.withOpacity(0.9)),
                  onPressed: () => _deleteJournalRow(row),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Mobile: смена + компактные KPI + операция + шаблоны + журнал.
  Widget _buildMobileCash() {
    final expenseTpl = kCashTemplates.where((t) => t.type == 'Расход').toList();
    final incomeTpl = kCashTemplates.where((t) => t.type == 'Приход').toList();
    final rows = _filteredJournal.take(40).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Text('Касса', style: AppTheme.pageTitle),
            const SizedBox(height: 6),
            Text(
              'Смена, итоги и операции',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _periodChip('today', 'Сегодня'),
                  _periodChip('week', 'Неделя'),
                  _periodChip('month', 'Месяц'),
                  _periodChip(
                    'custom',
                    _period == 'custom' ? '$_startDate — $_endDate' : 'Период',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: TourKeys.cashKpi,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    SizedBox(width: 120, child: _kpi(title: 'Наличные', amount: _cashSum, color: AppColors.success, expand: false)),
                    const SizedBox(width: 8),
                    SizedBox(width: 110, child: _kpi(title: 'Карта', amount: _cardSum, color: AppColors.primary, expand: false)),
                    const SizedBox(width: 8),
                    SizedBox(width: 110, child: _kpi(title: 'Перевод', amount: _transferSum, color: const Color(0xFF38BDF8), expand: false)),
                    const SizedBox(width: 8),
                    SizedBox(width: 110, child: _kpi(title: 'По счету', amount: _invoiceSum, color: const Color(0xFFA78BFA), expand: false)),
                    const SizedBox(width: 8),
                    SizedBox(width: 110, child: _kpi(title: 'Расходы', amount: _expenseSum, color: AppColors.danger, expand: false)),
                    const SizedBox(width: 8),
                    SizedBox(width: 110, child: _kpi(title: 'Итого', amount: _net, color: AppColors.text, emphasize: true, expand: false)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 110,
                      child: _kpi(
                        title: 'Долги',
                        amount: _debtTotal,
                        color: AppColors.danger,
                        onTap: _showDebts,
                        expand: false,
                        pulse: isPulseActive(_pulseDebts),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: TourKeys.cashShift,
              child: CashShiftPanel(
                shift: _shift,
                registerSnapshots: _registerSnapshots,
                selectedRegisterId: _selectedRegisterId,
                onSelectRegister: (id) => setState(() => _selectedRegisterId = id),
                onOpenRegister: _openRegisterTx,
                onChanged: _loadData,
                pulsingRegisterId: _pulsingRegisterId,
              ),
            ),
            const SizedBox(height: 16),
            PulseAnchor(
              active: isPulseActive(_pulseOp),
              borderRadius: BorderRadius.circular(AppTheme.radius),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => _openOp(),
                  icon: const Icon(Icons.add, size: 22),
                  label: Text(
                    'Новая операция',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Быстрые шаблоны',
              style: GoogleFonts.manrope(
                color: AppColors.textDim,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 10),
            PulseAnchor(
              active: isPulseActive(_pulseTemplates),
              child: KeyedSubtree(
                key: TourKeys.cashTemplates,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _templateRow('Расход', AppColors.danger, expenseTpl),
                    _templateRow('Приход', AppColors.success, incomeTpl),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            PulseAnchor(
              active: isPulseActive(_pulseJournal),
              child: KeyedSubtree(
                key: TourKeys.cashJournal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('Журнал', style: AppTheme.sectionTitle),
                        const Spacer(),
                        _miniFilter('Все', _filterSource == 'all' && _filterType == 'all', () {
                          setState(() {
                            _filterSource = 'all';
                            _filterType = 'all';
                          });
                        }),
                        _miniFilter('Оплаты', _filterSource == 'payment', () {
                          setState(() => _filterSource = _filterSource == 'payment' ? 'all' : 'payment');
                        }),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                      )
                    else if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          'Нет операций за период',
                          style: GoogleFonts.manrope(color: AppColors.textDim),
                        ),
                      )
                    else
                      ...rows.asMap().entries.map((e) => _journalRow(e.value, e.key.isOdd)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (AppResponsive.isMobile(context)) {
      return _buildMobileCash();
    }

    final rows = _filteredJournal;
    final expenseTpl = kCashTemplates.where((t) => t.type == 'Расход').toList();
    final incomeTpl = kCashTemplates.where((t) => t.type == 'Приход').toList();
    const padH = 24.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(padH, 20, padH, 10),
            child: Row(
              children: [
                Text('Касса', style: AppTheme.pageTitle),
                const Spacer(),
                _periodChip('today', 'Сегодня'),
                _periodChip('week', 'Неделя'),
                _periodChip('month', 'Месяц'),
                _periodChip('custom', _period == 'custom' ? '$_startDate — $_endDate' : 'Период'),
                const SizedBox(width: 8),
                PulseAnchor(
                  active: isPulseActive(_pulseOp),
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  child: ElevatedButton.icon(
                    onPressed: () => _openOp(),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text('Операция', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            key: TourKeys.cashShift,
            padding: const EdgeInsets.fromLTRB(padH, 0, padH, 8),
            child: CashShiftPanel(
              shift: _shift,
              registerSnapshots: _registerSnapshots,
              selectedRegisterId: _selectedRegisterId,
              onSelectRegister: (id) => setState(() => _selectedRegisterId = id),
              onOpenRegister: _openRegisterTx,
              onChanged: _loadData,
              pulsingRegisterId: _pulsingRegisterId,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(padH, 0, padH, 6),
            child: KeyedSubtree(
              key: TourKeys.cashKpi,
              child: Row(
                children: [
                  _kpi(title: 'Наличные', amount: _cashSum, color: AppColors.success, compact: true),
                  const SizedBox(width: 6),
                  _kpi(title: 'Карта', amount: _cardSum, color: AppColors.primary, compact: true),
                  const SizedBox(width: 6),
                  _kpi(title: 'Перевод', amount: _transferSum, color: const Color(0xFF38BDF8), compact: true),
                  const SizedBox(width: 6),
                  _kpi(title: 'По счету', amount: _invoiceSum, color: const Color(0xFFA78BFA), compact: true),
                  const SizedBox(width: 6),
                  _kpi(title: 'Расходы', amount: _expenseSum, color: AppColors.danger, compact: true),
                  const SizedBox(width: 6),
                  _kpi(title: 'Итого', amount: _net, color: AppColors.text, emphasize: true, compact: true),
                  const SizedBox(width: 6),
                  _kpi(
                    title: 'Долги',
                    amount: _debtTotal,
                    color: AppColors.danger,
                    onTap: _showDebts,
                    compact: true,
                    pulse: isPulseActive(_pulseDebts),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            key: TourKeys.cashTemplates,
            padding: const EdgeInsets.fromLTRB(padH, 0, padH, 8),
            child: PulseAnchor(
              active: isPulseActive(_pulseTemplates),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: AppTheme.panelDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('Быстрые шаблоны', style: AppTheme.sectionTitle),
                        const SizedBox(width: 10),
                        Text(
                          'один клик',
                          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _templateRow('Расход', AppColors.danger, expenseTpl),
                    _templateRow('Приход', AppColors.success, incomeTpl),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            key: TourKeys.cashJournal,
            padding: const EdgeInsets.fromLTRB(padH, 4, padH, 0),
            child: PulseAnchor(
              active: isPulseActive(_pulseJournal),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                decoration: BoxDecoration(
                  color: AppColors.surface2.withOpacity(0.9),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
                ),
                child: Row(
                  children: [
                    Text('Журнал', style: AppTheme.sectionTitle),
                    const SizedBox(width: 14),
                    _miniFilter('Все', _filterSource == 'all' && _filterType == 'all', () {
                      setState(() {
                        _filterSource = 'all';
                        _filterType = 'all';
                      });
                    }),
                    _miniFilter('Оплаты', _filterSource == 'payment', () {
                      setState(() => _filterSource = _filterSource == 'payment' ? 'all' : 'payment');
                    }),
                    _miniFilter('Операции', _filterSource == 'flow', () {
                      setState(() => _filterSource = _filterSource == 'flow' ? 'all' : 'flow');
                    }),
                    _miniFilter(
                      'Приход',
                      _filterType == 'Приход',
                      () => setState(() => _filterType = _filterType == 'Приход' ? 'all' : 'Приход'),
                      activeColor: AppColors.success,
                    ),
                    _miniFilter(
                      'Расход',
                      _filterType == 'Расход',
                      () => setState(() => _filterType = _filterType == 'Расход' ? 'all' : 'Расход'),
                      activeColor: AppColors.danger,
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 130,
                      child: DropdownButtonFormField<String?>(
                        value: _filterMethod,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: 'Метод',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        dropdownColor: AppColors.surface,
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Все')),
                          ...CashMethods.all.map((m) => DropdownMenuItem(value: m, child: Text(m))),
                        ],
                        onChanged: (v) => setState(() => _filterMethod = v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(padH, 0, padH, 20),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface2.withOpacity(0.55),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppTheme.radiusLg)),
                ),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : rows.isEmpty
                        ? Center(
                            child: Text('Нет операций за период', style: GoogleFonts.manrope(color: AppColors.textDim)),
                          )
                        : ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (context, index) =>
                                _journalRow(rows[index], index.isOdd, desktopActions: true),
                          ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniFilter(String label, bool active, VoidCallback onTap, {Color? activeColor}) {
    final accent = activeColor ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? AppColors.text : AppColors.textMuted,
          ),
        ),
        selected: active,
        onSelected: (_) => onTap(),
        selectedColor: accent.withOpacity(0.40),
        backgroundColor: Colors.transparent,
        side: BorderSide(color: active ? accent : AppColors.border),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
