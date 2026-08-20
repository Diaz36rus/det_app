import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'crm/cloud_db_bridge.dart';
import 'database.dart';
import 'responsive.dart';

enum _StatsPeriod { today, week, month }

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  _StatsPeriod _period = _StatsPeriod.month;
  int _topMode = 0; // 0 count, 1 revenue

  double _revPeriod = 0;
  double _avgCheck = 0;
  double _ordersPeriod = 0;
  double _openDebt = 0;
  double _openOrders = 0;
  List<Map<String, dynamic>> _topByCount = [];
  List<Map<String, dynamic>> _topByRevenue = [];
  List<Map<String, dynamic>> _byStatus = [];
  List<double> _dayTotals = const [];
  List<String> _dayLabels = const [];
  List<Map<String, dynamic>> _masterDay = [];
  late DateTime _masterDayDate;
  bool _isLoading = true;
  String? _error;

  final _money = NumberFormat('#,##0', 'ru_RU');

  int get _days {
    final now = DateTime.now();
    switch (_period) {
      case _StatsPeriod.today:
        return 1;
      case _StatsPeriod.week:
        return 7;
      case _StatsPeriod.month:
        return now.day.clamp(1, 31);
    }
  }

  String get _periodLabel {
    switch (_period) {
      case _StatsPeriod.today:
        return 'Сегодня';
      case _StatsPeriod.week:
        return '7 дней';
      case _StatsPeriod.month:
        return 'Месяц';
    }
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _masterDayDate = DateTime(now.year, now.month, now.day);
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final masterDayKey = DateFormat('yyyy-MM-dd').format(_masterDayDate);
    final days = _days;

    try {
      late final Map<String, dynamic> s;
      if (CloudDbBridge.active) {
        s = await CloudDbBridge.instance.getCompanyStats(masterDay: masterDayKey, days: days);
      } else {
        s = await DatabaseHelper().getCompanyStatsBundle(masterDay: masterDayKey, days: days);
      }

      final byDay = ((s['revenue_by_day'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final map = <String, double>{};
      for (final r in byDay) {
        map[r['day']?.toString() ?? ''] = (r['total'] as num?)?.toDouble() ?? 0;
      }

      final now = DateTime.now();
      final labels = <String>[];
      final totals = <double>[];
      for (int i = days - 1; i >= 0; i--) {
        final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
        final key = DateFormat('yyyy-MM-dd').format(d);
        labels.add(DateFormat('dd.MM').format(d));
        totals.add(map[key] ?? 0);
      }

      if (!mounted) return;
      setState(() {
        _revPeriod = (s['revenue_period'] as num?)?.toDouble() ??
            (s['revenue_month'] as num?)?.toDouble() ??
            0;
        if (_period == _StatsPeriod.today) {
          _revPeriod = (s['revenue_today'] as num?)?.toDouble() ?? _revPeriod;
        }
        _avgCheck = (s['avg_check'] as num?)?.toDouble() ?? 0;
        _ordersPeriod = (s['orders_period'] as num?)?.toDouble() ??
            (s['orders_count'] as num?)?.toDouble() ??
            0;
        _openDebt = (s['open_debt'] as num?)?.toDouble() ?? 0;
        _openOrders = (s['open_orders'] as num?)?.toDouble() ?? 0;
        _topByCount = ((s['top_by_count'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _topByRevenue = ((s['top_by_revenue'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _byStatus = ((s['by_status'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _masterDay = ((s['master_day'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _dayLabels = labels;
        _dayTotals = totals;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _pickMasterDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _masterDayDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _masterDayDate = DateTime(picked.year, picked.month, picked.day));
    await _loadStats();
  }

  Widget _periodChips() {
    Widget chip(_StatsPeriod p, String label) {
      final on = _period == p;
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: FilterChip(
          label: Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: on ? AppColors.text : AppColors.textMuted,
            ),
          ),
          selected: on,
          onSelected: (_) {
            if (_period == p) return;
            setState(() => _period = p);
            _loadStats();
          },
          selectedColor: AppColors.primary.withOpacity(0.28),
          checkmarkColor: AppColors.primary,
          backgroundColor: AppColors.surface2,
          side: BorderSide(color: on ? AppColors.primary.withOpacity(0.7) : AppColors.border),
        ),
      );
    }

    return Row(
      children: [
        chip(_StatsPeriod.today, 'Сегодня'),
        chip(_StatsPeriod.week, '7 дней'),
        chip(_StatsPeriod.month, 'Месяц'),
      ],
    );
  }

  Widget _kpi(String label, String value, Color accent) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: AppTheme.kpiDecoration(accent: accent),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.manrope(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text, style: AppTheme.sectionLabel);
  }

  Widget _panel({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: AppTheme.panelDecoration,
      child: child,
    );
  }

  Widget _buildChart() {
    final maxY = _dayTotals.fold<double>(0, (a, b) => a > b ? a : b);
    final chartMax = maxY <= 0 ? 1.0 : maxY * 1.15;
    final n = _dayTotals.length;
    final labelEvery = n <= 7 ? 1 : (n <= 14 ? 2 : 5);

    return SizedBox(
      height: 200,
      child: n == 0
          ? Center(
              child: Text('Нет данных', style: GoogleFonts.manrope(color: AppColors.textDim)),
            )
          : BarChart(
              BarChartData(
                maxY: chartMax,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: AppColors.borderSoft, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= _dayLabels.length) return const SizedBox.shrink();
                        if (i % labelEvery != 0 && i != _dayLabels.length - 1) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _dayLabels[i],
                            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (int i = 0; i < n; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: _dayTotals[i],
                          color: i == n - 1 ? AppColors.primary : AppColors.primary.withOpacity(0.55),
                          width: n <= 7 ? 14 : (n <= 14 ? 8 : 5),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }

  Widget _statusBoard() {
    if (_byStatus.isEmpty) {
      return Text(
        'Нет заказов в работе',
        style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
      );
    }
    final maxC = _byStatus
        .map((e) => (e['count'] as num?)?.toDouble() ?? 0)
        .fold<double>(1, (a, b) => a > b ? a : b);
    return Column(
      children: _byStatus.map((row) {
        final name = row['name']?.toString() ?? '—';
        final count = (row['count'] as num?)?.toInt() ?? 0;
        final color = kOrderStatusColors[name] ?? AppColors.textMuted;
        final frac = count / maxC;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: GoogleFonts.manrope(
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '$count',
                    style: GoogleFonts.manrope(
                      color: AppColors.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: frac.clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: AppColors.surface,
                  color: color.withOpacity(0.85),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _mastersPanel() {
    final dayLabel = DateFormat('dd.MM.yyyy').format(_masterDayDate);
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionLabel('МАСТЕРА')),
              TextButton.icon(
                onPressed: _pickMasterDay,
                icon: const Icon(Icons.calendar_today, size: 15),
                label: Text(dayLabel, style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_masterDay.isEmpty)
            Text('Нет сотрудников', style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13))
          else
            ..._masterDay.map((m) {
              final n = (m['orders_count'] as num?)?.toInt() ?? 0;
              final rev = (m['revenue'] as num?)?.toDouble() ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        m['name']?.toString() ?? '—',
                        style: GoogleFonts.manrope(
                          color: AppColors.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '$n зак.',
                      style: GoogleFonts.manrope(
                        color: n > 0 ? AppColors.success : AppColors.textDim,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 88,
                      child: Text(
                        rev > 0 ? '${_money.format(rev)} ₽' : '—',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.manrope(
                          color: rev > 0 ? AppColors.text : AppColors.textDim,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _topsPanel() {
    final items = _topMode == 0 ? _topByCount : _topByRevenue;
    double maxVal = 1;
    for (final s in items) {
      final v = _topMode == 0
          ? ((s['count'] as num?)?.toDouble() ?? 0)
          : ((s['revenue'] as num?)?.toDouble() ?? 0);
      if (v > maxVal) maxVal = v;
    }

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionLabel('УСЛУГИ · $_periodLabel')),
              _topTab(0, 'Шт'),
              const SizedBox(width: 6),
              _topTab(1, '₽'),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text(
              'Пока нет выданных заказов за период',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
            )
          else
            ...List.generate(items.length, (index) {
              final s = items[index];
              final val = _topMode == 0
                  ? ((s['count'] as num?)?.toDouble() ?? 0)
                  : ((s['revenue'] as num?)?.toDouble() ?? 0);
              final label = _topMode == 0
                  ? '${val.toInt()} раз'
                  : '${_money.format(val)} ₽';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${index + 1}.',
                          style: GoogleFonts.manrope(color: AppColors.textDim, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s['name']?.toString() ?? '',
                            style: GoogleFonts.manrope(
                              color: AppColors.text,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          label,
                          style: GoogleFonts.manrope(
                            color: AppColors.success,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (val / maxVal).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: AppColors.surface,
                        color: AppColors.primary.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _topTab(int mode, String label) {
    final on = _topMode == mode;
    return InkWell(
      onTap: () => setState(() => _topMode = mode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? AppColors.primary.withOpacity(0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? AppColors.primary.withOpacity(0.55) : AppColors.border),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: on ? AppColors.text : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = AppResponsive.isMobile(context);

    if (_isLoading && _dayTotals.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (_error != null && _dayTotals.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: GoogleFonts.manrope(color: AppColors.danger)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _loadStats, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }

    final kpiRow = Row(
      children: [
        _kpi('ВЫРУЧКА', '${_money.format(_revPeriod)} ₽', AppColors.success),
        const SizedBox(width: 10),
        _kpi('СРЕДНИЙ ЧЕК', '${_money.format(_avgCheck)} ₽', AppColors.primary),
        const SizedBox(width: 10),
        _kpi('ЗАКАЗОВ', '${_ordersPeriod.toInt()}', AppColors.textMuted),
        const SizedBox(width: 10),
        _kpi('В РАБОТЕ', '${_openOrders.toInt()}', const Color(0xFFF59E0B)),
        const SizedBox(width: 10),
        _kpi('ДОЛГ', '${_money.format(_openDebt)} ₽', AppColors.danger),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadStats,
        child: ListView(
          padding: mobile ? const EdgeInsets.fromLTRB(12, 12, 12, 24) : AppTheme.pagePadding,
          children: [
            if (!mobile)
              Row(
                children: [
                  Expanded(child: Text('Статистика', style: AppTheme.pageTitle)),
                  if (_isLoading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    ),
                  _periodChips(),
                ],
              )
            else ...[
              Row(
                children: [
                  Expanded(child: Text('Статистика', style: AppTheme.pageTitle.copyWith(fontSize: 22))),
                  _periodChips(),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (mobile)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 720),
                  child: IntrinsicHeight(child: kpiRow),
                ),
              )
            else
              kpiRow,
            const SizedBox(height: 18),
            if (mobile) ...[
              _sectionLabel('ВЫРУЧКА · $_periodLabel'),
              const SizedBox(height: 8),
              _panel(child: _buildChart()),
              const SizedBox(height: 14),
              _sectionLabel('В РАБОТЕ СЕЙЧАС'),
              const SizedBox(height: 8),
              _panel(child: _statusBoard()),
              const SizedBox(height: 14),
              _mastersPanel(),
              const SizedBox(height: 14),
              _topsPanel(),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('ВЫРУЧКА · $_periodLabel'),
                        const SizedBox(height: 8),
                        _panel(child: _buildChart()),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('В РАБОТЕ СЕЙЧАС'),
                        const SizedBox(height: 8),
                        _panel(child: _statusBoard()),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _mastersPanel()),
                  const SizedBox(width: 14),
                  Expanded(child: _topsPanel()),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
