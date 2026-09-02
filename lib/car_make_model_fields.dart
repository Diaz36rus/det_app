import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';
import 'car_brands.dart';
import 'car_catalog.dart';

/// Пара полей «Марка» + «Модель» с автоподстановкой.
/// Модели только для выбранной марки; при смене марки список моделей обновляется сразу.
class CarMakeModelFields extends StatefulWidget {
  const CarMakeModelFields({
    super.key,
    this.initialMakeModel = '',
    this.onChanged,
    this.enabled = true,
    this.isDense = true,
    this.stacked = false,
    this.extraMakes = const [],
    this.extraModelsByMake = const {},
    this.makeFieldKey,
    this.modelFieldKey,
  });

  final String initialMakeModel;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool isDense;
  final bool stacked;
  final List<String> extraMakes;
  /// slug/ключ марки → модели, встречавшиеся в заказах (не общий пул).
  final Map<String, List<String>> extraModelsByMake;
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

  /// Меняется при смене марки → пересоздаёт Autocomplete моделей.
  int _modelEpoch = 0;
  String _makeFingerprint = '';

  String get makeModel => CarCatalog.join(_makeCtrl.text, _modelCtrl.text);

  @override
  void initState() {
    super.initState();
    final parts = CarCatalog.split(widget.initialMakeModel);
    _makeCtrl = TextEditingController(text: parts.make);
    _modelCtrl = TextEditingController(text: parts.model);
    _makeFingerprint = _fingerprint(_makeCtrl.text);
    _makeCtrl.addListener(_onMakeEdited);
    _modelCtrl.addListener(_emit);
  }

  @override
  void dispose() {
    _makeCtrl.removeListener(_onMakeEdited);
    _modelCtrl.removeListener(_emit);
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _makeFocus.dispose();
    _modelFocus.dispose();
    super.dispose();
  }

  String _fingerprint(String make) {
    final slug = CarBrands.slugFor(make.trim());
    if (slug != null) return slug;
    return CarCatalog.extrasKey(make);
  }

  void _emit() => widget.onChanged?.call(makeModel);

  void _onMakeEdited() {
    final fp = _fingerprint(_makeCtrl.text);
    if (fp != _makeFingerprint) {
      _makeFingerprint = fp;
      final model = _modelCtrl.text.trim();
      if (model.isNotEmpty &&
          !CarCatalog.modelBelongsToMake(
            _makeCtrl.text,
            model,
            modelsByMake: widget.extraModelsByMake,
          )) {
        _modelCtrl.removeListener(_emit);
        _modelCtrl.text = '';
        _modelCtrl.addListener(_emit);
      }
      // Пересоздаём optionsBuilder моделей сразу, без ожидания ввода в поле модели.
      if (mounted) setState(() => _modelEpoch++);
    }
    _emit();
  }

  void setMakeModel(String value) {
    final parts = CarCatalog.split(value);
    _makeCtrl.removeListener(_onMakeEdited);
    _modelCtrl.removeListener(_emit);
    if (_makeCtrl.text != parts.make) _makeCtrl.text = parts.make;
    if (_modelCtrl.text != parts.model) _modelCtrl.text = parts.model;
    _makeFingerprint = _fingerprint(_makeCtrl.text);
    _makeCtrl.addListener(_onMakeEdited);
    _modelCtrl.addListener(_emit);
    if (mounted) setState(() => _modelEpoch++);
    _emit();
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
      key: fieldKey,
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: optionsBuilder,
      onSelected: (v) {
        controller.value = TextEditingValue(
          text: v,
          selection: TextSelection.collapsed(offset: v.length),
        );
      },
      fieldViewBuilder: (context, textCtrl, focus, onSubmit) {
        return TextField(
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
        // Шире оверлей + свой скролл, чтобы родительский ScrollView формы не перехватывал жест.
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, minWidth: 260, maxWidth: 360),
              child: NotificationListener<ScrollNotification>(
                onNotification: (_) => true,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  primary: false,
                  shrinkWrap: false,
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
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final make = _makeCtrl.text.trim();
    final makeField = _field(
      fieldKey: widget.makeFieldKey,
      controller: _makeCtrl,
      focusNode: _makeFocus,
      label: 'Марка',
      hint: 'начните вводить…',
      optionsBuilder: (tv) => CarCatalog.filterBrands(
        tv.text,
        extra: widget.extraMakes,
      ),
    );

    final modelField = _field(
      fieldKey: ValueKey('car_model_$_modelEpoch'),
      controller: _modelCtrl,
      focusNode: _modelFocus,
      label: 'Модель',
      hint: CarCatalog.modelHintFor(make),
      optionsBuilder: (tv) => CarCatalog.filterModels(
        _makeCtrl.text,
        tv.text,
        modelsByMake: widget.extraModelsByMake,
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
