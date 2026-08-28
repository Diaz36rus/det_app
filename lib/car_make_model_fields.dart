import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';
import 'car_catalog.dart';

/// Пара полей «Марка» + «Модель» с автоподстановкой.
/// Свои [TextEditingController] — ввод не сбрасывается при rebuild родителя.
/// Программная подстановка: [CarMakeModelFieldsState.setMakeModel] через [GlobalKey].
class CarMakeModelFields extends StatefulWidget {
  const CarMakeModelFields({
    super.key,
    this.initialMakeModel = '',
    this.onChanged,
    this.enabled = true,
    this.isDense = true,
    this.stacked = false,
    this.extraMakes = const [],
    this.extraModels = const [],
    this.makeFieldKey,
    this.modelFieldKey,
  });

  final String initialMakeModel;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool isDense;
  final bool stacked;
  final List<String> extraMakes;
  final List<String> extraModels;
  final Key? makeFieldKey;
  final Key? modelFieldKey;

  @override
  State<CarMakeModelFields> createState() => CarMakeModelFieldsState();
}

class CarMakeModelFieldsState extends State<CarMakeModelFields> {
  late final TextEditingController _makeCtrl;
  late final TextEditingController _modelCtrl;
  final _makeFocus = FocusNode();
  final _modelFocus = FocusNode();

  String get makeModel => CarCatalog.join(_makeCtrl.text, _modelCtrl.text);

  @override
  void initState() {
    super.initState();
    final parts = CarCatalog.split(widget.initialMakeModel);
    _makeCtrl = TextEditingController(text: parts.make);
    _modelCtrl = TextEditingController(text: parts.model);
    _makeCtrl.addListener(_emit);
    _modelCtrl.addListener(_emit);
  }

  @override
  void dispose() {
    _makeCtrl.removeListener(_emit);
    _modelCtrl.removeListener(_emit);
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _makeFocus.dispose();
    _modelFocus.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged?.call(makeModel);

  /// Подставить «Марка Модель» без потери фокуса у других полей формы.
  void setMakeModel(String value) {
    final parts = CarCatalog.split(value);
    if (_makeCtrl.text != parts.make) _makeCtrl.text = parts.make;
    if (_modelCtrl.text != parts.model) _modelCtrl.text = parts.model;
  }

  void clear() => setMakeModel('');

  Widget _field({
    required Key? fieldKey,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required Iterable<String> Function(TextEditingValue) optionsBuilder,
  }) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: optionsBuilder,
      onSelected: (v) {
        controller.text = v;
        controller.selection = TextSelection.collapsed(offset: v.length);
      },
      fieldViewBuilder: (context, textCtrl, focus, onSubmit) {
        return TextField(
          key: fieldKey,
          controller: textCtrl,
          focusNode: focus,
          enabled: widget.enabled,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            isDense: widget.isDense,
          ),
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => onSubmit(),
        );
      },
      optionsViewBuilder: (context, onSelected, opts) {
        final list = opts.toList();
        if (list.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, minWidth: 240),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final opt = list[i];
                  return ListTile(
                    dense: true,
                    title: Text(
                      opt,
                      style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13),
                    ),
                    onTap: () => onSelected(opt),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final makeField = _field(
      fieldKey: widget.makeFieldKey,
      controller: _makeCtrl,
      focusNode: _makeFocus,
      label: 'Марка',
      hint: 'Toyota, BMW…',
      optionsBuilder: (tv) => CarCatalog.filterBrands(
        tv.text,
        extra: widget.extraMakes,
      ),
    );

    final modelField = _field(
      fieldKey: widget.modelFieldKey,
      controller: _modelCtrl,
      focusNode: _modelFocus,
      label: 'Модель',
      hint: _makeCtrl.text.trim().isEmpty ? 'Сначала марка' : 'Camry, X5…',
      optionsBuilder: (tv) => CarCatalog.filterModels(
        _makeCtrl.text,
        tv.text,
        extra: widget.extraModels,
      ),
    );

    if (widget.stacked) {
      return Column(
        children: [
          makeField,
          const SizedBox(height: 10),
          modelField,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: makeField),
        const SizedBox(width: 10),
        Expanded(child: modelField),
      ],
    );
  }
}
