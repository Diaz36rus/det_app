import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'service_category_browser.dart';

/// Явный маппинг категория → asset (имена файлов в assets/images/).
const Map<String, String> kCategoryImageAssets = {
  'Мойка': 'assets/images/wash.jpg',
  'Химчистка': 'assets/images/dry_cleaning.jpg',
  'Полировка': 'assets/images/polish.jpg',
  'Керамика и Силант': 'assets/images/ceramic.jpg',
  'Антидождь': 'assets/images/rain_repellent.jpg',
  'Оклейка (Пленка)': 'assets/images/wrapping.jpg',
  'Тонировка': 'assets/images/tinting.jpg',
};

bool _isWrapRiskZone(Map<String, dynamic> s) {
  return (s['name'] ?? '').toString().contains(' · ЗР · ');
}

String? imageAssetForCategory(String category) {
  if (kCategoryImageAssets.containsKey(category)) {
    return kCategoryImageAssets[category];
  }
  final n = category.toLowerCase();
  if (n.contains('оклей')) return 'assets/images/wrapping.jpg';
  if (n.contains('тонир')) return 'assets/images/tinting.jpg';
  if (n.contains('мойк')) return 'assets/images/wash.jpg';
  if (n.contains('химчист')) return 'assets/images/dry_cleaning.jpg';
  if (n.contains('полир')) return 'assets/images/polish.jpg';
  if (n.contains('керамик') || n.contains('силант')) return 'assets/images/ceramic.jpg';
  if (n.contains('антидожд') || n.contains('krytex')) return 'assets/images/rain_repellent.jpg';
  return null;
}

/// Сетка категорий: тап → Hero-раскрытие по центру с услугами на фоне картинки.
class ServiceCategoryGallery extends StatelessWidget {
  final List<Map<String, dynamic>> services;
  final String carCategory;
  final Set<String> selectedNames;
  final void Function(String name, double price, String category) onToggle;

  const ServiceCategoryGallery({
    super.key,
    required this.services,
    required this.carCategory,
    required this.selectedNames,
    required this.onToggle,
  });

