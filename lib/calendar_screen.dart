import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'database.dart';
import 'order_details_dialog.dart';

class CalendarScreen extends StatefulWidget {
  final DateTime selectedDate;
  /// Клик по пустому слоту в «Общей записи» → создать заказ на это время.
  final void Function(DateTime date, TimeOfDay time)? onCreateAt;

  const CalendarScreen({
    super.key,
    required this.selectedDate,
    this.onCreateAt,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _workItems = [];
  bool _isLoading = true;
  bool _showGeneral = true;
  int _loadGen = 0;

  /// Высота одного 30-минутного слота.
  final double _slotHeight = 36.0;
  final int _slotMinutes = 30;
  final double _colWidth = 200.0;
  final int _startHour = 8;
  final int _endHour = 22;

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
    // После первого кадра — иначе setState из initState/переключения тура может оборвать загрузку.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
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

  Future<void> _loadData() async {
    final gen = ++_loadGen;
    if (mounted) setState(() => _isLoading = true);
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

  /// Понимает форматы: "2026-07-31 15:30:00", "2026-07-31T15:30:00", "15:30"
  DateTime _parseDate(String? dtStr) {
    final fallback = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
      _startHour,
    );
    if (dtStr == null || dtStr.isEmpty) return fallback;
    try {
      final n = dtStr.replaceFirst('T', ' ').split('.').first.trim();
      final parsed = DateTime.parse(n.contains(' ') ? n.replaceFirst(' ', 'T') : n);
      return DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month,
        widget.selectedDate.day,
        parsed.hour,
        parsed.minute,
      );
    } catch (_) {
      try {
        final parts = dtStr.split(':');
        return DateTime(
          widget.selectedDate.year,
          widget.selectedDate.month,
          widget.selectedDate.day,
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
      } catch (_) {
        return fallback;
      }
    }
  }

  DateTime _ensureEnd(DateTime start, String? endStr) {
    var end = (endStr != null && endStr.isNotEmpty) ? _parseDate(endStr) : start.add(const Duration(hours: 1));
    if (!end.isAfter(start)) end = start.add(const Duration(minutes: 30));
    return end;
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

  @override
  Widget build(BuildContext context) {
    final gridHeight = _gridHeight;
    final statuses = STATUSES.where((s) => s != "Выдан").toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(
              children: [
                Text("Календарь", style: AppTheme.pageTitle),
                const SizedBox(width: 16),
                Text(
                  DateFormat('dd MMMM yyyy', 'ru').format(widget.selectedDate),
                  style: GoogleFonts.manrope(
                    color: AppColors.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
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
                    constraints: const BoxConstraints(minHeight: 40, minWidth: 140),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text("Общая запись", style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text("Детальное время", style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 16, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 56,
                          child: Column(
                            children: [
                              const SizedBox(height: 40),
                              ...List.generate(_slotsCount, (i) {
                                final totalMin = _startHour * 60 + i * _slotMinutes;
                                final h = totalMin ~/ 60;
                                final m = totalMin % 60;
                                final isHour = m == 0;
                                return SizedBox(
                                  height: _slotHeight,
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 2, right: 8),
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
                            ],
                          ),
                        ),
                        Expanded(
                          child: _showGeneral
                              ? _buildColumn("Общая запись", MediaQuery.of(context).size.width - 100, gridHeight, true)
                              : SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: statuses.map((s) => _buildColumn(s, _colWidth, gridHeight, false)).toList(),
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
  }

  Widget _buildColumn(String title, double width, double gridHeight, bool isGeneral) {
    return Container(
      width: width,
      height: gridHeight + 40,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            ...List.generate(_slotsCount, (i) {
              final isHour = i % 2 == 0;
              return Positioned(
                top: 40.0 + (i * _slotHeight),
                left: 0,
                right: 0,
                child: Container(
                  height: 1,
                  color: AppColors.border.withOpacity(isHour ? 0.75 : 0.4),
                ),
              );
            }),
            if (isGeneral && widget.onCreateAt != null)
              Positioned(
                top: 40,
                left: 0,
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
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
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 40,
              child: Container(
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.surface2,
                  border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
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
              ),
            ),
            ..._buildCards(title, isGeneral, gridHeight, width),
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
        final start = _parseDate(o['start_time']?.toString());
        final end = _ensureEnd(start, o['end_time']?.toString());
        events.add({
          'orderId': o['id'],
          'start': start,
          'end': end,
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

        final start = _parseDate(w['start_time']?.toString());
        final end = _ensureEnd(start, w['end_time']?.toString());
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
          'start': start,
          'end': end,
          'isTech': false,
          'isDone': isDone,
          'title': "${w['client_name']}",
          'subtitle': car.isEmpty ? work : (work.isEmpty ? car : "$car · $work"),
        });
      }
      if (colTitle == "Мойка") {
        for (final o in _orders) {
          if (o['tech_wash_start'] == null) continue;
          final start = _parseDate(o['tech_wash_start']?.toString());
          final end = _ensureEnd(start, o['tech_wash_end']?.toString());
          final car = carLine(o);
          events.add({
            'orderId': o['id'],
            'start': start,
            'end': end,
            'isTech': true,
            'title': "${o['client_name']}",
            'subtitle': car.isEmpty ? "Тех. мойка" : "$car · Тех. мойка",
          });
        }
      }
    }

    events.sort((a, b) => (a['start'] as DateTime).compareTo(b['start'] as DateTime));

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

    for (final e in events) {
      final start = e['start'] as DateTime;
      final end = e['end'] as DateTime;
      var groupLanes = 1;
      for (final other in events) {
        if (_overlaps(start, end, other['start'] as DateTime, other['end'] as DateTime)) {
          final ol = (other['lane'] as int) + 1;
          if (ol > groupLanes) groupLanes = ol;
        }
      }
      e['groupLanes'] = groupLanes;
    }

    const gap = 4.0;
    final cards = <Widget>[];

    for (final e in events) {
      final start = e['start'] as DateTime;
      final end = e['end'] as DateTime;
      final isTech = e['isTech'] == true;
      final isDone = e['isDone'] == true;
      final orderId = e['orderId'] as int;
      final lane = e['lane'] as int;
      final groupLanes = e['groupLanes'] as int;

      var top = 40.0 + _offsetForTime(start.hour, start.minute);
      var minutes = end.difference(start).inMinutes.toDouble();
      if (minutes < 30) minutes = 30;
      var height = minutes * _pixelsPerMinute;
      if (height < 44) height = 44;
      if (top < 40) top = 40;
      final maxBottom = 40 + gridHeight;
      if (top + height > maxBottom) {
        height = maxBottom - top - 2;
        if (height < 36) {
          height = 36;
          top = maxBottom - height - 2;
        }
      }

      final usable = colWidth - 10 - gap * (groupLanes - 1);
      final cardW = usable / groupLanes;
      final left = 5 + lane * (cardW + gap);
      final timeStr = "${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}";

      cards.add(
        Positioned(
          top: top,
          left: left,
          width: cardW,
          height: height,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openOrder(orderId),
              borderRadius: BorderRadius.circular(8),
              child: Opacity(
                opacity: isDone ? 0.55 : 1,
                child: Container(
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
                  child: ClipRect(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Flexible(
                          child: Row(
                            children: [
                              if (isDone) ...[
                                const Icon(Icons.check_circle, size: 12, color: AppColors.success),
                                const SizedBox(width: 3),
                              ],
                              Expanded(
                                child: Text(
                                  "$timeStr  ${e['title']}",
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.manrope(
                                    color: isDone ? AppColors.textDim : AppColors.text,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    height: 1.15,
                                    decoration: isDone ? TextDecoration.lineThrough : null,
                                    decorationColor: AppColors.textDim,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (height >= 40)
                          Flexible(
                            child: Text(
                              "${e['subtitle']}",
                              maxLines: height >= 56 ? 2 : 1,
                              softWrap: true,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                color: isDone
                                    ? AppColors.textDim
                                    : (isTech ? const Color(0xFF5EEAD4) : const Color(0xFFBFDBFE)),
                                fontSize: 10,
                                height: 1.15,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return cards;
  }
}
