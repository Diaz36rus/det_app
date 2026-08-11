import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'database.dart';
import 'responsive.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  double _revToday = 0;
  double _revMonth = 0;
  double _avgCheck = 0;
  double _ordersCount = 0;
  double _openDebt = 0;
  List<Map<String, dynamic>> _topByCount = [];
  List<Map<String, dynamic>> _topByRevenue = [];
  List<double> _dayTotals = List.filled(30, 0);
  List<String> _dayLabels = List.filled(30, "");
  List<Map<String, dynamic>> _masterDay = [];
  late DateTime _masterDayDate;
  bool _isLoading = true;

  final _money = NumberFormat('#,##0.##', 'ru_RU');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _masterDayDate = DateTime(now.year, now.month, now.day);
    _loadStats();
  }

  Future<void> _loadStats() async {
    final revToday = await DatabaseHelper().getRevenueToday();
    final revMonth = await DatabaseHelper().getRevenueMonth();
    final kpis = await DatabaseHelper().getStatsKpis();
    final topByCount = await DatabaseHelper().getServicesStats();
    final topByRevenue = await DatabaseHelper().getTopServicesByRevenue();
    final byDay = await DatabaseHelper().getRevenueByDay(30);
    final masterDay = await DatabaseHelper().getMasterDayStats(
      DateFormat('yyyy-MM-dd').format(_masterDayDate),
    );

    final map = <String, double>{};
    for (final r in byDay) {
      map[r['day']?.toString() ?? ""] = (r['total'] as num?)?.toDouble() ?? 0;
    }

    final now = DateTime.now();
    final labels = <String>[];
    final totals = <double>[];
    for (int i = 29; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(d);
      labels.add(DateFormat('dd.MM').format(d));
      totals.add(map[key] ?? 0);
    }

    if (!mounted) return;
    setState(() {
      _revToday = revToday;
      _revMonth = revMonth;
      _avgCheck = kpis['avg_check'] ?? 0;
      _ordersCount = kpis['orders_count'] ?? 0;
      _openDebt = kpis['open_debt'] ?? 0;
      _topByCount = topByCount;
      _topByRevenue = topByRevenue;
      _dayLabels = labels;
      _dayTotals = totals;
      _masterDay = masterDay;
      _isLoading = false;
    });
  }

  Future<void> _pickMasterDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _masterDayDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _masterDayDate = DateTime(picked.year, picked.month, picked.day);
      _isLoading = true;
    });
    await _loadStats();
  }

  Widget _masterDayReport() {
    final dayLabel = DateFormat('dd.MM.yyyy').format(_masterDayDate);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Мастера за день',
                  style: AppTheme.sectionTitle,
                ),
              ),
              TextButton.icon(
                onPressed: _pickMasterDay,
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(dayLabel, style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_masterDay.isEmpty)
            Text(
              'Нет мастеров в справочнике',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
            )
          else
            ..._masterDay.map((m) {
              final n = (m['orders_count'] as num?)?.toInt() ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
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
                        fontSize: 13,
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

  Widget _kpiCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.manrope(color: color, fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    final maxY = _dayTotals.fold<double>(0, (a, b) => a > b ? a : b);
    final chartMax = maxY <= 0 ? 1.0 : maxY * 1.2;

    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: BarChart(
        BarChartData(
          maxY: chartMax,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= _dayLabels.length) return const SizedBox.shrink();
                  if (i % 5 != 0 && i != _dayLabels.length - 1) return const SizedBox.shrink();
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
            for (int i = 0; i < _dayTotals.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: _dayTotals[i],
                    color: AppColors.primary,
                    width: 6,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _topList({
    required String title,
    required List<Map<String, dynamic>> items,
    required String valueKey,
    required String Function(Map<String, dynamic>) valueLabel,
    required double Function(Map<String, dynamic>) valueNum,
  }) {
    double maxVal = 1;
    for (final s in items) {
      final v = valueNum(s);
      if (v > maxVal) maxVal = v;
    }

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.sectionTitle),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text("Пока нет данных", style: GoogleFonts.manrope(color: AppColors.textDim)),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final s = items[index];
                      final val = valueNum(s);
                      final fraction = val / maxVal;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(AppTheme.radius),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  "${index + 1}.",
                                  style: GoogleFonts.manrope(
                                    color: AppColors.textDim,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    s['name']?.toString() ?? "",
                                    style: GoogleFonts.manrope(
                                      color: AppColors.text,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  valueLabel(s),
                                  style: GoogleFonts.manrope(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: fraction,
                                minHeight: 6,
                                backgroundColor: AppColors.surface,
                                color: AppColors.primary,
                              ),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final mobile = AppResponsive.isMobile(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: mobile ? const EdgeInsets.fromLTRB(12, 12, 12, 16) : AppTheme.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mobile) ...[
              Text("Статистика", style: AppTheme.pageTitle),
              const SizedBox(height: 16),
            ],
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _kpiCard("Сегодня", "${_money.format(_revToday)} ₽", AppColors.success),
                  const SizedBox(width: 10),
                  _kpiCard("Месяц", "${_money.format(_revMonth)} ₽", AppColors.primary),
                  const SizedBox(width: 10),
                  _kpiCard("Средний чек", "${_money.format(_avgCheck)} ₽", AppColors.text),
                  const SizedBox(width: 10),
                  _kpiCard("Заказов", "${_ordersCount.toInt()}", AppColors.textMuted),
                  const SizedBox(width: 10),
                  _kpiCard("Долг открытых", "${_money.format(_openDebt)} ₽", AppColors.danger),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text("Выручка за 30 дней", style: AppTheme.sectionTitle),
            const SizedBox(height: 8),
            _buildChart(),
            const SizedBox(height: 16),
            _masterDayReport(),
            const SizedBox(height: 16),
            Expanded(
              child: mobile
                  ? ListView(
                      children: [
                        SizedBox(
                          height: 280,
                          child: _topList(
                            title: "Топ по количеству",
                            items: _topByCount,
                            valueKey: 'count',
                            valueLabel: (s) => "${(s['count'] as num?)?.toInt() ?? 0} раз",
                            valueNum: (s) => ((s['count'] as num?)?.toDouble() ?? 0),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 280,
                          child: _topList(
                            title: "Топ по выручке",
                            items: _topByRevenue,
                            valueKey: 'revenue',
                            valueLabel: (s) =>
                                "${_money.format((s['revenue'] as num?)?.toDouble() ?? 0)} ₽",
                            valueNum: (s) => ((s['revenue'] as num?)?.toDouble() ?? 0),
                          ),
                        ),
                      ],
                    )
                  : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _topList(
                    title: "Топ по количеству",
                    items: _topByCount,
                    valueKey: 'count',
                    valueLabel: (s) => "${(s['count'] as num?)?.toInt() ?? 0} раз",
                    valueNum: (s) => ((s['count'] as num?)?.toDouble() ?? 0),
                  ),
                  const SizedBox(width: 16),
                  _topList(
                    title: "Топ по выручке",
                    items: _topByRevenue,
                    valueKey: 'revenue',
                    valueLabel: (s) =>
                        "${_money.format((s['revenue'] as num?)?.toDouble() ?? 0)} ₽",
                    valueNum: (s) => ((s['revenue'] as num?)?.toDouble() ?? 0),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
