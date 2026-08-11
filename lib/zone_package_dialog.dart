import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'responsive.dart';
import 'wrap_catalog.dart';

/// Результат редактора зонального пакета (оклейка / тонировка).
class ZonePackageResult {
  final List<String> zoneNames;
  final double packagePrice;

  const ZonePackageResult({required this.zoneNames, required this.packagePrice});
}

/// Чеклист зон + одна сумма за весь пакет (на конкретное авто).
class ZonePackageDialog extends StatefulWidget {
  final String kind; // wrap | tint
  final List<Map<String, dynamic>> catalogZones;
  final Set<String> initiallySelected;
  final double initialPrice;

  const ZonePackageDialog({
    super.key,
    required this.kind,
    required this.catalogZones,
    this.initiallySelected = const {},
    this.initialPrice = 0,
  });

  static Future<ZonePackageResult?> open(
    BuildContext context, {
    required String kind,
    required List<Map<String, dynamic>> catalogZones,
    Set<String> initiallySelected = const {},
    double initialPrice = 0,
  }) {
    return showDialog<ZonePackageResult>(
      context: context,
      builder: (_) => ZonePackageDialog(
        kind: kind,
        catalogZones: catalogZones,
        initiallySelected: initiallySelected,
        initialPrice: initialPrice,
      ),
    );
  }

  @override
  State<ZonePackageDialog> createState() => _ZonePackageDialogState();
}

class _ZonePackageDialogState extends State<ZonePackageDialog> {
  late final Set<String> _selected;
  late final TextEditingController _priceCtrl;
  late final List<Map<String, dynamic>> _tintZones;

  String get _title => widget.kind == 'tint' ? 'Тонировка' : 'Оклейка';

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initiallySelected};
    _priceCtrl = TextEditingController(
      text: widget.initialPrice > 0
          ? (widget.initialPrice % 1 == 0
              ? widget.initialPrice.toInt().toString()
              : widget.initialPrice.toStringAsFixed(2))
          : '',
    );
    _tintZones = List<Map<String, dynamic>>.from(widget.catalogZones);
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  String _label(String name) {
    return name.replaceFirst(RegExp(r'^Тонировка\s*·\s*'), '');
  }

  Widget _zoneTile(Map<String, dynamic> s) {
    final name = (s['name'] ?? '').toString();
    final checked = _selected.contains(name);
    return CheckboxListTile(
      dense: true,
      value: checked,
      activeColor: AppColors.primary,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        _label(name),
        style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
      ),
      onChanged: (v) {
        setState(() {
          if (v == true) {
            _selected.add(name);
          } else {
            _selected.remove(name);
          }
        });
      },
    );
  }

  void _saveTint() {
    final price = double.tryParse(_priceCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    Navigator.pop(
      context,
      ZonePackageResult(
        zoneNames: _selected.toList()..sort(),
        packagePrice: price,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = AppResponsive.isMobile(context);

    if (widget.kind == 'wrap') {
      return AlertDialog(
        backgroundColor: AppColors.surface,
        insetPadding: AppResponsive.dialogInsetPadding(context),
        title: Text(
          _title,
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: AppColors.text),
        ),
        content: SizedBox(
          width: mobile ? AppResponsive.dialogWidth(context, desktop: 560) : 560,
          height: mobile ? MediaQuery.sizeOf(context).height * 0.7 : 560,
          child: WrapPackageEditor(
            initiallySelected: widget.initiallySelected,
            initialPrice: widget.initialPrice,
            onApply: (draft) {
              Navigator.pop(
                context,
                ZonePackageResult(
                  zoneNames: draft.zoneNames,
                  packagePrice: draft.packagePrice,
                ),
              );
            },
            onCancel: () => Navigator.pop(context),
          ),
        ),
      );
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Отметьте зоны. Сумма — одна на весь пакет (под это авто).',
          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13, height: 1.35),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _priceCtrl,
          autofocus: false,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Сумма пакета, ₽',
            isDense: true,
            helperText: _selected.isEmpty
                ? 'Без зон пакет будет удалён'
                : 'Выбрано зон: ${_selected.length}',
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            children: [
              Text(
                'Зоны',
                style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              for (final s in _tintZones) _zoneTile(s),
              ...() {
                final catalogNames = widget.catalogZones.map((s) => (s['name'] ?? '').toString()).toSet();
                final extras = _selected.where((n) => !catalogNames.contains(n)).toList()..sort();
                if (extras.isEmpty) return <Widget>[];
                return [
                  const SizedBox(height: 8),
                  Text(
                    'Уже в заказе',
                    style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  for (final name in extras)
                    CheckboxListTile(
                      dense: true,
                      value: true,
                      activeColor: AppColors.primary,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        _label(name),
                        style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      onChanged: (v) {
                        setState(() {
                          if (v != true) _selected.remove(name);
                        });
                      },
                    ),
                ];
              }(),
            ],
          ),
        ),
      ],
    );

    return AlertDialog(
      backgroundColor: AppColors.surface,
      insetPadding: AppResponsive.dialogInsetPadding(context),
      title: Text(
        _title,
        style: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: AppColors.text),
      ),
      content: SizedBox(
        width: mobile ? AppResponsive.dialogWidth(context, desktop: 440) : 440,
        height: mobile ? MediaQuery.sizeOf(context).height * 0.62 : 480,
        child: body,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: _saveTint,
          child: Text(
            _selected.isEmpty ? 'Убрать пакет' : 'Сохранить',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
