import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_theme.dart';
import '../app_version.dart';
import '../responsive.dart';
import '../sync/sync_controller.dart';
import 'update_channel.dart';
import 'update_service.dart';

/// Диалог проверки / установки обновления (Windows zip или Android APK).
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key});

  static Future<void> open(BuildContext context) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Перед обновлением',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: AppResponsive.dialogWidth(ctx, desktop: 420),
          child: Text(
            Platform.isAndroid
                ? 'Скачается APK с ПК в вашей Wi‑Fi. Затем откроется установщик Android — '
                    'подтвердите установку (Play Защита: «Все равно установить»).\n\n'
                    'Сохранённые в базе данные останутся.'
                : 'Проверьте и сохраните незакрытые окна и заказы.\n\n'
                    'При перезапуске приложение закроется: несохранённые правки в открытых '
                    'карточках могут пропасть. Данные в базе останутся.',
            style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const UpdateDialog(),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _busy = true;
  bool _applying = false;
  bool _ready = false;
  bool _apkOpened = false;
  double _progress = 0;
  UpdateCheckResult? _result;
  PreparedUpdate? _prepared;
  PreparedApkUpdate? _preparedApk;
  final _urlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await AppVersion.ensureLoaded();
    final ch = await UpdateChannel.load();
    var url = ch?.manifestUrl ?? UpdateChannel.cloudManifestUrl;
    if (url.isEmpty) {
      final sync = SyncController.instance;
      url = UpdateChannel.suggestFromSyncBaseUrl(sync.config.normalizedBaseUrl) ??
          UpdateChannel.suggestFromSyncBaseUrl(sync.suggestedClientUrl) ??
          UpdateChannel.cloudManifestUrl;
    }
    _urlCtrl.text = url;
    await _check();
  }

  Future<void> _check() async {
    // Всегда берём URL из поля — иначе «Проверить» читает старый файл (часто :7878 → 401).
    final typed = _urlCtrl.text.trim();
    if (typed.isNotEmpty) {
      try {
        await UpdateChannel.save(typed);
        if (mounted) {
          _urlCtrl.text = UpdateChannel.normalizeManifestUrl(typed);
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сохранить канал: $e')),
        );
        return;
      }
    }

    setState(() {
      _busy = true;
      _result = null;
      _ready = false;
      _apkOpened = false;
      _prepared = null;
      _preparedApk = null;
    });
    final r = await UpdateService.instance.check();
    if (!mounted) return;
    setState(() {
      _result = r;
      _busy = false;
      if (r.channelUrl != null && r.channelUrl!.trim().isNotEmpty) {
        _urlCtrl.text = r.channelUrl!;
      }
    });
  }

  Future<void> _saveChannelAndCheck() async {
    await _check();
  }

  Future<void> _download() async {
    final m = _result?.manifest;
    if (m == null) return;
    setState(() {
      _applying = true;
      _ready = false;
      _apkOpened = false;
      _prepared = null;
      _preparedApk = null;
      _progress = 0;
    });
    try {
      if (Platform.isAndroid) {
        final apk = await UpdateService.instance.prepareAndroidUpdate(
          m,
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
        );
        await UpdateService.instance.openAndroidInstaller(apk);
        if (!mounted) return;
        setState(() {
          _applying = false;
          _ready = true;
          _apkOpened = true;
          _preparedApk = apk;
        });
      } else {
        final prepared = await UpdateService.instance.prepareUpdate(
          m,
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
        );
        if (!mounted) return;
        setState(() {
          _prepared = prepared;
          _progress = 1;
        });
        // Windows: сразу подмена файлов и автоперезапуск (без кнопки «Перезапустить»).
        await UpdateService.instance.applyPreparedAndRestart(prepared);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        _ready = false;
        _prepared = null;
        _preparedApk = null;
      });
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Ошибка обновления', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
          content: Text('$e', style: GoogleFonts.manrope(color: AppColors.textMuted)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
          ],
        ),
      );
    }
  }

  Future<void> _restart() async {
    final prepared = _prepared;
    if (prepared == null) return;
    try {
      await UpdateService.instance.applyPreparedAndRestart(prepared);
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Не удалось перезапустить', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
          content: Text('$e', style: GoogleFonts.manrope(color: AppColors.textMuted)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
          ],
        ),
      );
    }
  }

  Future<void> _reopenApk() async {
    final apk = _preparedApk;
    if (apk == null) return;
    try {
      await UpdateService.instance.openAndroidInstaller(apk);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Обновление', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: AppResponsive.dialogWidth(context, desktop: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Сейчас: ${AppVersion.label}  ·  схема БД ${AppVersion.dbSchema}'
              '${Platform.isAndroid ? ' · Android' : ''}',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (!_ready) ...[
              TextField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'URL манифеста (latest.json)',
                  hintText: 'http://192.168.3.2:8080/latest.json',
                  isDense: true,
                ),
                enabled: !_applying,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _applying || _busy ? null : _saveChannelAndCheck,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Сохранить URL и проверить'),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else if (_applying) ...[
              Text(
                'Скачивание… ${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress <= 0 ? null : _progress, color: AppColors.primary),
              const SizedBox(height: 8),
              Text(
                Platform.isAndroid
                    ? 'После загрузки откроется установщик Android.'
                    : 'После загрузки приложение перезапустится само…',
                style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
              ),
            ] else if (_ready && _apkOpened && _preparedApk != null) ...[
              _androidSuccessBlock(_preparedApk!),
            ] else if (_ready && _prepared != null) ...[
              // Запасной UI, если автоперезапуск не сработал.
              _windowsSuccessBlock(_prepared!),
            ] else ...[
              _statusBlock(r),
            ],
          ],
        ),
      ),
      actions: [
        if (!_ready)
          TextButton(
            onPressed: _applying ? null : () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        if (!_ready && !_applying)
          TextButton(
            onPressed: _busy ? null : _check,
            child: const Text('Проверить'),
          ),
        if (!_ready && r?.status == UpdateCheckStatus.available)
          ElevatedButton(
            onPressed: _applying ? null : _download,
            child: Text(Platform.isAndroid ? 'Скачать APK' : 'Скачать и установить'),
          ),
        if (_ready && _apkOpened) ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Готово'),
          ),
          ElevatedButton.icon(
            onPressed: _reopenApk,
            icon: const Icon(Icons.system_update_alt, size: 18),
            label: const Text('Открыть установщик'),
          ),
        ],
        if (_ready && _prepared != null) ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Позже'),
          ),
          ElevatedButton.icon(
            onPressed: _restart,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Перезапустить'),
          ),
        ],
      ],
    );
  }

  Widget _androidSuccessBlock(PreparedApkUpdate prepared) {
    final m = prepared.manifest;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.success.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline, color: AppColors.success, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'APK готов: ${m.version}+${m.build}',
                  style: GoogleFonts.manrope(
                    color: AppColors.success,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Подтвердите установку в окне Android.\n'
            'Если Play Защита спросит — «Все равно установить».',
            style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13, height: 1.4),
          ),
          if (m.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(m.notes, style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13, height: 1.35)),
          ],
        ],
      ),
    );
  }

  Widget _windowsSuccessBlock(PreparedUpdate prepared) {
    final m = prepared.manifest;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.success.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline, color: AppColors.success, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Обновление успешно выполнено',
                  style: GoogleFonts.manrope(
                    color: AppColors.success,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Готово к установке: ${m.version}+${m.build}\n'
            'Нажмите «Перезапустить» — приложение закроется, заменит файлы и откроется снова.',
            style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13, height: 1.4),
          ),
          if (m.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(m.notes, style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13, height: 1.35)),
          ],
        ],
      ),
    );
  }

  Widget _statusBlock(UpdateCheckResult? r) {
    if (r == null) return const SizedBox.shrink();
    Color color;
    String title;
    switch (r.status) {
      case UpdateCheckStatus.available:
        color = AppColors.success;
        title = 'Доступна ${r.manifest!.version}+${r.manifest!.build}';
        break;
      case UpdateCheckStatus.upToDate:
        color = AppColors.primary;
        title = 'Актуальная версия';
        break;
      case UpdateCheckStatus.noChannel:
        color = const Color(0xFFF59E0B);
        title = 'Канал не настроен';
        break;
      case UpdateCheckStatus.error:
        color = AppColors.danger;
        title = 'Ошибка проверки';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.manrope(color: color, fontWeight: FontWeight.w800, fontSize: 14)),
          if (r.message != null && r.message!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(r.message!, style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13, height: 1.35)),
          ],
          if (r.manifest != null && r.status == UpdateCheckStatus.available) ...[
            if (r.manifest!.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(r.manifest!.notes, style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13, height: 1.35)),
            ],
            const SizedBox(height: 6),
            Text(
              'Схема БД пакета: ${r.manifest!.dbVersion}'
              '${r.manifest!.critical ? ' · критическое' : ''}'
              '${Platform.isAndroid && r.manifest!.hasAndroidPack ? ' · APK' : ''}',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
