import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';

/// Зона кузова для оклейки.
enum WrapZone { popular, front, side, rear }

/// Сторона для парных деталей.
enum WrapSide { pair, left, right }

/// Финиш для хрома / эмблем / глянца (+ «Снять» где нужно).
enum WrapFinish { film, antichrome, darken, remove }

extension WrapZoneX on WrapZone {
  String get label => switch (this) {
        WrapZone.popular => 'Популярные',
        WrapZone.front => 'Перед',
        WrapZone.side => 'Борта',
        WrapZone.rear => 'Зад',
      };

  /// Сегмент в имени услуги: «Оклейка · Перед · …»
  String? get nameToken => switch (this) {
        WrapZone.popular => null,
        WrapZone.front => 'Перед',
        WrapZone.side => 'Борт',
        WrapZone.rear => 'Зад',
      };
}

extension WrapSideX on WrapSide {
  String get label => switch (this) {
        WrapSide.pair => 'Пара',
        WrapSide.left => 'Л',
        WrapSide.right => 'П',
      };

  String get nameToken => label;
}

extension WrapFinishX on WrapFinish {
  String get label => switch (this) {
        WrapFinish.film => 'Плёнка',
        WrapFinish.antichrome => 'Антихром',
        WrapFinish.darken => 'Притемнение',
        WrapFinish.remove => 'Снять',
      };

  String get nameToken => label;
}

class WrapPart {
  final String id;
  final String title;
  final WrapZone zone;
  final bool sided;
  final bool hasFinish;
  /// Доп. опция «Снять» (надписи, шильдики и т.п.).
  final bool hasRemove;
  /// Полная оклейка: переключатель «Целиком» / «С детализацией».
  final bool hasDetailing;
  /// Позиция ещё в разработке (автовыбор зон и т.п.).
  final bool wip;

  const WrapPart({
    required this.id,
    required this.title,
    required this.zone,
    this.sided = false,
    this.hasFinish = false,
    this.hasRemove = false,
    this.hasDetailing = false,
    this.wip = false,
  });

  /// Базовое имя в прайсе (без стороны/финиша).
  String get catalogName {
    final z = zone.nameToken;
    if (z == null) return 'Оклейка · $title';
    return 'Оклейка · $z · $title';
  }
}

/// Собирает имя позиции для заказа.
String buildWrapLineName(
  WrapPart part, {
  WrapSide side = WrapSide.pair,
  WrapFinish finish = WrapFinish.film,
  bool withDetailing = false,
}) {
  final buf = StringBuffer(part.catalogName);
  if (part.sided && side != WrapSide.pair) {
    buf.write(' · ${side.nameToken}');
  } else if (part.sided) {
    buf.write(' · Пара');
  }
  if (part.hasDetailing && withDetailing) {
    buf.write(' · С детализацией');
  }
  if ((part.hasFinish || part.hasRemove) && finish != WrapFinish.film) {
    buf.write(' · ${finish.nameToken}');
  }
  return buf.toString();
}

/// Ключ выбора в UI (часть + сторона + финиш).
String wrapSelectionKey(WrapPart part, WrapSide side, WrapFinish finish) {
  return '${part.id}|${side.name}|${finish.name}';
}

