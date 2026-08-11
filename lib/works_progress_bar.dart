import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'database.dart';

/// Прогресс выполнения работ заказа (done / total).
class WorksProgressBar extends StatelessWidget {
  final int done;
  final int total;
  final bool compact;

  const WorksProgressBar({
    super.key,
    required this.done,
    required this.total,
    this.compact = false,
  });

  /// Из полей заказа `works_done` / `works_total` (или из списка items).
  factory WorksProgressBar.fromOrder(Map<String, dynamic> order, {bool compact = false}) {
    return WorksProgressBar(
      done: (order['works_done'] as num?)?.toInt() ?? 0,
      total: (order['works_total'] as num?)?.toInt() ?? 0,
      compact: compact,
    );
  }

  factory WorksProgressBar.fromItems(List<Map<String, dynamic>> items, {bool compact = false}) {
    // Шапка пакета оклейки не считается отдельной работой.
    final countable = items.where((w) {
      if (isZonePackageHeader(w['name']?.toString()) && w['parent_id'] == null) {
        return false;
      }
      return true;
    }).toList();
    final total = countable.length;
    final done = countable.where((w) => (w['is_done'] as num?)?.toInt() == 1).length;
    return WorksProgressBar(done: done, total: total, compact: compact);
  }

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : done / total;
    final pct = (progress * 100).round();
    final complete = progress >= 1 && total > 0;
    final barH = compact ? 6.0 : 10.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                total == 0 ? "Нет работ" : (compact ? "$done/$total" : "Выполнено $done из $total"),
                style: GoogleFonts.manrope(
                  color: AppColors.textMuted,
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              "$pct%",
              style: GoogleFonts.manrope(
                color: complete ? AppColors.success : AppColors.primary,
                fontSize: compact ? 11 : 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 5 : 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: barH,
            color: AppColors.bg,
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              tween: Tween(end: progress.clamp(0.0, 1.0)),
              builder: (context, value, _) {
                return FractionallySizedBox(
                  widthFactor: value,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: LinearGradient(
                        colors: complete
                            ? const [Color(0xFF16A34A), AppColors.success]
                            : const [Color(0xFF2563EB), AppColors.primary],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
