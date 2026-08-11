import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'database.dart';
import 'db_refresh_mixin.dart';
import 'order_details_dialog.dart';
import 'responsive.dart';

class CalendarScreen extends StatefulWidget {
  final DateTime selectedDate;
  /// Клик по пустому слоту в «Общей записи» → создать заказ на это время.
  final void Function(DateTime date, TimeOfDay time)? onCreateAt;
  /// Смена дня (стрелки / date picker).
  final ValueChanged<DateTime>? onDateChanged;

  const CalendarScreen({
    super.key,
    required this.selectedDate,
    this.onCreateAt,
    this.onDateChanged,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> with DbRefreshMixin {
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _workItems = [];
  /// Заказы по дням недели (ключ yyyy-MM-dd) — режим «Неделя».
  final Map<String, List<Map<String, dynamic>>> _ordersByDay = {};
  bool _isLoading = true;
  bool _showGeneral = true;
  bool _weekMode = false;
  int _loadGen = 0;

  /// Long-press drag карточки в «Общей» / неделе.
  int? _dragOrderId;
  double _dragDy = 0;
  double? _dragStartGlobalY;
  DateTime? _dragFullStart;
  DateTime? _dragFullEnd;

  @override
  void onDatabaseChanged() => _loadData(showSpinner: false);

  /// Высота одного 30-минутного слота.
  final double _slotHeight = 36.0;
  final int _slotMinutes = 30;
  final double _colWidth = 200.0;
  final double _headerHeight = 40.0;
  final int _startHour = 8;
  final int _endHour = 22;
  /// Синхрон горизонтального скролла: заголовки ↔ сетка (детальное время).
  final ScrollController _hHeaderCtrl = ScrollController();
  final ScrollController _hBodyCtrl = ScrollController();
  bool _syncingHScroll = false;

  /// Слоты: 08:00, 08:30, …, 22:00, 22:30.
  int get _slotsCount => (_endHour - _startHour + 1) * 2;

  double get _gridHeight => _slotsCount * _slotHeight;

  double get _pixelsPerMinute => _slotHeight / _slotMinutes;

  double _offsetForTime(int hour, int minute) {
    final fromStart = (hour - _startHour) * 60 + minute;
    return fromStart * _pixelsPerMinute;
  }

  @override
  void initState() {
    super.initState();
    _hHeaderCtrl.addListener(_syncHFromHeader);
    _hBodyCtrl.addListener(_syncHFromBody);
    // После первого кадра — иначе setState из initState/переключения тура может оборвать загрузку.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
  }

  void _syncHFromHeader() {
    if (_syncingHScroll || !_hBodyCtrl.hasClients) return;
    if (_hBodyCtrl.offset == _hHeaderCtrl.offset) return;
    _syncingHScroll = true;
    _hBodyCtrl.jumpTo(_hHeaderCtrl.offset.clamp(0.0, _hBodyCtrl.position.maxScrollExtent));
    _syncingHScroll = false;
  }

  void _syncHFromBody() {
    if (_syncingHScroll || !_hHeaderCtrl.hasClients) return;
    if (_hHeaderCtrl.offset == _hBodyCtrl.offset) return;
    _syncingHScroll = true;
    _hHeaderCtrl.jumpTo(_hBodyCtrl.offset.clamp(0.0, _hHeaderCtrl.position.maxScrollExtent));
    _syncingHScroll = false;
  }

  @override
  void dispose() {
    _hHeaderCtrl.removeListener(_syncHFromHeader);
    _hBodyCtrl.removeListener(_syncHFromBody);
    _hHeaderCtrl.dispose();
    _hBodyCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sameDay = widget.selectedDate.year == oldWidget.selectedDate.year &&
        widget.selectedDate.month == oldWidget.selectedDate.month &&
        widget.selectedDate.day == oldWidget.selectedDate.day;
    if (!sameDay) {
      _loadData();
    }
  }

  DateTime _weekStart(DateTime d) {
    final day = _dateOnly(d);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  List<DateTime> _weekDays(DateTime d) =>
      List.generate(7, (i) => _weekStart(d).add(Duration(days: i)));

  Future<void> _loadData({bool showSpinner = true}) async {
    final gen = ++_loadGen;
    if (showSpinner && mounted) setState(() => _isLoading = true);
    try {
      if (_weekMode) {
        final days = _weekDays(widget.selectedDate);
        final results = await Future.wait(
          days.map((d) => DatabaseHelper().getOrdersForCalendar(DateFormat('yyyy-MM-dd').format(d))),
        );
        if (!mounted || gen != _loadGen) return;
        setState(() {
          _ordersByDay
            ..clear()
            ..addEntries([
              for (var i = 0; i < days.length; i++)
                MapEntry(DateFormat('yyyy-MM-dd').format(days[i]), results[i]),
            ]);
          _orders = results.expand((e) => e).toList();
          _workItems = [];
          _isLoading = false;
        });
        return;
      }
      final dateStr = DateFormat('yyyy-MM-dd').format(widget.selectedDate);
      final orders = await DatabaseHelper().getOrdersForCalendar(dateStr);
      final workItems = await DatabaseHelper().getOrderItemsForCalendar(dateStr);
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _orders = orders;
        _workItems = workItems;
        _ordersByDay.clear();
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('CalendarScreen._loadData: $e\n$st');
      if (mounted && gen == _loadGen) {
        setState(() {
          _orders = [];
          _workItems = [];
          _ordersByDay.clear();
          _isLoading = false;
        });
      }
    }
  }

  /// Полная дата-время: "2026-07-31 15:30:00", ISO, либо только "15:30" → [viewDay].
  DateTime? _tryParseDateTime(String? dtStr, {DateTime? viewDay}) {
    final day = viewDay ?? widget.selectedDate;
    if (dtStr == null || dtStr.trim().isEmpty) return null;
    try {
      final n = dtStr.replaceFirst('T', ' ').split('.').first.trim();
      if (n.contains(' ')) {
        return DateTime.parse(n.replaceFirst(' ', 'T'));
      }
      final parts = n.split(':');
      return DateTime(
        day.year,
        day.month,
        day.day,
        int.parse(parts[0]),
        parts.length > 1 ? int.parse(parts[1]) : 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Обрезает интервал заказа до видимого дня сетки (08:00–22:30).
  /// `null` — событие не пересекает выбранный день.
  ({DateTime start, DateTime end})? _clipEventToViewDay(
    String? startStr,
    String? endStr, {
    DateTime? viewDay,
  }) {
    final base = viewDay ?? widget.selectedDate;
    final day = DateTime(base.year, base.month, base.day);
    final dayEnd = day.add(const Duration(days: 1));
    final gridStart = DateTime(day.year, day.month, day.day, _startHour);
    final gridEnd = DateTime(day.year, day.month, day.day, _endHour)
        .add(Duration(minutes: _slotMinutes));

    final rawStart = _tryParseDateTime(startStr, viewDay: day);
    if (rawStart == null) return null;
    var rawEnd = _tryParseDateTime(endStr, viewDay: day);
    rawEnd ??= rawStart.add(const Duration(hours: 1));
    if (!rawEnd.isAfter(rawStart)) {
      rawEnd = rawStart.add(const Duration(minutes: 30));
    }

    // Не пересекает выбранный календарный день.
    if (!rawStart.isBefore(dayEnd) || !rawEnd.isAfter(day)) return null;

    var visStart = rawStart.isBefore(day) ? day : rawStart;
    var visEnd = rawEnd.isAfter(dayEnd) ? dayEnd : rawEnd;

    if (visStart.isBefore(gridStart)) visStart = gridStart;
    if (visEnd.isAfter(gridEnd)) visEnd = gridEnd;

    if (!visEnd.isAfter(visStart)) {
      // Слот целиком вне рабочих часов дня — короткий маркер у края сетки.
      if (rawEnd.isBefore(gridStart) || !rawEnd.isAfter(gridStart)) {
        visStart = gridStart;
        visEnd = gridStart.add(const Duration(minutes: 30));
      } else {
        visEnd = gridEnd;
        visStart = gridEnd.subtract(const Duration(minutes: 30));
      }
    }
    return (start: visStart, end: visEnd);
  }

  bool _overlaps(DateTime a0, DateTime a1, DateTime b0, DateTime b1) {
    return a0.isBefore(b1) && a1.isAfter(b0);
  }

  Future<void> _openOrder(int orderId) async {
    final fullOrder = await DatabaseHelper().getOrderById(orderId);
    if (fullOrder != null && mounted) {
      await OrderDetailsDialog.open(context, fullOrder);
      _loadData();
    }
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void _shiftDay(int delta) {
    final step = _weekMode ? 7 : 1;
    final next = _dateOnly(widget.selectedDate).add(Duration(days: delta * step));
    widget.onDateChanged?.call(next);
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOnly(widget.selectedDate),
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
      locale: const Locale('ru', 'RU'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(primary: AppColors.primary),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    widget.onDateChanged?.call(_dateOnly(picked));
  }

  Widget _dayNavigator({required double fontSize}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: _weekMode ? "Предыдущая неделя" : "Предыдущий день",
          onPressed: widget.onDateChanged == null ? null : () => _shiftDay(-1),
          icon: const Icon(Icons.chevron_left, color: AppColors.primary),
        ),
        Flexible(
          child: InkWell(
            onTap: widget.onDateChanged == null ? null : _pickDay,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(
                DateFormat('dd MMMM yyyy', 'ru').format(widget.selectedDate),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  color: AppColors.primary,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: _weekMode ? "Следующая неделя" : "Следующий день",
          onPressed: widget.onDateChanged == null ? null : () => _shiftDay(1),
          icon: const Icon(Icons.chevron_right, color: AppColors.primary),
        ),
      ],
    );
  }

  Widget _scopeToggle({required bool mobile}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg.withOpacity(0.45),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: ToggleButtons(
        isSelected: [!_weekMode, _weekMode],
        onPressed: (index) {
          setState(() {
            _weekMode = index == 1;
            if (_weekMode) _showGeneral = true;
          });
          _loadData();
        },
        color: AppColors.textMuted,
        selectedColor: AppColors.text,
        fillColor: AppColors.primarySoft.withOpacity(0.65),
        borderColor: Colors.transparent,
        selectedBorderColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radius - 2),
        constraints: BoxConstraints(minHeight: 36, minWidth: mobile ? 64 : 72),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('День', style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 12)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('Неделя', style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _weekStrip({required bool mobile}) {
    final days = _weekDays(widget.selectedDate);
    final today = _dateOnly(DateTime.now());
    final selected = _dateOnly(widget.selectedDate);
    return SizedBox(
      height: mobile ? 58 : 64,
      child: Row(
        children: [
          for (final d in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    onTap: widget.onDateChanged == null ? null : () => widget.onDateChanged!(_dateOnly(d)),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _dateOnly(d) == selected
                            ? AppColors.primarySoft.withOpacity(0.75)
                            : AppColors.surface2.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        border: Border.all(
                          color: _dateOnly(d) == today
                              ? AppColors.primary.withOpacity(0.7)
                              : AppColors.borderSoft.withOpacity(0.4),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            DateFormat('E', 'ru').format(d),
                            style: GoogleFonts.manrope(
                              color: AppColors.textDim,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${d.day}',
                            style: GoogleFonts.manrope(
                              color: AppColors.text,
                              fontSize: mobile ? 14 : 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _modeToggle({required bool mobile}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg.withOpacity(0.45),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: ToggleButtons(
        isSelected: [_showGeneral, !_showGeneral],
        onPressed: _weekMode
            ? null
            : (index) {
                setState(() => _showGeneral = index == 0);
                _loadData();
              },
        color: AppColors.textMuted,
        selectedColor: AppColors.text,
        fillColor: AppColors.primarySoft.withOpacity(0.65),
        borderColor: Colors.transparent,
        selectedBorderColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radius - 2),
        constraints: BoxConstraints(minHeight: 40, minWidth: mobile ? 100 : 130),
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: mobile ? 8 : 12),
            child: Text(
              mobile ? "Общая" : "Общая запись",
              style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: mobile ? 12 : 13),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: mobile ? 8 : 12),
            child: Text(
              mobile ? "Детально" : "Детальное время",
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w600,
                fontSize: mobile ? 12 : 13,
                color: _weekMode ? AppColors.textDim.withOpacity(0.45) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gridHeight = _gridHeight;
    // Колонки детального режима — цеха (как у позиций), не статусы канбана.
    final detailColumns = WORKSHOPS;

    final mobile = AppResponsive.isMobile(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(mobile ? 12 : 24, mobile ? 12 : 20, mobile ? 12 : 24, 8),
            child: mobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _dayNavigator(fontSize: 16),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _scopeToggle(mobile: true),
                          const SizedBox(width: 8),
                          Expanded(child: _modeToggle(mobile: true)),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Text("Календарь", style: AppTheme.pageTitle),
                      const SizedBox(width: 12),
                      Expanded(child: _dayNavigator(fontSize: 18)),
                      const SizedBox(width: 8),
                      _scopeToggle(mobile: false),
                      const SizedBox(width: 8),
                      _modeToggle(mobile: false),
                    ],
                  ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(mobile ? 12 : 24, 0, mobile ? 12 : 24, 6),
            child: _weekStrip(mobile: mobile),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(mobile ? 12 : 24, 0, mobile ? 12 : 24, 6),
            child: Text(
              _weekMode
                  ? 'Неделя · пустой слот — новый заказ · удерживайте карточку для переноса'
                  : 'Пустой слот — новый заказ · удерживайте карточку — перенос по времени',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : Padding(
                    padding: EdgeInsets.fromLTRB(mobile ? 8 : 12, 8, mobile ? 12 : 16, 16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final timeGutter = mobile ? 44.0 : 56.0;
                        final detailColW = mobile ? 160.0 : _colWidth;
                        final bodyColW = (constraints.maxWidth - timeGutter).clamp(120.0, 4000.0);
                        final weekDays = _weekDays(widget.selectedDate);
                        final weekColW = mobile ? 120.0 : 150.0;

                        Widget timeGutterCol() => SizedBox(
                              width: timeGutter,
                              child: Column(
                                children: List.generate(_slotsCount, (i) {
                                  final totalMin = _startHour * 60 + i * _slotMinutes;
                                  final h = totalMin ~/ 60;
                                  final m = totalMin % 60;
                                  final isHour = m == 0;
                                  return SizedBox(
                                    height: _slotHeight,
                                    child: Align(
                                      alignment: Alignment.topRight,
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 2, right: 4),
                                        child: Text(
                                          "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}",
                                          style: GoogleFonts.manrope(
                                            color: isHour ? AppColors.textMuted : AppColors.textDim,
                                            fontSize: isHour ? 11 : 10,
                                            fontWeight: isHour ? FontWeight.w700 : FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            );

                        if (_weekMode) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: _headerHeight,
                                child: Row(
                                  children: [
                                    SizedBox(width: timeGutter),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        controller: _hHeaderCtrl,
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: weekDays.map((d) {
                                            final label = DateFormat('E d.MM', 'ru').format(d);
                                            return _buildColumnHeader(label, weekColW);
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      timeGutterCol(),
                                      SizedBox(
                                        width: bodyColW,
                                        child: SingleChildScrollView(
                                          controller: _hBodyCtrl,
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: weekDays.map((d) {
                                              final key = DateFormat('yyyy-MM-dd').format(d);
                                              return _buildColumnBody(
                                                DateFormat('E d.MM', 'ru').format(d),
                                                weekColW,
                                                gridHeight,
                                                true,
                                                viewDay: d,
                                                ordersOverride: _ordersByDay[key] ?? const [],
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: _headerHeight,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(width: timeGutter),
                                  Expanded(
                                    child: _showGeneral
                                        ? _buildColumnHeader('Общая запись', bodyColW)
                                        : SingleChildScrollView(
                                            controller: _hHeaderCtrl,
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              children: detailColumns
                                                  .map((s) => _buildColumnHeader(s, detailColW))
                                                  .toList(),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    timeGutterCol(),
                                    if (_showGeneral)
                                      SizedBox(
                                        width: bodyColW,
                                        child: _buildColumnBody(
                                          'Общая запись',
                                          bodyColW,
                                          gridHeight,
                                          true,
                                        ),
                                      )
                                    else
                                      SizedBox(
                                        width: bodyColW,
                                        child: SingleChildScrollView(
                                          controller: _hBodyCtrl,
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: detailColumns
                                                .map(
                                                  (s) => _buildColumnBody(
                                                    s,
                                                    detailColW,
                                                    gridHeight,
                                                    false,
                                                  ),
                                                )
                                                .toList(),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnHeader(String title, double width) {
    // В «Общей» (день) — без зазора; неделя / детально — зазор между колонками.
    final gap = (!_weekMode && _showGeneral) ? 0.0 : 10.0;
    return Container(
      width: width,
      height: _headerHeight,
      margin: EdgeInsets.only(right: gap),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface2.withOpacity(0.85),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      child: Text(
        title,
        style: GoogleFonts.manrope(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.3,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildColumnBody(
    String title,
    double width,
    double gridHeight,
    bool isGeneral, {
    DateTime? viewDay,
    List<Map<String, dynamic>>? ordersOverride,
  }) {
    final gap = (!_weekMode && isGeneral) ? 0.0 : 10.0;
    final dayForCreate = viewDay ?? widget.selectedDate;
    return Container(
      width: width,
      height: gridHeight,
      margin: EdgeInsets.only(right: gap),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.55),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppTheme.radiusLg)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppTheme.radiusLg)),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            ...List.generate(_slotsCount, (i) {
              final isHour = i % 2 == 0;
              return Positioned(
                top: i * _slotHeight,
                left: 8,
                right: 8,
                child: Container(
                  height: isHour ? 1 : 0.5,
                  color: AppColors.borderSoft.withOpacity(isHour ? 0.55 : 0.28),
                ),
              );
            }),
            // Пустое место (в т.ч. справа от узких карточек) — новая запись.
            if (isGeneral && widget.onCreateAt != null)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  // onTapUp (не onTapDown): скролл не должен открывать создание.
                  onTapUp: (details) {
                    final dy = details.localPosition.dy;
                    var slot = (dy / _slotHeight).floor();
                    if (slot < 0) slot = 0;
                    if (slot >= _slotsCount) slot = _slotsCount - 1;
                    final totalMin = _startHour * 60 + slot * _slotMinutes;
                    final day = DateTime(
                      dayForCreate.year,
                      dayForCreate.month,
                      dayForCreate.day,
                    );
                    widget.onCreateAt!(
                      day,
                      TimeOfDay(hour: totalMin ~/ 60, minute: totalMin % 60),
                    );
                  },
                ),
              ),
            ..._buildCards(
              title,
              isGeneral,
              gridHeight,
              width,
              viewDay: viewDay,
              ordersOverride: ordersOverride,
            ),
            if (isGeneral && widget.onCreateAt != null)
              Positioned(
                top: 8,
                right: 8,
                child: IgnorePointer(
                  child: Icon(
                    Icons.add,
                    size: 14,
                    color: AppColors.textDim.withOpacity(0.28),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCards(
    String colTitle,
    bool isGeneral,
    double gridHeight,
    double colWidth, {
    DateTime? viewDay,
    List<Map<String, dynamic>>? ordersOverride,
  }) {
    final events = <Map<String, dynamic>>[];
    final day = viewDay ?? widget.selectedDate;
    final dayOrders = ordersOverride ?? _orders;

    String carLine(Map<String, dynamic> row) {
      final model = row['make_model']?.toString() ?? "";
      final plate = row['plate']?.toString() ?? "";
      if (model.isEmpty && plate.isEmpty) return "";
      if (plate.isEmpty) return model;
      if (model.isEmpty) return plate;
      return "$model · $plate";
    }

    bool hasDebt(Map<String, dynamic> row) {
      final price = (row['price'] as num?)?.toDouble() ?? 0;
      final paid = (row['paid_amount'] as num?)?.toDouble() ?? 0;
      return (price - paid) > 0.01;
    }

    if (isGeneral) {
      for (final o in dayOrders) {
        var startStr = o['start_time']?.toString();
        var endStr = o['end_time']?.toString();
        // Старые записи только с due_date/end_date — маркер 09:00 на этот день.
        if (startStr == null || startStr.trim().isEmpty) {
          final dayStr = DateFormat('yyyy-MM-dd').format(day);
          String dayOf(String? raw) {
            if (raw == null || raw.trim().isEmpty) return '';
            return raw.replaceAll('T', ' ').trim().substring(0, 10);
          }
          final dueDay = dayOf(o['due_date']?.toString());
          final endDay = dayOf(o['end_date']?.toString());
          if (dueDay != dayStr && endDay != dayStr) continue;
          startStr = '$dayStr 09:00:00';
          endStr = '$dayStr 10:00:00';
        }
        final clipped = _clipEventToViewDay(startStr, endStr, viewDay: day);
        if (clipped == null) continue;
        final fullStart = _tryParseDateTime(startStr, viewDay: day) ?? clipped.start;
        final fullEnd = _tryParseDateTime(endStr, viewDay: day) ?? clipped.end;
        events.add({
          'orderId': o['id'],
          'start': clipped.start,
          'end': clipped.end,
          'fullStart': fullStart,
          'fullEnd': fullEnd.isAfter(fullStart) ? fullEnd : fullStart.add(const Duration(minutes: 30)),
          'isTech': false,
          'draggable': true,
          'status': o['status']?.toString() ?? '',
          'hasDebt': hasDebt(o),
          'title': "${o['client_name']}",
          'subtitle': carLine(o),
        });
      }
    } else {
      for (final w in _workItems) {
        if ((w['workshop'] ?? '') != colTitle) continue;
        // Состав пакета оклейки не рисуем по зонам — одна карточка шапки.
        if (w['parent_id'] != null) continue;

        final clipped = _clipEventToViewDay(
          w['start_time']?.toString(),
          w['end_time']?.toString(),
          viewDay: day,
        );
        if (clipped == null) continue;
        final car = carLine(w);
        final workName = w['work_name']?.toString() ?? "";
        String work;
        bool isDone;
        if (isWrapPackageHeader(workName)) {
          final headerId = (w['item_id'] as num?)?.toInt();
          final kids = _workItems.where((x) => (x['parent_id'] as num?)?.toInt() == headerId).toList();
          final n = kids.length;
          work = n > 0 ? "Оклейка · $n поз." : "Оклейка";
          isDone = n > 0
              ? kids.every((x) => (x['is_done'] as num?)?.toInt() == 1)
              : (w['is_done'] as num?)?.toInt() == 1;
        } else {
          work = workName;
          isDone = (w['is_done'] as num?)?.toInt() == 1;
        }
        events.add({
          'orderId': w['order_id'],
          'start': clipped.start,
          'end': clipped.end,
          'isTech': false,
          'isDone': isDone,
          'status': w['status']?.toString() ?? '',
          'hasDebt': hasDebt(w),
          'title': "${w['client_name']}",
          'subtitle': car.isEmpty ? work : (work.isEmpty ? car : "$car · $work"),
        });
      }
      if (colTitle == "Мойка") {
        for (final o in dayOrders) {
          if (o['tech_wash_start'] == null) continue;
          final clipped = _clipEventToViewDay(
            o['tech_wash_start']?.toString(),
            o['tech_wash_end']?.toString(),
            viewDay: day,
          );
          if (clipped == null) continue;
          final car = carLine(o);
          events.add({
            'orderId': o['id'],
            'start': clipped.start,
            'end': clipped.end,
            'isTech': true,
            'status': o['status']?.toString() ?? '',
            'hasDebt': hasDebt(o),
            'title': "${o['client_name']}",
            'subtitle': car.isEmpty ? "Тех. мойка" : "$car · Тех. мойка",
          });
        }
      }
    }

    events.sort((a, b) {
      final c = (a['start'] as DateTime).compareTo(b['start'] as DateTime);
      if (c != 0) return c;
      return (a['end'] as DateTime).compareTo(b['end'] as DateTime);
    });

    // Дорожки: пересекающиеся заказы — в разные колонки (не друг на друге).
    final laneEnds = <DateTime>[];
    for (final e in events) {
      final start = e['start'] as DateTime;
      final end = e['end'] as DateTime;
      var lane = -1;
      for (var i = 0; i < laneEnds.length; i++) {
        if (!start.isBefore(laneEnds[i])) {
          lane = i;
          break;
        }
      }
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(end);
      } else {
        laneEnds[lane] = end;
      }
      e['lane'] = lane;
    }

    // Число колонок в кластере = max(lane)+1 среди всех взаимно пересекающихся.
    for (final e in events) {
      final start = e['start'] as DateTime;
      final end = e['end'] as DateTime;
      var maxLane = e['lane'] as int;
      for (final other in events) {
        if (!_overlaps(start, end, other['start'] as DateTime, other['end'] as DateTime)) {
          continue;
        }
        final ol = other['lane'] as int;
        if (ol > maxLane) maxLane = ol;
        // Расширяем кластер: кто пересекается с other — тоже учитываем их lane.
        for (final third in events) {
          if (_overlaps(
                other['start'] as DateTime,
                other['end'] as DateTime,
                third['start'] as DateTime,
                third['end'] as DateTime,
              ) &&
              (third['lane'] as int) > maxLane) {
            maxLane = third['lane'] as int;
          }
        }
      }
      e['groupLanes'] = maxLane + 1;
    }

    // Выравниваем groupLanes внутри кластера (все пересекающиеся видят одно число колонок).
    var changed = true;
    while (changed) {
      changed = false;
      for (final e in events) {
        for (final other in events) {
          if (!_overlaps(
            e['start'] as DateTime,
            e['end'] as DateTime,
            other['start'] as DateTime,
            other['end'] as DateTime,
          )) {
            continue;
          }
          final a = e['groupLanes'] as int;
          final b = other['groupLanes'] as int;
          if (a != b) {
            final m = a > b ? a : b;
            e['groupLanes'] = m;
            other['groupLanes'] = m;
            changed = true;
          }
        }
      }
    }

    // Ширина по тексту; параллельные карточки вплотную (без зазора).
    const padH = 14.0; // horizontal padding 7+7
    const borderW = 3.0; // left accent
    const edgePad = 6.0;
    final cards = <Widget>[];

    for (final e in events) {
      final start = e['start'] as DateTime;
      final isTech = e['isTech'] == true;
      final isDone = e['isDone'] == true;
      final hasDebt = e['hasDebt'] == true;
      final status = e['status']?.toString() ?? '';
      final statusColor = kOrderStatusColors[status] ?? AppColors.primary;
      final groupLanes = (e['groupLanes'] as int).clamp(1, 12);

      final timeStr = "${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}";
      final titleText = "$timeStr  ${e['title']}";
      final subtitleText = "${e['subtitle']}";

      final subtitleTint = isDone
          ? AppColors.textDim
          : (isTech
              ? const Color(0xFF5EEAD4)
              : Color.lerp(statusColor, Colors.white, 0.35) ?? const Color(0xFF93C5FD));

      final titleStyle = GoogleFonts.manrope(
        color: isDone ? AppColors.textDim : AppColors.text,
        fontSize: groupLanes >= 3 ? 10.5 : 12,
        fontWeight: FontWeight.w800,
        height: 1.15,
        decoration: isDone ? TextDecoration.lineThrough : null,
        decorationColor: AppColors.textDim,
      );
      final subtitleStyle = GoogleFonts.manrope(
        color: subtitleTint,
        fontSize: groupLanes >= 3 ? 9.5 : 11,
        fontWeight: FontWeight.w600,
        height: 1.15,
      );

      final titleW = _measureTextWidth(titleText, titleStyle);
      final subtitleW = subtitleText.isEmpty ? 0.0 : _measureTextWidth(subtitleText, subtitleStyle);
      final iconW = (isDone ? 15.0 : 0.0) + (hasDebt && !isDone ? 14.0 : 0.0);
      final extras = padH + borderW + iconW;
      e['statusColor'] = statusColor;
      e['hasDebt'] = hasDebt;
      // min — имя клиента целиком; preferred — ещё и авто/номер.
      final minW = (titleW + extras).clamp(56.0, colWidth - edgePad * 2);
      final preferred = ((titleW > subtitleW ? titleW : subtitleW) + extras)
          .clamp(minW, colWidth - edgePad * 2);
      e['titleText'] = titleText;
      e['subtitleText'] = subtitleText;
      e['titleStyle'] = titleStyle;
      e['subtitleStyle'] = subtitleStyle;
      e['minW'] = minW;
      e['preferredW'] = preferred;
    }

    // В кластере: вплотную без gap. На узком экране не жмём уже имени — режем subtitle.
    final laneWByEvent = <Map<String, dynamic>, double>{};
    final leftByEvent = <Map<String, dynamic>, double>{};
    for (final e in events) {
      final groupLanes = e['groupLanes'] as int;
      final lanePref = List<double>.filled(groupLanes, 56.0);
      final laneMin = List<double>.filled(groupLanes, 56.0);
      for (final other in events) {
        if (!_overlaps(
          e['start'] as DateTime,
          e['end'] as DateTime,
          other['start'] as DateTime,
          other['end'] as DateTime,
        )) {
          continue;
        }
        if ((other['groupLanes'] as int) != groupLanes) continue;
        final ol = other['lane'] as int;
        if (ol < 0 || ol >= groupLanes) continue;
        final pw = other['preferredW'] as double;
        final mw = other['minW'] as double;
        if (pw > lanePref[ol]) lanePref[ol] = pw;
        if (mw > laneMin[ol]) laneMin[ol] = mw;
      }
      final maxTotal = colWidth - edgePad * 2;
      var prefTotal = 0.0;
      var minTotal = 0.0;
      for (var i = 0; i < groupLanes; i++) {
        prefTotal += lanePref[i];
        minTotal += laneMin[i];
      }
      final laneW = List<double>.from(lanePref);
      if (prefTotal > maxTotal) {
        if (minTotal <= maxTotal) {
          // Влезают имена — берём min (время+клиент), номер может с ellipsis.
          for (var i = 0; i < groupLanes; i++) {
            laneW[i] = laneMin[i];
          }
        } else if (minTotal > 0) {
          final scale = maxTotal / minTotal;
          for (var i = 0; i < groupLanes; i++) {
            laneW[i] = laneMin[i] * scale;
          }
        }
      }
      final lane = e['lane'] as int;
      var left = edgePad;
      for (var i = 0; i < lane; i++) {
        left += laneW[i];
      }
      leftByEvent[e] = left;
      laneWByEvent[e] = laneW[lane];
    }

    for (final e in events) {
      final start = e['start'] as DateTime;
      final end = e['end'] as DateTime;
      final isTech = e['isTech'] == true;
      final isDone = e['isDone'] == true;
      final orderId = (e['orderId'] as num).toInt();
      final cardW = laneWByEvent[e]!;
      final left = leftByEvent[e]!;
      final titleText = e['titleText'] as String;
      final subtitleText = e['subtitleText'] as String;
      final titleStyle = e['titleStyle'] as TextStyle;
      final subtitleStyle = e['subtitleStyle'] as TextStyle;
      final canDrag = e['draggable'] == true && isGeneral;

      var top = _offsetForTime(start.hour, start.minute);
      var minutes = end.difference(start).inMinutes.toDouble();
      if (minutes < 30) minutes = 30;
      var height = minutes * _pixelsPerMinute;
      if (height < 44) height = 44;
      if (top < 0) top = 0;
      final maxBottom = gridHeight;
      if (top + height > maxBottom) {
        height = maxBottom - top - 2;
        if (height < 36) {
          height = 36;
          top = maxBottom - height - 2;
        }
      }

      final dragging = _dragOrderId == orderId;
      if (dragging) top += _dragDy;

      final hasDebt = e['hasDebt'] == true;
      final statusColor = (e['statusColor'] as Color?) ?? AppColors.primary;
      // Полоска слева = статус; долг — иконка + тонкая красная линия сверху.
      final accent = isDone
          ? AppColors.success
          : (isTech ? const Color(0xFF14B8A6) : statusColor);
      final fillBase = isDone
          ? AppColors.surface2
          : (isTech
              ? const Color(0xFF0F2E2A)
              : (Color.lerp(AppColors.surface2, statusColor, 0.22) ?? const Color(0xFF152A4A)));
      final fill = isDone ? fillBase.withOpacity(0.9) : fillBase;

      final cardBody = Opacity(
        opacity: isDone ? 0.6 : (dragging ? 0.92 : 1),
        child: Material(
          color: Colors.transparent,
          elevation: dragging ? 8 : 0,
          borderRadius: BorderRadius.circular(10),
          child: GestureDetector(
            onTap: dragging ? null : () => _openOrder(orderId),
            onLongPressStart: !canDrag
                ? null
                : (details) {
                    // Global Y: localOffset ломается, когда карточка двигается под пальцем → 08:00.
                    setState(() {
                      _dragOrderId = orderId;
                      _dragDy = 0;
                      _dragStartGlobalY = details.globalPosition.dy;
                      _dragFullStart = e['fullStart'] as DateTime? ?? start;
                      _dragFullEnd = e['fullEnd'] as DateTime? ?? end;
                    });
                  },
            onLongPressMoveUpdate: !canDrag
                ? null
                : (details) {
                    if (_dragOrderId != orderId || _dragStartGlobalY == null) return;
                    setState(() {
                      _dragDy = details.globalPosition.dy - _dragStartGlobalY!;
                    });
                  },
            onLongPressEnd: !canDrag
                ? null
                : (_) => _finishOrderDrag(orderId),
            onLongPressCancel: !canDrag
                ? null
                : () {
                    if (_dragOrderId == orderId) {
                      setState(() {
                        _dragOrderId = null;
                        _dragDy = 0;
                        _dragStartGlobalY = null;
                        _dragFullStart = null;
                        _dragFullEnd = null;
                      });
                    }
                  },
            child: Container(
              width: cardW,
              padding: const EdgeInsets.fromLTRB(8, 6, 7, 6),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  left: BorderSide(
                    color: (dragging ? AppColors.primary : accent).withOpacity(0.9),
                    width: 3,
                  ),
                  top: hasDebt && !isDone && !isTech
                      ? BorderSide(color: AppColors.danger.withOpacity(0.75), width: 1.5)
                      : BorderSide.none,
                ),
                boxShadow: isDone && !dragging
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(dragging ? 0.45 : 0.28),
                          blurRadius: dragging ? 14 : 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isDone) ...[
                        const Icon(Icons.check_circle, size: 12, color: AppColors.success),
                        const SizedBox(width: 3),
                      ] else if (hasDebt) ...[
                        const Icon(Icons.payments_outlined, size: 12, color: AppColors.danger),
                        const SizedBox(width: 3),
                      ],
                      Expanded(
                        child: Text(
                          titleText,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      ),
                    ],
                  ),
                  if (height >= 40 && subtitleText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitleText,
                        maxLines: height >= 56 ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: subtitleStyle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      cards.add(
        Positioned(
          top: top,
          left: left,
          width: cardW,
          height: height,
          child: cardBody,
        ),
      );
    }
    return cards;
  }

  String _fmtDbDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi:00';
  }

  Future<void> _finishOrderDrag(int orderId) async {
    final dy = _dragDy;
    final fullStart = _dragFullStart;
    final fullEnd = _dragFullEnd;
    setState(() {
      _dragOrderId = null;
      _dragDy = 0;
      _dragStartGlobalY = null;
      _dragFullStart = null;
      _dragFullEnd = null;
    });
    if (fullStart == null || fullEnd == null) return;

    final slotDelta = (dy / _slotHeight).round();
    if (slotDelta == 0) return;
    final shiftMin = slotDelta * _slotMinutes;

    // Просто сдвигаем исходный интервал — без привязки к 08:00 дня сетки
    // (старый clamp убивал время и ставил 08:00).
    var newStart = fullStart.add(Duration(minutes: shiftMin));
    var newEnd = fullEnd.add(Duration(minutes: shiftMin));
    if (!newEnd.isAfter(newStart)) {
      newEnd = newStart.add(const Duration(minutes: 30));
    }
    // Snap минут старта к шагу слота (0 или 30).
    final snap = ((newStart.minute + _slotMinutes ~/ 2) ~/ _slotMinutes) * _slotMinutes;
    if (snap == 60) {
      newStart = DateTime(newStart.year, newStart.month, newStart.day, newStart.hour + 1);
    } else {
      newStart = DateTime(newStart.year, newStart.month, newStart.day, newStart.hour, snap);
    }
    final durMin = fullEnd.difference(fullStart).inMinutes.clamp(30, 24 * 60);
    newEnd = newStart.add(Duration(minutes: durMin));

    final startStr = _fmtDbDateTime(newStart);
    final endStr = _fmtDbDateTime(newEnd);
    final due = DateFormat('yyyy-MM-dd').format(newStart);
    try {
      await DatabaseHelper().updateOrderSchedule(orderId, due, startStr, endStr, '');
      await DatabaseHelper().addOrderEvent(
        orderId,
        'Календарь: перенос на ${DateFormat('dd.MM HH:mm', 'ru').format(newStart)}'
        '–${DateFormat('HH:mm').format(newEnd)}',
      );
    } catch (e, st) {
      debugPrint('Calendar drag save: $e\n$st');
    }
    if (mounted) _loadData(showSpinner: false);
  }

  double _measureTextWidth(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: ui.TextDirection.ltr,
      ellipsis: '…',
    )..layout();
    // Небольшой запас: GoogleFonts на Android может чуть шире отрисовать.
    return painter.width + 6;
  }
}
