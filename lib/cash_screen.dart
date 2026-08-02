import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'cash_catalog.dart';
import 'cash_operation_dialog.dart';
import 'cash_shift_panel.dart';
import 'database.dart';
import 'order_details_dialog.dart';
import 'tour_keys.dart';

class CashScreen extends StatefulWidget {
  const CashScreen({super.key});

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  String _period = 'today';
  String _startDate = '';
  String _endDate = '';
  List<Map<String, dynamic>> _journal = [];
  Map<String, dynamic>? _shift;
  double? _expectedCash;
  double _debtTotal = 0;

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
    double? expected;
    if (shift != null) {
      expected = await DatabaseHelper().getShiftExpectedCash((shift['id'] as num).toInt());
    }
    final debt = await DatabaseHelper().getTotalDebt();

    double cash = 0, card = 0, transfer = 0, invoice = 0, expense = 0;
    for (final row in journal) {
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      final type = row['type']?.toString() ?? '';
      final method = row['method']?.toString() ?? '';
      final source = row['source']?.toString() ?? '';

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
          if (source == 'payment') card += amount;
          break;
      }
    }

    if (!mounted) return;
    setState(() {
      _journal = journal;
      _shift = shift;
      _expectedCash = expected;
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

  String _fmtDt(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw.contains(' ') ? raw.replaceFirst(' ', 'T') : raw);
    if (dt == null) return raw;
    return DateFormat('dd.MM HH:mm').format(dt);
  }

  Future<void> _openOp({CashTemplate? template}) async {
    final ok = await CashOperationDialog.open(context, template: template);
    if (ok == true) _loadData();
  }

  Future<void> _openOrder(int orderId) async {
    final order = await DatabaseHelper().getOrderById(orderId);
    if (order == null || !mounted) return;
    final refreshed = await OrderDetailsDialog.open(context, order);
    if (refreshed == true) _loadData();
  }

  Future<void> _showDebts() async {
    final debts = await DatabaseHelper().getOrderDebts();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Долги по заказам', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 480,
          height: 420,
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
  }) {
    final child = Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: emphasize
              ? AppColors.primary.withOpacity(0.65)
              : (onTap != null ? color.withOpacity(0.45) : AppColors.border),
          width: emphasize ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${_money.format(amount)} ₽',
              style: GoogleFonts.manrope(color: color, fontSize: 18, fontWeight: FontWeight.w800, height: 1.1),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return Expanded(child: child);
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(AppTheme.radius), child: child),
      ),
    );
  }

  Widget _templateChip(CashTemplate t) {
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
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withOpacity(0.40)),
            ),
            child: Text(
              t.label,
              style: GoogleFonts.manrope(
                color: accent,
                fontWeight: FontWeight.w700,
                fontSize: 13,
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
              child: Row(children: items.map(_templateChip).toList()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _journalRow(Map<String, dynamic> row, bool alt) {
    final isIncome = row['type']?.toString() == 'Приход';
    final color = isIncome ? AppColors.success : AppColors.danger;
    final sign = isIncome ? '+' : '−';
    final amount = (row['amount'] as num?)?.toDouble() ?? 0;
    final orderId = (row['order_id'] as num?)?.toInt();
    final source = row['source']?.toString() ?? '';
    final clickable = orderId != null && source == 'payment';
    final meta = [
      row['category']?.toString() ?? '',
      row['method']?.toString() ?? '',
    ].where((s) => s.isNotEmpty).join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: clickable ? () => _openOrder(orderId) : null,
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
                        color: clickable ? AppColors.primary : AppColors.text,
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
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredJournal;
    final expenseTpl = kCashTemplates.where((t) => t.type == 'Расход').toList();
    final incomeTpl = kCashTemplates.where((t) => t.type == 'Приход').toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Шапка ---
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(
              children: [
                Text('Касса', style: AppTheme.pageTitle),
                const Spacer(),
                _periodChip('today', 'Сегодня'),
                _periodChip('week', 'Неделя'),
                _periodChip('month', 'Месяц'),
                _periodChip('custom', _period == 'custom' ? '$_startDate — $_endDate' : 'Период'),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _openOp(),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('Операция', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),

          // --- KPI + смена ---
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: KeyedSubtree(
                    key: TourKeys.cashKpi,
                    child: Row(
                    children: [
                      _kpi(title: 'Наличные', amount: _cashSum, color: AppColors.success),
                      const SizedBox(width: 8),
                      _kpi(title: 'Карта', amount: _cardSum, color: AppColors.primary),
                      const SizedBox(width: 8),
                      _kpi(title: 'Перевод', amount: _transferSum, color: const Color(0xFF38BDF8)),
                      const SizedBox(width: 8),
                      _kpi(title: 'По счёту', amount: _invoiceSum, color: const Color(0xFFA78BFA)),
                      const SizedBox(width: 8),
                      _kpi(title: 'Расходы', amount: _expenseSum, color: AppColors.danger),
                      const SizedBox(width: 8),
                      _kpi(title: 'Итого', amount: _net, color: AppColors.text, emphasize: true),
                      const SizedBox(width: 8),
                      _kpi(title: 'Долги', amount: _debtTotal, color: AppColors.danger, onTap: _showDebts),
                    ],
                  ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  key: TourKeys.cashShift,
                  width: 240,
                  child: CashShiftPanel(
                    shift: _shift,
                    expectedCash: _expectedCash,
                    onChanged: _loadData,
                  ),
                ),
              ],
            ),
          ),

          // --- Шаблоны двумя группами ---
          Padding(
            key: TourKeys.cashTemplates,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Быстрые шаблоны',
                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4),
                ),
                const SizedBox(height: 8),
                _templateRow('Расход', AppColors.danger, expenseTpl),
                _templateRow('Приход', AppColors.success, incomeTpl),
              ],
            ),
          ),

          // --- Журнал: заголовок + фильтры ---
          Padding(
            key: TourKeys.cashJournal,
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border.all(color: AppColors.border),
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

          // --- Список ---
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface.withOpacity(0.35),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  border: const Border(
                    left: BorderSide(color: AppColors.border),
                    right: BorderSide(color: AppColors.border),
                    bottom: BorderSide(color: AppColors.border),
                  ),
                ),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : rows.isEmpty
                        ? Center(
                            child: Text('Нет операций за период', style: GoogleFonts.manrope(color: AppColors.textDim)),
                          )
                        : ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (context, index) => _journalRow(rows[index], index.isOdd),
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
        backgroundColor: AppColors.bg,
        side: BorderSide(color: active ? accent : AppColors.border),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
