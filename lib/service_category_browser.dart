import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';

/// Группировка услуг по полю category.
Map<String, List<Map<String, dynamic>>> groupServicesByCategory(
  List<Map<String, dynamic>> services,
) {
  final map = <String, List<Map<String, dynamic>>>{};
  for (final s in services) {
    final cat = (s['category'] ?? 'Прочее').toString();
    map.putIfAbsent(cat, () => []).add(s);
  }
  return map;
}

double servicePriceForCar(Map<String, dynamic> s, String carCategory) {
  final fixed = (s['fixed_price'] as num?)?.toDouble() ?? 0;
  if (fixed > 0) return fixed;
  final key = "price$carCategory";
  return ((s[key] ?? 0) as num).toDouble();
}

bool _isWrapRiskZone(Map<String, dynamic> s) {
  return (s['name'] ?? '').toString().contains(' · ЗР · ');
}

/// Сначала категории, по нажатию — подуслуги (+ добавить).
class ServiceCategoryBrowser extends StatefulWidget {
  final List<Map<String, dynamic>> services;
  final String carCategory;
  final void Function(String name, double price, String category) onAdd;

  const ServiceCategoryBrowser({
    super.key,
    required this.services,
    required this.carCategory,
    required this.onAdd,
  });

  @override
  State<ServiceCategoryBrowser> createState() => _ServiceCategoryBrowserState();
}

class _ServiceCategoryBrowserState extends State<ServiceCategoryBrowser> {
  String? _selectedCategory;

  @override
  void didUpdateWidget(covariant ServiceCategoryBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.services != widget.services && _selectedCategory != null) {
      final cats = groupServicesByCategory(widget.services);
      if (!cats.containsKey(_selectedCategory)) {
        _selectedCategory = null;
      }
    }
  }

  Widget _serviceRow(Map<String, dynamic> s) {
    final price = servicePriceForCar(s, widget.carCategory);
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "${s['name']}",
              style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
          Text(
            "$price ₽",
            style: GoogleFonts.manrope(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w700),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle, color: AppColors.primary, size: 20),
            tooltip: "Добавить",
            onPressed: () => widget.onAdd(
              "${s['name']}",
              price,
              "${s['category'] ?? ''}",
            ),
          ),
        ],
      ),
    );
  }

  Widget _flatServiceList(List<Map<String, dynamic>> items) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) => _serviceRow(items[index]),
    );
  }

  /// Оклейка: частые сверху + раскрывающиеся зоны риска.
  Widget _wrapServiceList(List<Map<String, dynamic>> items) {
    final popular = items.where((s) => !_isWrapRiskZone(s)).toList();
    final risk = items.where(_isWrapRiskZone).toList();

    return ListView(
      children: [
        if (popular.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 2),
            child: Text(
              "Частые",
              style: GoogleFonts.manrope(
                color: AppColors.textDim,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (var i = 0; i < popular.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            _serviceRow(popular[i]),
          ],
        ],
        if (risk.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                iconColor: AppColors.primary,
                collapsedIconColor: AppColors.textMuted,
                title: Text(
                  "Зоны риска",
                  style: GoogleFonts.manrope(
                    color: AppColors.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  "${risk.length} позиций",
                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11),
                ),
                children: [
                  for (var i = 0; i < risk.length; i++) ...[
                    if (i > 0) const SizedBox(height: 4),
                    _serviceRow(risk[i]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = groupServicesByCategory(widget.services);
    final categories = grouped.keys.toList();

    if (_selectedCategory == null) {
      if (categories.isEmpty) {
        return Center(
          child: Text("Нет услуг в прайсе", style: GoogleFonts.manrope(color: AppColors.textDim)),
        );
      }
      return ListView.separated(
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final count = grouped[cat]!.length;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              onTap: () => setState(() => _selectedCategory = cat),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        cat,
                        style: GoogleFonts.manrope(
                          color: AppColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      "$count",
                      style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    final items = grouped[_selectedCategory] ?? [];
    final isWrap = _selectedCategory == 'Оклейка (Пленка)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _selectedCategory = null),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.arrow_back, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedCategory!,
                    style: GoogleFonts.manrope(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: isWrap ? _wrapServiceList(items) : _flatServiceList(items),
        ),
      ],
    );
  }
}
