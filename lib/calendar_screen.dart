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
  bool _isLoading = true;
  bool _showGeneral = true;
  int _loadGen = 0;

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

  Future<void> _loadData({bool showSpinner = true}) async {
    final gen = ++_loadGen;
    if (showSpinner && mounted) setState(() => _isLoading = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(widget.selectedDate);
      final orders = await DatabaseHelper().getOrdersForCalendar(dateStr);
      final workItems = await DatabaseHelper().getOrderItemsForCalendar(dateStr);
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _orders = orders;
        _workItems = workItems;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('CalendarScreen._loadData: $e\n$st');
      if (mounted && gen == _loadGen) {
        setState(() {
          _orders = [];
          _workItems = [];
          _isLoading = false;
        });
      }
    }
  }

  /// Полная дата-время: "2026-07-31 15:30:00", ISO, либо только "15:30" → выбранный день.
  DateTime? _tryParseDateTime(String? dtStr) {
    if (dtStr == null || dtStr.trim().isEmpty) return null;
    try {
      final n = dtStr.replaceFirst('T', ' ').split('.').first.trim();
      if (n.contains(' ')) {
        return DateTime.parse(n.replaceFirst(' ', 'T'));
      }
      final parts = n.split(':');
      return DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month,
        widget.selectedDate.day,
        int.parse(parts[0]),
        parts.length > 1 ? int.parse(parts[1]) : 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Обрезает интервал заказа до видимого дня сетки (08:00–22:30).
  /// `null` — событие не пересекает выбранный день.
  ({DateTime start, DateTime end})? _clipEventToViewDay(String? startStr, String? endStr) {
    final day = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
    );
    final dayEnd = day.add(const Duration(days: 1));
    final gridStart = DateTime(day.year, day.month, day.day, _startHour);
    final gridEnd = DateTime(day.year, day.month, day.day, _endHour)
        .add(Duration(minutes: _slotMinutes));

    final rawStart = _tryParseDateTime(startStr);
    if (rawStart == null) return null;
    var rawEnd = _tryParseDateTime(endStr);
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
    final next = _dateOnly(widget.selectedDate).add(Duration(days: delta));
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
          tooltip: "Предыдущий день",
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
          tooltip: "Следующий день",
          onPressed: widget.onDateChanged == null ? null : () => _shiftDay(1),
          icon: const Icon(Icons.chevron_right, color: AppColors.primary),
        ),
      ],
    );
  }

  Widget _modeToggle({required bool mobile}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: ToggleButtons(
        isSelected: [_showGeneral, !_showGeneral],
        onPressed: (index) {
          setState(() => _showGeneral = index == 0);
          _loadData();
        },
        color: AppColors.textMuted,
        selectedColor: AppColors.text,
        fillColor: AppColors.primarySoft,
        borderColor: Colors.transparent,
        selectedBorderColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radius - 2),
        constraints: BoxConstraints(minHeight: 40, minWidth: mobile ? 120 : 140),
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
              style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: mobile ? 12 : 13),
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
                      const SizedBox(height: 10),
                      _modeToggle(mobile: true),
                    ],
                  )
                : Row(
                    children: [
                      Text("Календарь", style: AppTheme.pageTitle),
                      const SizedBox(width: 12),
                      Expanded(child: _dayNavigator(fontSize: 18)),
                      const SizedBox(width: 12),
                      _modeToggle(mobile: false),
                    ],
                  ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(mobile ? 12 : 24, 0, mobile ? 12 : 24, 10),
            child: Text(
              'Клик по пустому слоту в «Общей записи» — создать заказ на это время',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final timeGutter = mobile ? 44.0 : 56.0;
                      final padH = mobile ? 8.0 : 12.0;
                      final padRight = mobile ? 12.0 : 16.0;
                      final detailColW = mobile ? 160.0 : _colWidth;
                      // Явная ширина колонки — без Expanded внутри ScrollView
                      // (на mobile maxWidth иногда 0 → clamp падал и карточки исчезали).
                      final bodyColW = (constraints.maxWidth - timeGutter - padH - padRight - 8)
                          .clamp(160.0, 4000.0);

                      return Padding(
                        padding: EdgeInsets.fromLTRB(padH, 8, padRight, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Липкие заголовки колонок — не уезжают при скролле вниз
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
                                    SizedBox(
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
                                    ),
                                    _showGeneral
                                        ? _buildColumnBody(
                                            'Общая запись',
                                            bodyColW,
                                            gridHeight,
                                            true,
                                          )
                                        : Expanded(
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
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnHeader(String title, double width) {
    return Container(
      width: width,
      height: _headerHeight,
      margin: const EdgeInsets.only(right: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        title,
        style: GoogleFonts.manrope(
          color: AppColors.text,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildColumnBody(String title, double width, double gridHeight, bool isGeneral) {
    return Container(
      width: width,
      height: gridHeight,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            ...List.generate(_slotsCount, (i) {
              final isHour = i % 2 == 0;
              return Positioned(
                top: i * _slotHeight,
                left: 0,
                right: 0,
                child: Container(
                  height: 1,
                  color: AppColors.border.withOpacity(isHour ? 0.75 : 0.4),
                ),
              );
            }),
            // Пустое место (в т.ч. справа от узких карточек) — новая запись.
            if (isGeneral && widget.onCreateAt != null)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (details) {
                    final dy = details.localPosition.dy;
                    var slot = (dy / _slotHeight).floor();
                    if (slot < 0) slot = 0;
                    if (slot >= _slotsCount) slot = _slotsCount - 1;
                    final totalMin = _startHour * 60 + slot * _slotMinutes;
                    final day = DateTime(
                      widget.selectedDate.year,
                      widget.selectedDate.month,
                      widget.selectedDate.day,
                    );
                    widget.onCreateAt!(
                      day,
                      TimeOfDay(hour: totalMin ~/ 60, minute: totalMin % 60),
                    );
                  },
                ),
              ),
            ..._buildCards(title, isGeneral, gridHeight, width),
            if (isGeneral && widget.onCreateAt != null)
              Positioned(
                top: 6,
                right: 6,
                child: IgnorePointer(
                  child: Icon(
                    Icons.add,
                    size: 14,
                    color: AppColors.textDim.withOpacity(0.4),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCards(String colTitle, bool isGeneral, double gridHeight, double colWidth) {
    final events = <Map<String, dynamic>>[];

    String carLine(Map<String, dynamic> row) {
      final model = row['make_model']?.toString() ?? "";
      final plate = row['plate']?.toString() ?? "";
      if (model.isEmpty && plate.isEmpty) return "";
      if (plate.isEmpty) return model;
      if (model.isEmpty) return plate;
      return "$model · $plate";
    }

    if (isGeneral) {
      for (final o in _orders) {
        var startStr = o['start_time']?.toString();
        var endStr = o['end_time']?.toString();
        // Старые записи только с due_date — маркер на выбранный день.
        if (startStr == null || startStr.trim().isEmpty) {
          final dayStr = DateFormat('yyyy-MM-dd').format(widget.selectedDate);
          startStr = '$dayStr 09:00:00';
          endStr = '$dayStr 10:00:00';
        }
        final clipped = _clipEventToViewDay(startStr, endStr);
        if (clipped == null) continue;
        events.add({
          'orderId': o['id'],
          'start': clipped.start,
          'end': clipped.end,
          'isTech': false,
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
          'title': "${w['client_name']}",
          'subtitle': car.isEmpty ? work : (work.isEmpty ? car : "$car · $work"),
        });
      }
      if (colTitle == "Мойка") {
        for (final o in _orders) {
          if (o['tech_wash_start'] == null) continue;
          final clipped = _clipEventToViewDay(
            o['tech_wash_start']?.toString(),
            o['tech_wash_end']?.toString(),
          );
          if (clipped == null) continue;
          final car = carLine(o);
          events.add({
            'orderId': o['id'],
            'start': clipped.start,
            'end': clipped.end,
            'isTech': true,
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
    const padH = 12.0; // horizontal padding 6+6
    const borderW = 2.4;
    const edgePad = 5.0;
    final cards = <Widget>[];

    for (final e in events) {
      final start = e['start'] as DateTime;
      final isTech = e['isTech'] == true;
      final isDone = e['isDone'] == true;
      final groupLanes = (e['groupLanes'] as int).clamp(1, 12);

      final timeStr = "${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}";
      final titleText = "$timeStr  ${e['title']}";
      final subtitleText = "${e['subtitle']}";

      final titleStyle = GoogleFonts.manrope(
        color: isDone ? AppColors.textDim : AppColors.text,
        fontSize: groupLanes >= 3 ? 10 : 11,
        fontWeight: FontWeight.w700,
        height: 1.15,
        decoration: isDone ? TextDecoration.lineThrough : null,
        decorationColor: AppColors.textDim,
      );
      final subtitleStyle = GoogleFonts.manrope(
        color: isDone
            ? AppColors.textDim
            : (isTech ? const Color(0xFF5EEAD4) : const Color(0xFFBFDBFE)),
        fontSize: groupLanes >= 3 ? 9 : 10,
        height: 1.15,
      );

      final titleW = _measureTextWidth(titleText, titleStyle);
      final subtitleW = subtitleText.isEmpty ? 0.0 : _measureTextWidth(subtitleText, subtitleStyle);
      final iconW = isDone ? 15.0 : 0.0;
      final extras = padH + borderW + iconW;
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
      final orderId = e['orderId'] as int;
      final cardW = laneWByEvent[e]!;
      final left = leftByEvent[e]!;
      final titleText = e['titleText'] as String;
      final subtitleText = e['subtitleText'] as String;
      final titleStyle = e['titleStyle'] as TextStyle;
      final subtitleStyle = e['subtitleStyle'] as TextStyle;

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

      final cardBody = Opacity(
        opacity: isDone ? 0.55 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openOrder(orderId),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: cardW,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              decoration: BoxDecoration(
                color: isDone
                    ? AppColors.surface2
                    : (isTech ? const Color(0xFF12352F) : AppColors.primarySoft),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDone
                      ? AppColors.success.withOpacity(0.45)
                      : (isTech ? const Color(0xFF14B8A6) : AppColors.primary.withOpacity(0.75)),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isDone) ...[
                        const Icon(Icons.check_circle, size: 12, color: AppColors.success),
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
