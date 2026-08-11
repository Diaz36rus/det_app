import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';
import 'app_toast.dart';
import 'database.dart';

/// Расход плёнки по заказу (м.п.). В цехе «Оклейка» — collapsible для мастера.
class OrderWrapFilmsPanel extends StatefulWidget {
  final int orderId;
  final bool collapsible;
  final bool initiallyExpanded;

  const OrderWrapFilmsPanel({
    super.key,
    required this.orderId,
    this.collapsible = false,
    this.initiallyExpanded = true,
  });

  @override
  State<OrderWrapFilmsPanel> createState() => _OrderWrapFilmsPanelState();
}

class _FilmRow {
  int filmId;
  final TextEditingController metersCtrl;
  final FocusNode metersFocus;

  _FilmRow({required this.filmId, required String metersText})
      : metersCtrl = TextEditingController(text: metersText),
        metersFocus = FocusNode();

  double get meters {
    final t = metersCtrl.text.trim().replaceAll(',', '.');
    return double.tryParse(t) ?? 0;
  }

  void dispose() {
    metersCtrl.dispose();
    metersFocus.dispose();
  }

  Map<String, dynamic> toMap() => {'filmId': filmId, 'meters': meters};
}

class _OrderWrapFilmsPanelState extends State<OrderWrapFilmsPanel> {
  List<Map<String, dynamic>> _catalog = [];
  final List<_FilmRow> _rows = [];
  bool _loading = true;
  bool _saving = false;
  late bool _expanded;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _load();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  String _fmtMeters(double m) {
    if (m == m.roundToDouble()) return m.toStringAsFixed(0);
    return m.toStringAsFixed(1);
  }

  void _clearRows() {
    for (final r in _rows) {
      r.dispose();
    }
    _rows.clear();
  }

  Future<void> _load() async {
    try {
      final catalog = await DatabaseHelper().listWrapFilms();
      final current = await DatabaseHelper().getOrderWrapFilms(widget.orderId);
      if (!mounted) return;
      _clearRows();
      for (final r in current) {
        final meters = (r['meters'] as num?)?.toDouble() ?? 0;
        final row = _FilmRow(
          filmId: (r['film_id'] as num).toInt(),
          metersText: _fmtMeters(meters),
        );
        row.metersFocus.addListener(() => _onMetersFocus(row));
        _rows.add(row);
      }
      setState(() {
        _catalog = catalog;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppToast(context, 'Плёнки: не удалось загрузить — $e');
    }
  }

  void _onMetersFocus(_FilmRow row) {
    if (!row.metersFocus.hasFocus) {
      unawaited(_save(showOk: false));
    }
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_save(showOk: false));
    });
  }

  Future<void> _save({bool showOk = false}) async {
    if (_saving) return;
    _saving = true;
    try {
      final payload = _rows.map((r) => r.toMap()).toList();
      await DatabaseHelper().setOrderWrapFilms(widget.orderId, payload);
      if (showOk && mounted) {
        showAppToast(context, 'Расход плёнки сохранён');
        setState(() {});
      }
    } catch (e) {
      if (mounted) showAppToast(context, 'Не сохранилось: $e');
    } finally {
      _saving = false;
    }
  }

  double get _totalMeters => _rows.fold<double>(0, (s, r) => s + r.meters);

  Future<void> _addFilmToCatalog() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Новая плёнка', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(ctx, v),
          decoration: const InputDecoration(
            labelText: 'Название',
            hintText: 'например Avery SW900',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    // Не dispose ctrl до закрытия диалога — на мобилке иначе гонка.
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (trimmed.isEmpty) return;

    try {
      final id = await DatabaseHelper().addWrapFilm(trimmed);
      final catalog = await DatabaseHelper().listWrapFilms();
      if (!mounted) return;
      final row = _FilmRow(filmId: id, metersText: '');
      row.metersFocus.addListener(() => _onMetersFocus(row));
      setState(() {
        _catalog = catalog;
        _rows.add(row);
        _expanded = true;
      });
      await _save(showOk: true);
      // Фокус на метры — сразу ввести расход.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) row.metersFocus.requestFocus();
      });
    } catch (e) {
      if (mounted) showAppToast(context, 'Плёнка не добавлена: $e');
    }
  }

  Future<void> _addRow() async {
    if (_catalog.isEmpty) {
      await _addFilmToCatalog();
      return;
    }
    final row = _FilmRow(
      filmId: (_catalog.first['id'] as num).toInt(),
      metersText: '',
    );
    row.metersFocus.addListener(() => _onMetersFocus(row));
    setState(() {
      _rows.add(row);
      _expanded = true;
    });
    await _save(showOk: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) row.metersFocus.requestFocus();
    });
  }

  Widget _headerButton() {
    final n = _rows.length;
    final meters = _totalMeters;
    final subtitle = n == 0
        ? 'Не заполнено — укажите расход'
        : '$n поз. · ${meters.toStringAsFixed(1)} м.п.';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(
                Icons.layers_outlined,
                size: 20,
                color: n == 0 ? AppColors.primary : AppColors.success,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Плёнки · расход',
                      style: GoogleFonts.manrope(
                        color: AppColors.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.manrope(
                        color: n == 0 ? AppColors.textMuted : AppColors.success,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (_saving)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                )
              else
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rowCard(int index) {
    final row = _rows[index];
    final value = _catalog.any((f) => (f['id'] as num).toInt() == row.filmId) ? row.filmId : null;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<int>(
            value: value,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Плёнка', isDense: true),
            items: _catalog
                .map(
                  (film) => DropdownMenuItem<int>(
                    value: (film['id'] as num).toInt(),
                    child: Text(film['name'].toString(), overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (id) async {
              if (id == null) return;
              setState(() => row.filmId = id);
              await _save(showOk: false);
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.metersCtrl,
                  focusNode: row.metersFocus,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Расход, м.п.',
                    hintText: 'например 12.5',
                    isDense: true,
                  ),
                  onChanged: (_) => _scheduleSave(),
                  onSubmitted: (_) => _save(showOk: true),
                ),
              ),
              IconButton(
                tooltip: 'Удалить',
                onPressed: () async {
                  setState(() {
                    row.dispose();
                    _rows.removeAt(index);
                  });
                  await _save(showOk: false);
                },
                icon: const Icon(Icons.remove_circle_outline, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body() {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, widget.collapsible ? 4 : 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ElevatedButton.icon(
                onPressed: _addRow,
                icon: const Icon(Icons.add, size: 18),
                label: Text('Строка', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              ),
              OutlinedButton(
                onPressed: _addFilmToCatalog,
                child: Text('Новая плёнка', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: () => _save(showOk: true),
                child: Text('Сохранить', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (_catalog.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Сначала «Новая плёнка» — название в каталог, потом расход в м.п.',
                style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
              ),
            )
          else if (_rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Нажмите «Строка» или «Новая плёнка».',
                style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
              ),
            )
          else
            for (var i = 0; i < _rows.length; i++) _rowCard(i),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: _rows.isEmpty ? AppColors.primary.withOpacity(0.35) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.collapsible) _headerButton(),
          if (!widget.collapsible || _expanded) ...[
            if (widget.collapsible) const Divider(height: 1),
            _body(),
          ],
        ],
      ),
    );
  }
}
