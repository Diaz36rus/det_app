import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';
import 'branch_scope.dart';
import 'crm/cloud_mode.dart';

/// Чипы филиалов. Не рисуется, если филиал один или офлайн.
class BranchFilterBar extends StatefulWidget {
  const BranchFilterBar({super.key, this.compact = false});

  final bool compact;

  @override
  State<BranchFilterBar> createState() => _BranchFilterBarState();
}

class _BranchFilterBarState extends State<BranchFilterBar> {
  @override
  void initState() {
    super.initState();
    BranchScope.instance.ensureLoaded();
    BranchScope.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    BranchScope.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!CloudMode.enabled) return const SizedBox.shrink();
    final scope = BranchScope.instance;
    if (!scope.loaded || !scope.hasMultiple) return const SizedBox.shrink();

    final chips = <Widget>[
      _chip(
        label: 'Все',
        selected: scope.selectedId == null,
        onTap: () => scope.select(null),
      ),
      for (final b in scope.branches)
        _chip(
          label: b.name,
          selected: scope.selectedId == b.id,
          onTap: () => scope.select(b.id),
        ),
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: widget.compact ? 6 : 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              chips[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      label: Text(
        label,
        style: GoogleFonts.manrope(
          fontWeight: FontWeight.w700,
          fontSize: widget.compact ? 12.5 : 13,
          color: selected ? AppColors.text : AppColors.textMuted,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary.withOpacity(0.28),
      backgroundColor: AppColors.surface2,
      side: BorderSide(
        color: selected ? AppColors.primary.withOpacity(0.55) : AppColors.borderSoft,
      ),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