/// Полный каталог оклейки (после редакции).
const List<WrapPart> kWrapCatalog = [
  // —— Популярные ——
  WrapPart(id: 'pop_hood', title: 'Капот', zone: WrapZone.popular),
  WrapPart(id: 'pop_fbumper', title: 'Передний бампер', zone: WrapZone.popular),
  WrapPart(id: 'pop_lights', title: 'Фары', zone: WrapZone.popular, sided: true),
  WrapPart(id: 'pop_mirrors', title: 'Зеркала', zone: WrapZone.popular, sided: true),
  WrapPart(id: 'pop_ffender', title: 'Крылья передние', zone: WrapZone.popular, sided: true),
  WrapPart(id: 'pop_sills', title: 'Пороги', zone: WrapZone.popular, sided: true),
  WrapPart(id: 'pop_roof_strip', title: 'Крыша (полоса)', zone: WrapZone.popular),
  WrapPart(
    id: 'pop_full',
    title: 'Полная оклейка кузова',
    zone: WrapZone.popular,
    hasDetailing: true,
    wip: true,
  ),
  WrapPart(id: 'pop_salon', title: 'Салон', zone: WrapZone.popular, wip: true),
  WrapPart(id: 'pop_apillar', title: 'Стойки лобового', zone: WrapZone.popular, sided: true),
  WrapPart(id: 'pop_handles', title: 'Зоны под ручками', zone: WrapZone.popular, sided: true),

  // —— Перед ——
  WrapPart(id: 'f_hood', title: 'Капот (целиком)', zone: WrapZone.front),
  WrapPart(id: 'f_hood_part', title: 'Капот (часть / нос)', zone: WrapZone.front),
  WrapPart(id: 'f_bumper', title: 'Передний бампер (целиком)', zone: WrapZone.front),
  WrapPart(id: 'f_bumper_top', title: 'Передний бампер (верхняя губа)', zone: WrapZone.front),
  WrapPart(id: 'f_bumper_bot', title: 'Передний бампер (нижняя губа)', zone: WrapZone.front),
  WrapPart(id: 'f_fender', title: 'Крыло переднее', zone: WrapZone.front, sided: true),
  WrapPart(id: 'f_arch', title: 'Расширитель арки передней', zone: WrapZone.front, sided: true),
  WrapPart(id: 'f_headlight', title: 'Фара', zone: WrapZone.front, sided: true),
  WrapPart(id: 'f_fog', title: 'ПТФ / ДХО', zone: WrapZone.front, sided: true),
  WrapPart(id: 'f_grille', title: 'Решётка радиатора', zone: WrapZone.front),
  WrapPart(id: 'f_grille_chrome', title: 'Хром / декор решётки', zone: WrapZone.front, hasFinish: true),
  WrapPart(id: 'f_emblem', title: 'Эмблема передняя', zone: WrapZone.front, hasFinish: true),
  WrapPart(id: 'f_apillar', title: 'Стойка лобового', zone: WrapZone.front, sided: true),
  WrapPart(id: 'f_roof_strip', title: 'Крыша (полоса)', zone: WrapZone.front),
  WrapPart(id: 'f_roof_full', title: 'Крыша (целиком)', zone: WrapZone.front),
  WrapPart(id: 'f_cowl', title: 'Жабо / пластик под лобовым', zone: WrapZone.front),

  // —— Борта ——
  WrapPart(id: 's_door_f', title: 'Дверь передняя', zone: WrapZone.side, sided: true),
  WrapPart(id: 's_door_r', title: 'Дверь задняя', zone: WrapZone.side, sided: true),
  WrapPart(id: 's_door_cover', title: 'Накладка двери', zone: WrapZone.side, sided: true),
  WrapPart(id: 's_door_mold', title: 'Молдинг двери', zone: WrapZone.side, sided: true, hasFinish: true),
  WrapPart(id: 's_handle_zone', title: 'Зона под ручкой', zone: WrapZone.side, sided: true),
  WrapPart(id: 's_handle', title: 'Ручка двери', zone: WrapZone.side, sided: true, hasFinish: true),
  WrapPart(id: 's_door_edge', title: 'Торцы / кромки дверей', zone: WrapZone.side, sided: true),
  WrapPart(id: 's_sill_out', title: 'Порог снаружи', zone: WrapZone.side, sided: true),
  WrapPart(id: 's_sill_in_s', title: 'Порог внутри (короткий)', zone: WrapZone.side, sided: true),
  WrapPart(id: 's_sill_in_l', title: 'Порог внутри (длинный)', zone: WrapZone.side, sided: true),
  WrapPart(id: 's_sill_cover', title: 'Накладка порога', zone: WrapZone.side, sided: true, hasFinish: true),
  WrapPart(id: 's_rfender', title: 'Крыло заднее / боковина', zone: WrapZone.side, sided: true),
  WrapPart(id: 's_rarch', title: 'Расширитель арки задней', zone: WrapZone.side, sided: true),
  WrapPart(id: 's_mirror', title: 'Зеркало (корпус)', zone: WrapZone.side, sided: true, hasFinish: true),
  WrapPart(id: 's_mirror_detail', title: 'Зеркало (детализация)', zone: WrapZone.side, sided: true),
  WrapPart(id: 's_repeater', title: 'Повторитель поворота', zone: WrapZone.side, sided: true),
  WrapPart(id: 's_gloss_pillars', title: 'Стойки глянцевые', zone: WrapZone.side, hasFinish: true),
  WrapPart(id: 's_window_mold', title: 'Молдинг окон', zone: WrapZone.side, hasFinish: true),
  WrapPart(id: 's_fuel', title: 'Лючок бензобака / зарядки', zone: WrapZone.side, hasFinish: true),

  // —— Зад ——
  WrapPart(id: 'r_trunk', title: 'Крышка / дверь багажника', zone: WrapZone.rear),
  WrapPart(id: 'r_trunk_edge', title: 'Крышка багажника (нижняя кромка)', zone: WrapZone.rear),
  WrapPart(id: 'r_bumper', title: 'Задний бампер (целиком)', zone: WrapZone.rear),
  WrapPart(id: 'r_load', title: 'Задний бампер (зона погрузки)', zone: WrapZone.rear),
  WrapPart(id: 'r_diffuser', title: 'Задний бампер (диффузор)', zone: WrapZone.rear),
  WrapPart(id: 'r_sand', title: 'Зона пескоструя заднего бампера', zone: WrapZone.rear),
  WrapPart(id: 'r_light', title: 'Фонарь задний', zone: WrapZone.rear, sided: true),
  WrapPart(id: 'r_reflector', title: 'Катафот / отражатель', zone: WrapZone.rear, sided: true),
  WrapPart(id: 'r_brake', title: 'Доп. стоп-сигнал', zone: WrapZone.rear),
  WrapPart(id: 'r_emblem', title: 'Эмблема / шильдик задний', zone: WrapZone.rear, hasFinish: true),
  WrapPart(id: 'r_letters', title: 'Надпись модели / буквы', zone: WrapZone.rear, hasFinish: true, hasRemove: true),
  WrapPart(id: 'r_spoiler', title: 'Спойлер / антикрыло', zone: WrapZone.rear, hasFinish: true),
  WrapPart(id: 'r_visor', title: 'Козырёк заднего стекла', zone: WrapZone.rear),
  WrapPart(id: 'r_exhaust', title: 'Накладка выхлопа / насадки', zone: WrapZone.rear, sided: true, hasFinish: true),
];

