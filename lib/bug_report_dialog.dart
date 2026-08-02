import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'database.dart';

/// Форма новой ошибки.
class BugReportDialog extends StatefulWidget {
  const BugReportDialog({super.key});

  @override
  State<BugReportDialog> createState() => _BugReportDialogState();
}

class _BugReportDialogState extends State<BugReportDialog> {
  final _placeCtrl = TextEditingController();
  final _sitCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _placeCtrl.dispose();
    _sitCtrl.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveReport() async {
    if (_detailsCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Опишите ошибку');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await DatabaseHelper().addBugReport(
      place: _placeCtrl.text.trim(),
      situation: _sitCtrl.text.trim(),
      details: _detailsCtrl.text.trim(),
    );
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        "Сообщить об ошибке",
        style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: AppColors.danger),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _placeCtrl,
              decoration: const InputDecoration(labelText: "Место (экран, кнопка)", isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _sitCtrl,
              decoration: const InputDecoration(labelText: "Ситуация (что делали)", isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _detailsCtrl,
              decoration: const InputDecoration(labelText: "Конкретика ошибки", isDense: true),
              maxLines: 4,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: GoogleFonts.manrope(color: AppColors.danger, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text("Отмена")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: _saving ? null : _saveReport,
          child: Text(_saving ? "…" : "Отправить", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

/// Список ошибок и правок внутри приложения.
class BugReportsListDialog extends StatefulWidget {
  const BugReportsListDialog({super.key});

  @override
  State<BugReportsListDialog> createState() => _BugReportsListDialogState();
}

class _BugReportsListDialogState extends State<BugReportsListDialog> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _filter = 'all'; // all | open | fixed

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper().getBugReports();
    if (!mounted) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'all') return _items;
    return _items.where((r) => r['status']?.toString() == _filter).toList();
  }

  String _fmt(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw.contains(' ') ? raw.replaceFirst(' ', 'T') : raw);
    if (dt == null) return raw;
    return DateFormat('dd.MM.yyyy HH:mm').format(dt);
  }

  Future<void> _editFix(Map<String, dynamic> row) async {
    final id = (row['id'] as num).toInt();
    final noteCtrl = TextEditingController(text: row['fix_note']?.toString() ?? '');
    var nextStatus = row['status']?.toString() ?? 'open';

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Правка #$id', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  row['details']?.toString() ?? '',
                  style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'open', label: Text('Открыта')),
                    ButtonSegment(value: 'fixed', label: Text('Исправлена')),
                  ],
                  selected: {nextStatus},
                  onSelectionChanged: (s) => setInner(() => nextStatus = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Что сделали / комментарий', isDense: true),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: Text('Удалить', style: GoogleFonts.manrope(color: AppColors.danger)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );

    if (action == 'delete') {
      await DatabaseHelper().deleteBugReport(id);
      await _load();
    } else if (action == 'save') {
      await DatabaseHelper().updateBugReport(id, status: nextStatus, fixNote: noteCtrl.text.trim());
      await _load();
    }
    noteCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final openCount = _items.where((r) => r['status'] == 'open').length;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Row(
        children: [
          Text('Ошибки и правки', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          if (openCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$openCount откр.',
                style: GoogleFonts.manrope(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Все'),
                  selected: _filter == 'all',
                  onSelected: (_) => setState(() => _filter = 'all'),
                  selectedColor: AppColors.primary.withOpacity(0.4),
                  showCheckmark: false,
                ),
                FilterChip(
                  label: const Text('Открытые'),
                  selected: _filter == 'open',
                  onSelected: (_) => setState(() => _filter = 'open'),
                  selectedColor: AppColors.danger.withOpacity(0.35),
                  showCheckmark: false,
                ),
                FilterChip(
                  label: const Text('Исправлены'),
                  selected: _filter == 'fixed',
                  onSelected: (_) => setState(() => _filter = 'fixed'),
                  selectedColor: AppColors.success.withOpacity(0.35),
                  showCheckmark: false,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : rows.isEmpty
                      ? Center(
                          child: Text('Пока пусто', style: GoogleFonts.manrope(color: AppColors.textDim)),
                        )
                      : ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                          itemBuilder: (_, i) {
                            final r = rows[i];
                            final open = r['status']?.toString() == 'open';
                            final fix = r['fix_note']?.toString() ?? '';
                            return InkWell(
                              onTap: () => _editFix(r),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: (open ? AppColors.danger : AppColors.success).withOpacity(0.18),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            open ? 'Открыта' : 'Исправлена',
                                            style: GoogleFonts.manrope(
                                              color: open ? AppColors.danger : AppColors.success,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _fmt(r['created_at']?.toString()),
                                          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                                        ),
                                        const Spacer(),
                                        Text(
                                          '#${r['id']}',
                                          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      r['details']?.toString() ?? '',
                                      style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 14),
                                    ),
                                    if ((r['place']?.toString() ?? '').isNotEmpty ||
                                        (r['situation']?.toString() ?? '').isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        [
                                          if ((r['place']?.toString() ?? '').isNotEmpty) 'Место: ${r['place']}',
                                          if ((r['situation']?.toString() ?? '').isNotEmpty) 'Ситуация: ${r['situation']}',
                                        ].join(' · '),
                                        style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12),
                                      ),
                                    ],
                                    if (fix.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Правка: $fix',
                                        style: GoogleFonts.manrope(color: AppColors.success, fontSize: 12.5, height: 1.3),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
      ],
    );
  }
}
