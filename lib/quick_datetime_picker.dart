import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Быстрый выбор даты и времени — без крутилки.
/// Карточка «Когда?»: крупный итог, неделя, часы утро/день/вечер, минуты.
class QuickDateTimePicker {
  static Future<String?> pickDateTime(
    BuildContext context, {
    DateTime? initial,
  }) async {
    final result = await showDialog<_PickResult>(
      context: context,
      useRootNavigator: true,
      builder: (context) => _QuickPickerDialog(
        mode: _PickMode.dateTime,
        initial: initial ?? DateTime.now(),
      ),
    );
    return result?.asDbString();
  }

  static Future<DateTime?> pickDate(
    BuildContext context, {
    DateTime? initial,
  }) async {
    final result = await showDialog<_PickResult>(
      context: context,
      useRootNavigator: true,
      builder: (context) => _QuickPickerDialog(
        mode: _PickMode.dateOnly,
        initial: initial ?? DateTime.now(),
      ),
    );
    return result?.dateOnly;
  }

  static Future<TimeOfDay?> pickTime(
    BuildContext context, {
    TimeOfDay? initial,
  }) async {
    final now = DateTime.now();
    final init = DateTime(
      now.year,
      now.month,
      now.day,
      initial?.hour ?? now.hour,
      initial?.minute ?? 0,
    );
    final result = await showDialog<_PickResult>(
      context: context,
      useRootNavigator: true,
      builder: (context) => _QuickPickerDialog(
        mode: _PickMode.timeOnly,
        initial: init,
      ),
    );
    if (result == null) return null;
    return TimeOfDay(hour: result.hour, minute: result.minute);
  }
}

enum _PickMode { dateTime, dateOnly, timeOnly }

class _PickResult {
  final DateTime day;
  final int hour;
  final int minute;

  _PickResult(this.day, this.hour, this.minute);

  DateTime get dateOnly => DateTime(day.year, day.month, day.day);

  String asDbString() {
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    final hh = hour.toString().padLeft(2, '0');
    final mm = minute.toString().padLeft(2, '0');
    return "$y-$m-$d $hh:$mm:00";
  }
}

class _QuickPickerDialog extends StatefulWidget {
  final _PickMode mode;
  final DateTime initial;

  const _QuickPickerDialog({required this.mode, required this.initial});

  @override
  State<_QuickPickerDialog> createState() => _QuickPickerDialogState();
}

class _QuickPickerDialogState extends State<_QuickPickerDialog> {
  late DateTime _day;
  int? _hour;
  int? _minute;
  bool _showFullCalendar = false;

  static const _morning = [8, 9, 10, 11, 12];
  static const _dayHours = [13, 14, 15, 16, 17];
  static const _evening = [18, 19, 20, 21, 22];
  static const _minutes = [0, 15, 30, 45];
  static const _weekDays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  void initState() {
    super.initState();
    _day = DateTime(widget.initial.year, widget.initial.month, widget.initial.day);
    final h = widget.initial.hour.clamp(8, 22);
    _hour = h;
    final m = widget.initial.minute;
    if (m < 8) {
      _minute = 0;
    } else if (m < 23) {
      _minute = 15;
    } else if (m < 38) {
      _minute = 30;
    } else if (m < 53) {
      _minute = 45;
    } else {
      _minute = 0;
      _hour = (h + 1).clamp(8, 22);
    }
  }

  bool get _needTime => widget.mode != _PickMode.dateOnly;
  bool get _needDate => widget.mode != _PickMode.timeOnly;
  bool get _timeReady => _hour != null && _minute != null;

  void _confirm() {
    if (_needTime && !_timeReady) return;
    Navigator.pop(context, _PickResult(_day, _hour ?? 9, _minute ?? 0));
  }

  String get _title {
    switch (widget.mode) {
      case _PickMode.dateOnly:
        return "Дата";
      case _PickMode.timeOnly:
        return "Время";
      case _PickMode.dateTime:
        return "Когда?";
    }
  }

  /// 7 дней начиная с сегодня
  List<DateTime> get _weekStrip {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(7, (i) => today.add(Duration(days: i)));
  }