List<WrapPart> wrapPartsFor(WrapZone zone) =>
    kWrapCatalog.where((p) => p.zone == zone).toList(growable: false);

/// Seed-строки для SERVICES_TREE / миграции (базовые имена, fp=0).
List<Map<String, dynamic>> wrapServicesTreeEntries() {
  return kWrapCatalog
      .map(
        (p) => <String, dynamic>{
          'cat': 'Оклейка (Пленка)',
          'name': p.catalogName,
          'p1': 0,
          'p2': 0,
          'p3': 0,
          'p4': 0,
          'fp': 0,
        },
      )
      .toList();
}

/// Результат редактора оклейки.
class WrapPackageDraft {
  final List<String> zoneNames;
  final double packagePrice;

  const WrapPackageDraft({required this.zoneNames, required this.packagePrice});
}

class _Sel {
  WrapSide side;
  WrapFinish finish;
  bool withDetailing;
  _Sel({
    this.side = WrapSide.pair,
    this.finish = WrapFinish.film,
    this.withDetailing = false,
  });
}

/// Редактор состава оклейки: популярные + Перед/Борта/Зад.
/// [onApply] — сохранить и закрыть; если null, показывает только чеклист (для встраивания).
class WrapPackageEditor extends StatefulWidget {
  final Set<String> initiallySelected;
  final double initialPrice;
  final bool dark;
  final ValueChanged<WrapPackageDraft>? onApply;
  final VoidCallback? onCancel;
  final bool showActions;

