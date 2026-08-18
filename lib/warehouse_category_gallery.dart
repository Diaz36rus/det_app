import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'inventory_catalog.dart';

/// Сетка категорий склада (карточки с фото) + раскрытие списка позиций.
class WarehouseCategoryGallery extends StatelessWidget {
  final Map<String, int> counts;
  final Map<String, int> lowCounts;
  final Future<void> Function(String category) onOpenCategory;

  const WarehouseCategoryGallery({
    super.key,
    required this.counts,
    required this.lowCounts,
    required this.onOpenCategory,
  });

  static int columnsForWidth(double width) {
    if (width < 700) return 2;
    if (width < 1100) return 3;
    if (width < 1500) return 4;
    return 5;
  }

  @override
  Widget build(BuildContext context) {
    const cats = InventoryCategories.all;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = columnsForWidth(constraints.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: cats.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            final cat = cats[index];
            final n = counts[cat] ?? 0;
            final low = lowCounts[cat] ?? 0;
            return _WarehouseCategoryTile(
              category: cat,
              asset: InventoryCategories.imageAsset(cat),
              count: n,
              lowCount: low,
              onTap: () => onOpenCategory(cat),
            );
          },
        );
      },
    );
  }
}

class _WarehouseCategoryTile extends StatelessWidget {
  final String category;
  final String? asset;
  final int count;
  final int lowCount;
  final VoidCallback onTap;

  const _WarehouseCategoryTile({
    required this.category,
    required this.asset,
    required this.count,
    required this.lowCount,
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
          tag: 'warehouse-hero-$category',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _WarehouseCategoryImage(asset: asset),
                Container(color: Colors.black.withOpacity(0.34)),
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
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        lowCount > 0 ? '$count поз. · мало $lowCount' : '$count поз.',
                        style: GoogleFonts.manrope(
                          color: lowCount > 0 ? const Color(0xFFFCA5A5) : const Color(0xFFCBD5E1),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

class _WarehouseCategoryImage extends StatelessWidget {
  final String? asset;
  const _WarehouseCategoryImage({required this.asset});

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

/// Оверлей категории: фон-картинка + список позиций.
class WarehouseCategoryExpand extends StatelessWidget {
  final String category;
  final List<Map<String, dynamic>> items;
  final Widget Function(Map<String, dynamic> item) itemBuilder;
  final VoidCallback onAdd;
  final VoidCallback onDismiss;
  final String emptyHint;

  const WarehouseCategoryExpand({
    super.key,
    required this.category,
    required this.items,
    required this.itemBuilder,
    required this.onAdd,
    required this.onDismiss,
    this.emptyHint = 'Пока пусто — добавь позицию',
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Ноутбуки 15–17": шире по ширине окна, выше по высоте — список не тесный.
    final cardW = size.width < 1100
        ? (size.width * 0.88).clamp(320.0, 640.0)
        : (size.width * 0.55).clamp(420.0, 720.0);
    final cardH = (size.height * 0.84).clamp(420.0, 780.0);
    final asset = InventoryCategories.imageAsset(category);

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: onDismiss,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Hero(
              tag: 'warehouse-hero-$category',
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
                        _WarehouseCategoryImage(asset: asset),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.5),
                                Colors.black.withOpacity(0.86),
                              ],
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          category,
                                          style: GoogleFonts.manrope(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          '${items.length} поз.',
                                          style: GoogleFonts.manrope(
                                            color: Colors.white70,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: onAdd,
                                    icon: const Icon(Icons.add, size: 18, color: Colors.white),
                                    label: Text(
                                      'Добавить',
                                      style: GoogleFonts.manrope(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Закрыть',
                                    onPressed: onDismiss,
                                    icon: const Icon(Icons.close, color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: items.isEmpty
                                  ? Center(
                                      child: Text(
                                        emptyHint,
                                        style: GoogleFonts.manrope(color: Colors.white54, fontSize: 14),
                                      ),
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                      itemCount: items.length,
                                      itemBuilder: (context, i) => itemBuilder(items[i]),
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Text(
                                'Тап вне карточки — закрыть',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.manrope(color: Colors.white38, fontSize: 11),
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
}

Future<void> showWarehouseCategoryExpand({
  required BuildContext context,
  required String category,
  required List<Map<String, dynamic>> Function() itemsProvider,
  required Future<void> Function() onAdd,
  required Widget Function(Map<String, dynamic> item, VoidCallback refresh) itemBuilder,
  String emptyHint = 'Пока пусто — добавь позицию',
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withOpacity(0.72),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (ctx, anim, secondary) {
      return SafeArea(
        child: _WarehouseCategoryExpandHost(
          category: category,
          itemsProvider: itemsProvider,
          onAdd: onAdd,
          itemBuilder: itemBuilder,
          emptyHint: emptyHint,
          onDismiss: () => Navigator.of(ctx).pop(),
        ),
      );
    },
    transitionBuilder: (ctx, anim, secondary, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _WarehouseCategoryExpandHost extends StatefulWidget {
  final String category;
  final List<Map<String, dynamic>> Function() itemsProvider;
  final Future<void> Function() onAdd;
  final Widget Function(Map<String, dynamic> item, VoidCallback refresh) itemBuilder;
  final String emptyHint;
  final VoidCallback onDismiss;

  const _WarehouseCategoryExpandHost({
    required this.category,
    required this.itemsProvider,
    required this.onAdd,
    required this.itemBuilder,
    required this.emptyHint,
    required this.onDismiss,
  });

  @override
  State<_WarehouseCategoryExpandHost> createState() => _WarehouseCategoryExpandHostState();
}

class _WarehouseCategoryExpandHostState extends State<_WarehouseCategoryExpandHost> {
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = widget.itemsProvider();
  }

  void _refresh() {
    setState(() => _items = widget.itemsProvider());
  }

  @override
  Widget build(BuildContext context) {
    return WarehouseCategoryExpand(
      category: widget.category,
      items: _items,
      emptyHint: widget.emptyHint,
      onDismiss: widget.onDismiss,
      onAdd: () async {
        await widget.onAdd();
        if (mounted) _refresh();
      },
      itemBuilder: (item) => widget.itemBuilder(item, _refresh),
    );
  }
}
