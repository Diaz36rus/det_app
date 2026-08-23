import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_datetime.dart';
import 'app_diagnostics.dart';
import 'app_theme.dart';
import 'auth/auth_controller.dart';
import 'bug_reports_api.dart';
import 'database.dart';
import 'responsive.dart';

/// Форма новой ошибки → локально + облако.
class BugReportDialog extends StatefulWidget {
  final String? initialPlace;
  final String? initialSituation;
  final String? initialDetails;
  /// По умолчанию прикладываем диагностический лог.
  final bool attachDiagLog;

  const BugReportDialog({
    super.key,
    this.initialPlace,
    this.initialSituation,
    this.initialDetails,
    this.attachDiagLog = true,
  });

  @override
  State<BugReportDialog> createState() => _BugReportDialogState();
}

class _BugReportDialogState extends State<BugReportDialog> {
  final _placeCtrl = TextEditingController();
  final _sitCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  bool _saving = false;
  bool _attachLog = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _placeCtrl.text = widget.initialPlace ?? '';
    _sitCtrl.text = widget.initialSituation ?? '';
    _detailsCtrl.text = widget.initialDetails ?? '';
    _attachLog = widget.attachDiagLog;
  }

  @override
  void dispose() {
    _placeCtrl.dispose();
    _sitCtrl.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveReport() async {
    var details = _detailsCtrl.text.trim();
    if (details.isEmpty && !_attachLog) {
      setState(() => _error = 'Опишите ошибку');
      return;
    }
    if (_attachLog) {
      final log = AppDiagnostics.instance.formatLogForBugReport(limit: 40);
      details = details.isEmpty ? log : '$details\n\n$log';
    }
    if (details.trim().isEmpty) {
      setState(() => _error = 'Опишите ошибку');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final place = _placeCtrl.text.trim().isEmpty ? 'Без места' : _placeCtrl.text.trim();
    final situation = _sitCtrl.text.trim();
    final result = await BugReportsApi.instance.saveAndUpload(
      place: place,
      situation: situation,
      details: details,
    );
    if (!mounted) return;
    await AppDiagnostics.instance.acknowledgeLocalErrors();
    if (!mounted) return;
    Navigator.pop(context, result.sent ? 'sent' : 'local');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Сообщить об ошибке',
        style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: AppColors.danger),
      ),
      content: SizedBox(
        width: AppResponsive.dialogWidth(context, desktop: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Сообщение сохранится здесь и уйдёт на сервер — мы увидим его в облаке.',
                style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _placeCtrl,
                decoration: const InputDecoration(labelText: 'Место (экран, кнопка)', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _sitCtrl,
                decoration: const InputDecoration(labelText: 'Ситуация (что делали)', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _detailsCtrl,
                decoration: const InputDecoration(labelText: 'Конкретика ошибки', isDense: true),
                maxLines: 4,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _attachLog,
                activeColor: AppColors.primary,
                title: Text(
                  'Приложить лог ошибок / связи',
                  style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Помогает понять сбой без переписки',
                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11),
                ),
                onChanged: (v) => setState(() => _attachLog = v ?? true),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: GoogleFonts.manrope(color: AppColors.danger, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: _saving ? null : _saveReport,
          child: Text(_saving ? '…' : 'Отправить', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

/// Список ошибок: локальные + (для platform admin) облако.
class BugReportsListDialog extends StatefulWidget {
  const BugReportsListDialog({super.key});

  @override
  State<BugReportsListDialog> createState() => _BugReportsListDialogState();
}

class _BugReportsListDialogState extends State<BugReportsListDialog> {
  List<Map<String, dynamic>> _items = [];
  List<CloudBugReport> _cloud = [];
  bool _loading = true;
  bool _cloudLoading = false;
  String? _cloudError;
  String _filter = 'all'; // all | open | fixed
  String _scope = 'local'; // local | cloud

  bool get _isPlatformAdmin =>
      AuthController.instance.user?.isPlatformAdmin == true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await BugReportsApi.instance.flushPending();
    await _loadLocal();
    if (_isPlatformAdmin) {
      await _loadCloud();
    }
  }

  Future<void> _loadLocal() async {
    final rows = await DatabaseHelper().getBugReports();
    if (!mounted) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  Future<void> _loadCloud() async {
    setState(() {
      _cloudLoading = true;
      _cloudError = null;
    });
    try {
      final rows = await BugReportsApi.instance.listCloud(limit: 150);
      if (!mounted) return;
      setState(() {
        _cloud = rows;
        _cloudLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cloudLoading = false;
        _cloudError = e.toString();
      });
    }
  }

  List<Map<String, dynamic>> get _filteredLocal {
    if (_filter == 'all') return _items;
    return _items.where((r) => r['status']?.toString() == _filter).toList();
  }

  List<CloudBugReport> get _filteredCloud {
    if (_filter == 'all') return _cloud;
    return _cloud.where((r) => r.status == _filter).toList();
  }

  String _fmt(String? raw) => AppDateTime.format(raw);

  String _syncLabel(Map<String, dynamic> r) {
    final s = r['sync_status']?.toString() ?? '';
    final cloudId = r['cloud_id'];
    if (s == 'sent' || cloudId != null) return 'На сервере';
    if (s == 'failed') return 'Не ушло';
    if (s == 'pending') return 'Отправка…';
    return '';
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
            width: AppResponsive.dialogWidth(ctx, desktop: 400),
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
      await _loadLocal();
    } else if (action == 'save') {
      await DatabaseHelper().updateBugReport(id, status: nextStatus, fixNote: noteCtrl.text.trim());
      final cloudId = (row['cloud_id'] as num?)?.toInt();
      if (_isPlatformAdmin && cloudId != null && cloudId > 0) {
        try {
          await BugReportsApi.instance.patchCloud(
            id: cloudId,
            status: nextStatus,
            fixNote: noteCtrl.text.trim(),
          );
        } catch (_) {}
      }
      await _loadLocal();
    }
    noteCtrl.dispose();
  }

  Future<void> _editCloud(CloudBugReport row) async {
    final noteCtrl = TextEditingController(text: row.fixNote);
    var nextStatus = row.status;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Облако #${row.id}', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: AppResponsive.dialogWidth(ctx, desktop: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(row.details, style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(
                    [
                      if (row.userName.isNotEmpty || row.userEmail.isNotEmpty)
                        '${row.userName} ${row.userEmail}'.trim(),
                      if (row.companyName.isNotEmpty) row.companyName,
                      '${row.platform} · ${row.appVersion}+${row.appBuild}',
                    ].where((s) => s.isNotEmpty).join('\n'),
                    style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
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
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (action == 'save') {
      try {
        await BugReportsApi.instance.patchCloud(
          id: row.id,
          status: nextStatus,
          fixNote: noteCtrl.text.trim(),
        );
        await _loadCloud();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось сохранить: $e')),
          );
        }
      }
    }
    noteCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localRows = _filteredLocal;
    final cloudRows = _filteredCloud;
    final openCount = _items.where((r) => r['status'] == 'open').length;
    final cloudOpen = _cloud.where((r) => r.status == 'open').length;

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
            if (_isPlatformAdmin)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SegmentedButton<String>(
                  segments: [
                    const ButtonSegment(value: 'local', label: Text('На устройстве')),
                    ButtonSegment(
                      value: 'cloud',
                      label: Text(cloudOpen > 0 ? 'Сервер ($cloudOpen)' : 'Сервер'),
                    ),
                  ],
                  selected: {_scope},
                  onSelectionChanged: (s) {
                    setState(() => _scope = s.first);
                    if (_scope == 'cloud' && _cloud.isEmpty && !_cloudLoading) {
                      _loadCloud();
                    }
                  },
                ),
              ),
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
              child: _scope == 'cloud' && _isPlatformAdmin
                  ? _buildCloudList(cloudRows)
                  : _buildLocalList(localRows),
            ),
          ],
        ),
      ),
      actions: [
        if (_scope == 'cloud' && _isPlatformAdmin)
          TextButton(
            onPressed: _cloudLoading ? null : _loadCloud,
            child: const Text('Обновить'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
      ],
    );
  }

  Widget _buildLocalList(List<Map<String, dynamic>> rows) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (rows.isEmpty) {
      return Center(child: Text('Пока пусто', style: GoogleFonts.manrope(color: AppColors.textDim)));
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) {
        final r = rows[i];
        final open = r['status']?.toString() == 'open';
        final fix = r['fix_note']?.toString() ?? '';
        final sync = _syncLabel(r);
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
                    if (sync.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        sync,
                        style: GoogleFonts.manrope(
                          color: sync == 'На сервере' ? AppColors.success : AppColors.textDim,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
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
    );
  }

  Widget _buildCloudList(List<CloudBugReport> rows) {
    if (_cloudLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_cloudError != null) {
      return Center(
        child: Text(_cloudError!, style: GoogleFonts.manrope(color: AppColors.danger, fontSize: 13)),
      );
    }
    if (rows.isEmpty) {
      return Center(child: Text('На сервере пусто', style: GoogleFonts.manrope(color: AppColors.textDim)));
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) {
        final r = rows[i];
        final open = r.status == 'open';
        return InkWell(
          onTap: () => _editCloud(r),
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
                    Expanded(
                      child: Text(
                        [
                          if (r.companyName.isNotEmpty) r.companyName,
                          if (r.userName.isNotEmpty) r.userName,
                          '${r.platform} ${r.appVersion}+${r.appBuild}',
                        ].where((s) => s.trim().isNotEmpty).join(' · '),
                        style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text('#${r.id}', style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  r.details,
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                if (r.place.isNotEmpty || r.situation.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (r.place.isNotEmpty) 'Место: ${r.place}',
                      if (r.situation.isNotEmpty) 'Ситуация: ${r.situation}',
                    ].join(' · '),
                    style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