  Widget _hourChip(int h) {
    final selected = _hour == h;
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 6),
      child: InkWell(
        onTap: () => setState(() => _hour = h),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 48,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF3B82F6) : const Color(0xFF2A2A2E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? const Color(0xFF3B82F6) : const Color(0xFF444444)),
          ),
          child: Text(
            h.toString().padLeft(2, '0'),
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }

  Widget _hourBlock(String label, List<int> hours) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Wrap(children: hours.map(_hourChip).toList()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dateText = DateFormat('dd.MM.yyyy').format(_day);
    final timeText = _timeReady
        ? "${_hour!.toString().padLeft(2, '0')}:${_minute!.toString().padLeft(2, '0')}"
        : "--:--";

    return Dialog(
      backgroundColor: const Color(0xFF1A1A1F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),

                // --- Крупный итог ---
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D2137),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      if (_needDate)
                        Expanded(
                          child: Text(
                            dateText,
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                        ),
                      if (_needTime)
                        Text(
                          timeText,
                          style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 28, fontWeight: FontWeight.w800),
                        ),
                    ],
                  ),
                ),

                if (_needDate) ...[
                  const SizedBox(height: 18),
                  const Text("День", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _pill("Сегодня", _day == today, () {
                        setState(() {
                          _day = today;
                          _showFullCalendar = false;
                        });
                      }),
                      const SizedBox(width: 8),
                      _pill("Завтра", _day == tomorrow, () {
                        setState(() {
                          _day = tomorrow;
                          _showFullCalendar = false;
                        });
                      }),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() => _showFullCalendar = !_showFullCalendar),
                        child: Text(
                          _showFullCalendar ? "Скрыть" : "Календарь",
                          style: const TextStyle(color: Color(0xFF60A5FA)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Полоска 7 дней
                  SizedBox(
                    height: 64,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _weekStrip.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final d = _weekStrip[i];
                        final selected = d == _day;
                        final wd = _weekDays[d.weekday - 1];
                        return InkWell(
                          onTap: () => setState(() {
                            _day = d;
                            _showFullCalendar = false;
                          }),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 52,
                            decoration: BoxDecoration(
                              color: selected ? const Color(0xFF3B82F6) : const Color(0xFF2A2A2E),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected ? const Color(0xFF3B82F6) : const Color(0xFF444444),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(wd, style: TextStyle(color: selected ? Colors.white70 : Colors.grey, fontSize: 11)),
                                const SizedBox(height: 2),
                                Text(
                                  "${d.day}",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_showFullCalendar) ...[
                    const SizedBox(height: 8),
                    Theme(
                      data: ThemeData.dark().copyWith(
                        colorScheme: const ColorScheme.dark(primary: Color(0xFF3B82F6)),
                      ),
                      child: CalendarDatePicker(
                        initialDate: _day,
                        firstDate: DateTime(2023),
                        lastDate: DateTime(2030),
                        onDateChanged: (d) => setState(() {
                          _day = DateTime(d.year, d.month, d.day);
                        }),
                      ),
                    ),
                  ],
                ],

                if (_needTime) ...[
                  const SizedBox(height: 18),
                  const Text("Время", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _hourBlock("Утро", _morning),
                  _hourBlock("День", _dayHours),
                  _hourBlock("Вечер", _evening),
                  const SizedBox(height: 4),
                  const Text("Минуты", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: _minutes.map((m) {
                      final selected = _minute == m;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: InkWell(
                            onTap: () {
                              setState(() => _minute = m);
                              if (widget.mode == _PickMode.timeOnly) {
                                Future.microtask(_confirm);
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected ? const Color(0xFF22C55E) : const Color(0xFF2A2A2E),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected ? const Color(0xFF22C55E) : const Color(0xFF444444),
                                ),
                              ),
                              child: Text(
                                ":${m.toString().padLeft(2, '0')}",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],

                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Отмена", style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (!_needTime || _timeReady)
                              ? const Color(0xFF3B82F6)
                              : const Color(0xFF334155),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: (!_needTime || _timeReady) ? _confirm : null,
                        child: const Text("Готово", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF3B82F6) : const Color(0xFF2A2A2E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? const Color(0xFF3B82F6) : const Color(0xFF444444)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