  const WrapPackageEditor({
    super.key,
    this.initiallySelected = const {},
    this.initialPrice = 0,
    this.dark = false,
    this.onApply,
    this.onCancel,
    this.showActions = true,
  });

  @override
  State<WrapPackageEditor> createState() => WrapPackageEditorState();
}

class WrapPackageEditorState extends State<WrapPackageEditor> {
  late final TextEditingController _priceCtrl;
  late final TextEditingController _customCtrl;
  final Map<String, _Sel> _selected = {}; // partId -> options
  final Set<String> _extraNames = {}; // свои / уже в заказе вне каталога

  Color get _fg => widget.dark ? Colors.white : AppColors.text;
  Color get _muted => widget.dark ? Colors.white70 : AppColors.textDim;
  Color get _card => widget.dark ? Colors.black.withOpacity(0.35) : AppColors.surface2;
  Color get _border => widget.dark ? Colors.white24 : AppColors.border;
  Color get _accent => widget.dark ? const Color(0xFF86EFAC) : AppColors.primary;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
      text: widget.initialPrice > 0
          ? (widget.initialPrice % 1 == 0
              ? widget.initialPrice.toInt().toString()
              : widget.initialPrice.toStringAsFixed(2))
          : '',
    );
    _customCtrl = TextEditingController();
    _hydrateFromNames(widget.initiallySelected);
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  void _hydrateFromNames(Set<String> names) {
    _selected.clear();
    _extraNames.clear();
    for (final name in names) {
      final parsed = _parseLineName(name);
      if (parsed != null) {
        _selected[parsed.$1.id] = _Sel(
          side: parsed.$2,
          finish: parsed.$3,
          withDetailing: parsed.$4,
        );
      } else if (name.trim().isNotEmpty && name.trim() != 'Оклейка') {
        _extraNames.add(name.trim());
      }
    }
  }

  /// Пытается сопоставить строку заказа с позицией каталога.
  (WrapPart, WrapSide, WrapFinish, bool)? _parseLineName(String raw) {
    var name = raw.trim();
    if (!name.startsWith('Оклейка ·')) return null;

    var side = WrapSide.pair;
    var finish = WrapFinish.film;
    var withDetailing = false;
    if (name.endsWith(' · Снять')) {
      finish = WrapFinish.remove;
      name = name.substring(0, name.length - ' · Снять'.length);
    } else if (name.endsWith(' · Антихром')) {
      finish = WrapFinish.antichrome;
      name = name.substring(0, name.length - ' · Антихром'.length);
    } else if (name.endsWith(' · Притемнение')) {
      finish = WrapFinish.darken;
      name = name.substring(0, name.length - ' · Притемнение'.length);
    }
    if (name.endsWith(' · С детализацией')) {
      withDetailing = true;
      name = name.substring(0, name.length - ' · С детализацией'.length);
    }
    if (name.endsWith(' · Пара')) {
      side = WrapSide.pair;
      name = name.substring(0, name.length - ' · Пара'.length);
    } else if (name.endsWith(' · Л')) {
      side = WrapSide.left;
      name = name.substring(0, name.length - ' · Л'.length);
    } else if (name.endsWith(' · П')) {
      side = WrapSide.right;
      name = name.substring(0, name.length - ' · П'.length);
    }

    for (final p in kWrapCatalog) {
      if (p.catalogName == name) {
        return (p, side, finish, withDetailing);
      }
    }
    return null;
  }

  List<String> get selectedNames {
    final out = <String>[];
    for (final e in _selected.entries) {
      WrapPart? part;
      for (final p in kWrapCatalog) {
        if (p.id == e.key) {
          part = p;
          break;
        }
      }
      if (part == null) continue;
      out.add(buildWrapLineName(
        part,
        side: e.value.side,
        finish: e.value.finish,
        withDetailing: e.value.withDetailing,
      ));
    }
    out.addAll(_extraNames);
    out.sort();
    return out;
  }

  WrapPackageDraft get draft {
    final price = double.tryParse(_priceCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    return WrapPackageDraft(zoneNames: selectedNames, packagePrice: price);
  }

  void apply() {
    widget.onApply?.call(draft);
  }

  int _countInZone(WrapZone zone) {
    var n = 0;
    for (final id in _selected.keys) {
      for (final p in kWrapCatalog) {
        if (p.id == id && p.zone == zone) {
          n++;
          break;
        }
      }
    }
    // свои с префиксом зоны
    final token = zone.nameToken;
    if (token != null) {
      n += _extraNames.where((e) => e.contains(' · $token · ')).length;
    }
    return n;
  }

  void _togglePart(WrapPart part, bool on) {
    if (part.wip) return;
    setState(() {
      if (on) {
        _selected[part.id] = _Sel();
      } else {
        _selected.remove(part.id);
      }
    });
  }

  void _addCustom(WrapZone zone) {
    final title = _customCtrl.text.trim();
    if (title.isEmpty || zone == WrapZone.popular) return;
    final z = zone.nameToken!;
    final name = title.startsWith('Оклейка') ? title : 'Оклейка · $z · $title';
    setState(() {
      _extraNames.add(name);
      _customCtrl.clear();
    });
  }

  Future<void> _promptCustom(WrapZone zone) async {
    _customCtrl.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Своя позиция · ${zone.label}',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: AppColors.text),
        ),
        content: TextField(
          controller: _customCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Название детали',
            hintText: 'например: Карбон на пороги',
            isDense: true,
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Добавить')),
        ],
      ),
    );
    if (ok == true) _addCustom(zone);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _priceCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: GoogleFonts.manrope(color: _fg, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            labelText: 'Сумма пакета, ₽',
            labelStyle: TextStyle(color: _muted),
            isDense: true,
            filled: true,
            fillColor: _card,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              borderSide: BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              borderSide: BorderSide(color: _accent, width: 1.5),
            ),
            helperText: selectedNames.isEmpty
                ? 'Отметьте зоны — сумма одна на весь пакет'
                : 'Выбрано: ${selectedNames.length}',
            helperStyle: TextStyle(color: _muted, fontSize: 11),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _zoneBlock(WrapZone.popular, initiallyExpanded: true),
              _zoneBlock(WrapZone.front),
              _zoneBlock(WrapZone.side),
              _zoneBlock(WrapZone.rear),
              if (_extraNames.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Свои / из заказа', style: GoogleFonts.manrope(color: _muted, fontSize: 12, fontWeight: FontWeight.w700)),
                for (final name in _extraNames.toList()..sort())
                  CheckboxListTile(
                    dense: true,
                    value: true,
                    activeColor: _accent,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(name.replaceFirst(RegExp(r'^Оклейка\s*·\s*'), ''), style: GoogleFonts.manrope(color: _fg, fontSize: 13)),
                    onChanged: (_) => setState(() => _extraNames.remove(name)),
                  ),
              ],
            ],
          ),
        ),
        if (widget.showActions) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              if (widget.onCancel != null)
                TextButton(
                  onPressed: widget.onCancel,
                  child: Text('Отмена', style: GoogleFonts.manrope(color: _muted)),
                ),
              const Spacer(),
              ElevatedButton(
                onPressed: apply,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                child: Text(
                  selectedNames.isEmpty ? 'Убрать оклейку' : 'Готово',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _zoneBlock(WrapZone zone, {bool initiallyExpanded = false}) {
    final parts = wrapPartsFor(zone);
    final count = zone == WrapZone.popular
        ? _selected.keys.where((id) => kWrapCatalog.any((p) => p.id == id && p.zone == WrapZone.popular)).length
        : _countInZone(zone);

    if (zone == WrapZone.popular) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Популярные',
            style: GoogleFonts.manrope(color: _muted, fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            'В работе: Салон, полная оклейка, полная оклейка с детализацией — автовыбор зон позже',
            style: GoogleFonts.manrope(
              color: _muted.withOpacity(0.85),
              fontSize: 10,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          for (final p in parts) _partTile(p),
          const SizedBox(height: 8),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: _border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            unselectedWidgetColor: _muted,
          ),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            iconColor: _accent,
            collapsedIconColor: _muted,
            title: Text(
              zone.label,
              style: GoogleFonts.manrope(color: _fg, fontWeight: FontWeight.w800, fontSize: 14),
            ),
            subtitle: Text(
              count > 0 ? 'выбрано $count' : '${parts.length} позиций',
              style: GoogleFonts.manrope(color: _muted, fontSize: 11),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _promptCustom(zone),
                  icon: Icon(Icons.add, size: 18, color: _accent),
                  label: Text(
                    'Своя позиция',
                    style: GoogleFonts.manrope(color: _accent, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
              for (final p in parts) _partTile(p),
            ],
          ),
        ),
      ),
    );
  }

  Widget _partTile(WrapPart part) {
    final on = _selected.containsKey(part.id);
    final sel = _selected[part.id];

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? _accent.withOpacity(0.55) : Colors.transparent),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Checkbox(
                    value: on,
                    activeColor: _accent,
                    side: BorderSide(color: _muted),
                    onChanged: part.wip ? null : (v) => _togglePart(part, v == true),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: part.wip ? null : () => _togglePart(part, !on),
                    child: Opacity(
                      opacity: part.wip ? 0.55 : 1,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              part.title,
                              style: GoogleFonts.manrope(
                                color: _fg,
                                fontSize: 13,
                                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (part.wip) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.55)),
                              ),
                              child: Text(
                                'скоро',
                                style: GoogleFonts.manrope(
                                  color: const Color(0xFFFBBF24),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (on && part.sided) _sideChips(part, sel!),
              ],
            ),
            if (on && part.hasDetailing)
              Padding(
                padding: const EdgeInsets.only(left: 36, bottom: 4),
                child: _detailingChips(sel!),
              ),
            if (on && (part.hasFinish || part.hasRemove))
              Padding(
                padding: const EdgeInsets.only(left: 36, bottom: 4),
                child: _finishChips(part, sel!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _detailingChips(_Sel sel) {
    Widget chip(String label, bool detailing) {
      final active = sel.withDetailing == detailing;
      return InkWell(
        onTap: () => setState(() => sel.withDetailing = detailing),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: active ? _accent.withOpacity(0.25) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: active ? _accent : _border),
          ),
          child: Text(
            label,
            style: GoogleFonts.manrope(color: _fg, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return Wrap(
      children: [
        chip('Целиком', false),
        chip('С детализацией', true),
      ],
    );
  }

  Widget _sideChips(WrapPart part, _Sel sel) {
    Widget chip(WrapSide s) {
      final active = sel.side == s;
      return InkWell(
        onTap: () => setState(() => sel.side = s),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: active ? _accent.withOpacity(0.25) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: active ? _accent : _border),
          ),
          child: Text(
            s.label,
            style: GoogleFonts.manrope(
              color: _fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip(WrapSide.pair),
        const SizedBox(width: 4),
        chip(WrapSide.left),
        const SizedBox(width: 4),
        chip(WrapSide.right),
      ],
    );
  }

  Widget _finishChips(WrapPart part, _Sel sel) {
    Widget chip(WrapFinish f) {
      final active = sel.finish == f;
      return InkWell(
        onTap: () => setState(() => sel.finish = f),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: active ? _accent.withOpacity(0.25) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: active ? _accent : _border),
          ),
          child: Text(
            f.label,
            style: GoogleFonts.manrope(color: _fg, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return Wrap(
      children: [
        if (part.hasFinish) ...[
          chip(WrapFinish.film),
          chip(WrapFinish.antichrome),
          chip(WrapFinish.darken),
        ],
        if (part.hasRemove) chip(WrapFinish.remove),
      ],
    );
  }
}