  Future<void> _openCategory(
    BuildContext context,
    String category,
    List<Map<String, dynamic>> items,
  ) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withOpacity(0.72),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (ctx, anim, secondary) {
        return SafeArea(
          child: Center(
            child: _CategoryExpandCard(
              category: category,
              asset: imageAssetForCategory(category),
              items: items,
              carCategory: carCategory,
              selectedNames: selectedNames,
              onToggle: onToggle,
              onDismiss: () => Navigator.of(ctx).pop(),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, secondary, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.88, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = groupServicesByCategory(services);
    final categories = grouped.keys.toList();

    if (categories.isEmpty) {
      return Center(
        child: Text("Нет услуг в прайсе", style: GoogleFonts.manrope(color: AppColors.textDim)),
      );
    }

    // Ячейки 263×263 (~1.5× от прежних 175).
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 4),
      itemCount: categories.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 263,
        mainAxisExtent: 263,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final cat = categories[index];
        final items = grouped[cat]!;
        final selectedCount =
            items.where((s) => selectedNames.contains(s['name']?.toString())).length;
        return _CategoryTile(
          category: cat,
          asset: imageAssetForCategory(cat),
          selectedCount: selectedCount,
          onTap: () => _openCategory(context, cat, items),
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final String category;
  final String? asset;
  final int selectedCount;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.asset,
    required this.selectedCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Hero(
          tag: 'category-hero-$category',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _CategoryImage(asset: asset),
                Container(color: Colors.black.withOpacity(0.32)),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        category,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
                      ),
                      ),
                      if (selectedCount > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          "в заказе: $selectedCount",
                          style: GoogleFonts.manrope(
                            color: const Color(0xFF86EFAC),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryImage extends StatelessWidget {
  final String? asset;
  const _CategoryImage({required this.asset});

  @override
  Widget build(BuildContext context) {
    if (asset == null) return _placeholder();
    return Image.asset(
      asset!,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
      ),
    );
  }
}

/// Раскрытая карточка: картинка на весь фон, список услуг поверх.
class _CategoryExpandCard extends StatefulWidget {
  final String category;
  final String? asset;
  final List<Map<String, dynamic>> items;
  final String carCategory;
  final Set<String> selectedNames;
  final void Function(String name, double price, String category) onToggle;
  final VoidCallback onDismiss;

  const _CategoryExpandCard({
    required this.category,
    required this.asset,
    required this.items,
    required this.carCategory,
    required this.selectedNames,
    required this.onToggle,
    required this.onDismiss,
  });

  @override
  State<_CategoryExpandCard> createState() => _CategoryExpandCardState();
}

class _CategoryExpandCardState extends State<_CategoryExpandCard> {
  late Set<String> _localSelected;

  @override
  void initState() {
    super.initState();
    _localSelected = Set<String>.from(widget.selectedNames);
  }

  @override
  void didUpdateWidget(covariant _CategoryExpandCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedNames != widget.selectedNames) {
      _localSelected = Set<String>.from(widget.selectedNames);
    }
  }

  void _toggle(String name, double price) {
    widget.onToggle(name, price, widget.category);
    setState(() {
      if (_localSelected.contains(name)) {
        _localSelected.remove(name);
      } else {
        _localSelected.add(name);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final cardW = (size.width * 0.52).clamp(360.0, 560.0);
    final cardH = (size.height * 0.72).clamp(420.0, 640.0);

    final isWrap = widget.category == 'Оклейка (Пленка)';
    final popular =
        isWrap ? widget.items.where((s) => !_isWrapRiskZone(s)).toList() : widget.items;
    final risk = isWrap ? widget.items.where(_isWrapRiskZone).toList() : <Map<String, dynamic>>[];

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: widget.onDismiss,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: GestureDetector(
            onTap: () {}, // не закрывать при тапе по карточке
            child: Hero(
              tag: 'category-hero-${widget.category}',
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    width: cardW,
                    height: cardH,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _CategoryImage(asset: widget.asset),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.45),
                                Colors.black.withOpacity(0.78),
                              ],
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.category,
                                      style: GoogleFonts.manrope(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: "Закрыть",
                                    onPressed: widget.onDismiss,
                                    icon: const Icon(Icons.close, color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                                children: [
                                  if (isWrap && popular.isNotEmpty) ...[
                                    Text(
                                      "Частые",
                                      style: GoogleFonts.manrope(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                  for (final s in popular) _serviceRow(s),
                                  if (risk.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Theme(
                                      data: Theme.of(context).copyWith(
                                        dividerColor: Colors.transparent,
                                        unselectedWidgetColor: Colors.white70,
                                      ),
                                      child: ExpansionTile(
                                        initiallyExpanded: false,
                                        tilePadding: EdgeInsets.zero,
                                        iconColor: Colors.white,
                                        collapsedIconColor: Colors.white70,
                                        title: Text(
                                          "Зоны риска · ${risk.length}",
                                          style: GoogleFonts.manrope(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                        children: [
                                          for (final s in risk) _serviceRow(s),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                              child: Text(
                                "Тап вне карточки — закрыть",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.manrope(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _serviceRow(Map<String, dynamic> s) {
    final name = s['name']?.toString() ?? '';
    final price = servicePriceForCar(s, widget.carCategory);
    final selected = _localSelected.contains(name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _toggle(name, price),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withOpacity(0.22)
                  : Colors.black.withOpacity(0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? const Color(0xFF86EFAC) : Colors.white24,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.check_circle : Icons.add_circle_outline,
                  size: 20,
                  color: selected ? const Color(0xFF86EFAC) : Colors.white70,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  "${price == price.roundToDouble() ? price.toInt() : price} ₽",
                  style: GoogleFonts.manrope(
                    color: const Color(0xFF86EFAC),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
