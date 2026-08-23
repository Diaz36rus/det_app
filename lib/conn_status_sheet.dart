import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import 'access_model.dart';
import 'app_diagnostics.dart';
import 'app_theme.dart';
import 'app_toast.dart';
import 'auth/auth_api.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_models.dart';
import 'auth/company_api.dart';
import 'auth/platform_api.dart';
import 'bug_report_dialog.dart';
import 'crm/cloud_mode.dart';
import 'database.dart';
import 'responsive.dart';
import 'sync/lan_discover.dart';
import 'sync/qr_scan_sheet.dart';
import 'sync/sync_config.dart';
import 'sync/sync_controller.dart';
import 'sync/sync_qr.dart';
import 'owner_pin.dart';
import 'update/update_channel.dart';

bool get _canScanSyncQr => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Публичная точка облака (приглашение / health).
const _kCloudBase = AuthApi.defaultBaseUrl;

String? _inviteUrlForUser(AuthUser? user) {
  final slug = user?.companySlug?.trim().toLowerCase();
  if (slug == null || slug.length < 2) return null;
  return encodeInviteQrPayload(slug: slug, apiBase: _kCloudBase);
}


Future<void> showConnStatusSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _ConnStatusSheet(),
  );
}

class _ConnStatusSheet extends StatefulWidget {
  const _ConnStatusSheet();

  @override
  State<_ConnStatusSheet> createState() => _ConnStatusSheetState();
}

class _ConnStatusSheetState extends State<_ConnStatusSheet> with SingleTickerProviderStateMixin {
  final _urlCtrl = TextEditingController();
  bool _busy = false;
  bool _scanning = false;
  int _scanDone = 0;
  int _scanTotal = 0;
  List<DiscoveredHost> _foundHosts = const [];

  bool _apkExpanded = false;
  bool _apkLoading = false;
  String? _apkQrUrl;
  String? _apkLabel;
  String? _apkError;

  bool? _cloudOk;
  bool _cloudChecking = false;
  String _cloudDetail = '';
  final _studioKey = GlobalKey<_StudioAccessBlockState>();

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    final sync = SyncController.instance;
    _urlCtrl.text = sync.config.isClient
        ? sync.config.normalizedBaseUrl
        : (sync.suggestedClientUrl ?? '');
    _pingCloud();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pingCloud() async {
    if (_cloudChecking) return;
    setState(() {
      _cloudChecking = true;
    });
    try {
      final r = await http
          .get(Uri.parse('$_kCloudBase/health'))
          .timeout(const Duration(seconds: 6));
      final ok = r.statusCode >= 200 && r.statusCode < 500;
      if (!mounted) return;
      setState(() {
        _cloudOk = ok;
        _cloudDetail = ok ? 'api.det-app.ru' : 'Сервер ответил ${r.statusCode}';
        _cloudChecking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cloudOk = false;
        _cloudDetail = 'Нет связи с облаком';
        _cloudChecking = false;
      });
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _pingCloud(),
      AppDiagnostics.instance.refreshConnection(force: true),
    ]);
  }

  Future<void> _ensureApkQr() async {
    if (_apkLoading) return;
    if (_apkQrUrl != null && _apkError == null) return;
    setState(() {
      _apkLoading = true;
      _apkError = null;
    });
    try {
      String qrUrl = UpdateChannel.cloudApkUrl;
      String? label;
      // HEAD на /updates/android даёт 405 — достаточно GET манифеста.
      try {
        final probe = await http
            .get(Uri.parse(UpdateChannel.cloudApkUrl), headers: {'Range': 'bytes=0-0'})
            .timeout(const Duration(seconds: 6));
        // 200 / 206 OK; 405/416 тоже значит endpoint жив
        if (probe.statusCode >= 400 &&
            probe.statusCode != 405 &&
            probe.statusCode != 416) {
          qrUrl = '';
        }
      } catch (_) {
        // не блокируем — ниже fallback на android_url из манифеста
      }

      final resp = await http
          .get(Uri.parse(UpdateChannel.cloudManifestUrl))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        throw StateError('Сервер ответил ${resp.statusCode}');
      }
      final map = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final androidUrl = (map['android_url']?.toString() ?? '').trim();
      final ver = map['version']?.toString() ?? '';
      final build = map['build'];
      if (ver.isNotEmpty && build != null) {
        label = '$ver+$build';
      }
      if (qrUrl.isEmpty) {
        if (androidUrl.isEmpty) {
          throw StateError('APK на сервере ещё нет');
        }
        qrUrl = androidUrl;
      }
      if (!mounted) return;
      setState(() {
        _apkQrUrl = qrUrl;
        _apkLabel = label;
        _apkLoading = false;
        _apkError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _apkLoading = false;
        _apkError = '$e';
        _apkQrUrl = null;
      });
    }
  }

  Future<void> _scanHostQr() async {
    if (_busy || _scanning) return;
    final url = await scanSyncHostQr(context);
    if (!mounted || url == null || url.trim().isEmpty) return;
    setState(() => _urlCtrl.text = url.trim());
    await _apply(SyncRole.client);
  }

  Future<void> _importLocalClients() async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Импорт клиентов', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: Text(
          'Загрузить клиентов и авто из локального файла detailing.db в облако?\n'
          'Дубли по телефону пропускаются.',
          style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.35),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Импорт')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await DatabaseHelper().importLocalClientsToCloud();
      if (!mounted) return;
      final created = result['created'] ?? 0;
      final skipped = result['skipped'] ?? 0;
      final cars = result['cars_created'] ?? 0;
      final total = result['local_total'] ?? 0;
      showAppToast(
        context,
        'Локально: $total. Создано: $created, пропущено: $skipped, авто: $cars',
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Импорт не удался: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _findHosts() async {
    if (_scanning || _busy) return;
    setState(() {
      _scanning = true;
      _scanDone = 0;
      _scanTotal = 0;
      _foundHosts = const [];
    });
    final sync = SyncController.instance;
    try {
      final hosts = await LanDiscover.findHosts(
        token: sync.config.token,
        port: sync.config.port,
        onProgress: (done, total) {
          if (!mounted) return;
          if (done != total && done % 12 != 0) return;
          setState(() {
            _scanDone = done;
            _scanTotal = total;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _foundHosts = hosts;
        _scanning = false;
      });
      if (hosts.isEmpty) {
        showAppToast(
          context,
          'Хост не найден. ПК в режиме «Хост» и в той же Wi‑Fi?',
        );
      } else if (hosts.length == 1) {
        _urlCtrl.text = hosts.first.baseUrl;
        await _apply(SyncRole.client);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      showAppToast(context, 'Поиск не удался: $e');
    }
  }

  Future<void> _apply(SyncRole role) async {
    if (_busy) return;
    setState(() => _busy = true);
    final sync = SyncController.instance;
    String? err;
    if (role == SyncRole.client) {
      final url = _urlCtrl.text.trim();
      if (url.isEmpty) {
        err = 'Укажите ссылку хоста';
      } else {
        err = await sync.applyRole(role: role, baseUrl: url);
      }
    } else {
      err = await sync.applyRole(role: role);
    }
    await AppDiagnostics.instance.refreshConnection(force: true);
    if (mounted) {
      setState(() => _busy = false);
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      } else {
        final msg = role == SyncRole.host
            ? 'Локальный хост запущен'
            : role == SyncRole.client
                ? 'Подключено к ${_urlCtrl.text.trim()}'
                : 'Локальный режим (один ПК)';
        showAppToast(context, msg);
      }
    }
  }

  Widget _roleChip({
    required String label,
    required bool selected,
    required ValueChanged<bool>? onSelected,
    Color? accent,
  }) {
    final color = accent ?? AppColors.textMuted;
    return ChoiceChip(
      label: Text(
        label,
        style: GoogleFonts.manrope(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: selected ? AppColors.text : AppColors.textMuted,
        ),
      ),
      selected: selected,
      onSelected: onSelected,
      selectedColor: color.withOpacity(0.55),
      backgroundColor: AppColors.surface2,
      side: BorderSide(color: selected ? color : AppColors.border),
      showCheckmark: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final diag = AppDiagnostics.instance;
    final sync = SyncController.instance;
    final mq = MediaQuery.of(context);
    final h = (mq.size.height - mq.padding.vertical - mq.viewInsets.bottom) * 0.88;
    final signedIn = CloudMode.sessionActive;
    final user = AuthController.instance.user;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + mq.viewInsets.bottom),
        child: SizedBox(
          height: h.clamp(320.0, mq.size.height),
          width: AppResponsive.dialogWidth(context, desktop: 520),
          child: ListenableBuilder(
            listenable: Listenable.merge([diag, sync, AuthController.instance]),
            builder: (context, _) {
              final role = sync.config.role;
              final hostUrl = sync.suggestedClientUrl;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'Связь',
                        style: GoogleFonts.manrope(
                          color: AppColors.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Обновить',
                        onPressed: _busy ? null : _refreshAll,
                        icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (signedIn) ...[
                            _CloudHero(
                              pulse: _pulse,
                              checking: _cloudChecking,
                              ok: _cloudOk,
                              detail: _cloudDetail,
                              user: user!,
                            ),
                            const SizedBox(height: 12),
                            _StudioAccessBlock(key: _studioKey),
                            if (user.isPlatformAdmin) ...[
                              const SizedBox(height: 12),
                              const _PlatformStudiosBlock(),
                            ],
                            const SizedBox(height: 12),
                            _InviteBlock(
                              inviteUrl: _inviteUrlForUser(user),
                              studioSlug: user.companySlug,
                              studioName: user.companyName,
                              canManage: canManageAssignments(accessRankOf(user)),
                              onStaffCreated: () => _studioKey.currentState?.reloadPending(),
                            ),
                            const SizedBox(height: 8),
                          ] else ...[
                            _GuestCloudPrompt(onRefresh: _pingCloud, cloudOk: _cloudOk),
                            const SizedBox(height: 12),
                          ],
                          _SoftExpansion(
                            icon: Icons.android_rounded,
                            title: 'Приложение для телефона',
                            subtitle: 'QR на APK с сервера',
                            initiallyExpanded: false,
                            onOpen: () {
                              setState(() => _apkExpanded = true);
                              _ensureApkQr();
                            },
                            child: _buildApkBody(context),
                          ),
                          if (signedIn && CloudMode.enabled)
                            _SoftExpansion(
                              icon: Icons.upload_file_outlined,
                              title: 'Импорт локальных клиентов',
                              subtitle: 'Из detailing.db в облако',
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: OutlinedButton.icon(
                                  onPressed: _busy ? null : _importLocalClients,
                                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                                  label: Text(
                                    'Запустить импорт',
                                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ),
                          _SoftExpansion(
                            icon: Icons.wifi_tethering_rounded,
                            title: 'Офлайн · Wi‑Fi',
                            subtitle: sync.isHosting
                                ? 'Локальный хост ещё запущен'
                                : 'Аварийный режим без интернета',
                            accent: sync.isHosting ? const Color(0xFFE8A838) : null,
                            child: _buildLanBody(
                              context,
                              role: role,
                              hostUrl: hostUrl,
                              sync: sync,
                            ),
                          ),
                          _SoftExpansion(
                            icon: Icons.bug_report_outlined,
                            title: 'Диагностика',
                            subtitle: diag.recentErrors.isEmpty
                                ? 'Лог пуст'
                                : '${diag.recentErrors.length} записей',
                            child: _buildDiagBody(context, diag),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildApkBody(BuildContext context) {
    if (_apkLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_apkError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_apkError!, style: GoogleFonts.manrope(color: AppColors.danger, fontSize: 12)),
            TextButton(
              onPressed: () {
                setState(() {
                  _apkQrUrl = null;
                  _apkError = null;
                });
                _ensureApkQr();
              },
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    if (_apkQrUrl == null) {
      if (!_apkExpanded) return const SizedBox.shrink();
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        if (_apkLabel != null)
          Text(
            'Сборка $_apkLabel',
            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        const SizedBox(height: 8),
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: _apkQrUrl!,
              version: QrVersions.auto,
              size: 140,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _apkQrUrl!));
            if (!context.mounted) return;
            showAppToast(context, 'Ссылка на APK скопирована');
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Копировать ссылку'),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildLanBody(
    BuildContext context, {
    required SyncRole role,
    required String? hostUrl,
    required SyncController sync,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Только если нет интернета. Обычная работа — через облако.',
          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, height: 1.35),
        ),
        if (sync.isHosting) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _apply(SyncRole.local),
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: const Text('Остановить локальный хост'),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          'Режим',
          style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _roleChip(
              label: 'Один ПК',
              selected: role == SyncRole.local,
              onSelected: _busy ? null : (_) => _apply(SyncRole.local),
            ),
            _roleChip(
              label: sync.isHosting ? 'Хост ●' : 'Хост',
              selected: role == SyncRole.host,
              onSelected: _busy ? null : (_) => _apply(SyncRole.host),
              accent: AppColors.primary,
            ),
            _roleChip(
              label: 'Клиент',
              selected: role == SyncRole.client,
              onSelected: _busy ? null : (_) => _apply(SyncRole.client),
              accent: const Color(0xFF22D3EE),
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        const SizedBox(height: 12),
        if (role == SyncRole.host) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.bg.withOpacity(0.55),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              hostUrl ?? 'IP не найден',
              style: GoogleFonts.manrope(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: hostUrl == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: hostUrl));
                    if (!context.mounted) return;
                    showAppToast(context, 'Ссылка скопирована');
                  },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Копировать ссылку'),
          ),
          if (hostUrl != null) ...[
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: QrImageView(
                  data: encodeSyncQrPayload(hostUrl),
                  version: QrVersions.auto,
                  size: 150,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'QR для телефона в той же Wi‑Fi',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ] else ...[
          if (_canScanSyncQr) ...[
            ElevatedButton.icon(
              onPressed: (_busy || _scanning) ? null : _scanHostQr,
              icon: const Icon(Icons.qr_code_scanner, size: 20),
              label: const Text('Сканировать QR хоста'),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: (_busy || _scanning) ? null : _findHosts,
            icon: _scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find, size: 18),
            label: Text(
              _scanning
                  ? (_scanTotal > 0 ? 'Поиск… $_scanDone/$_scanTotal' : 'Поиск…')
                  : 'Найти хост в Wi‑Fi',
            ),
          ),
          if (_foundHosts.length > 1) ...[
            const SizedBox(height: 8),
            ..._foundHosts.map(
              (h) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: AppColors.bg.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _busy
                        ? null
                        : () async {
                            _urlCtrl.text = h.baseUrl;
                            await _apply(SyncRole.client);
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Text(
                        h.baseUrl,
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _urlCtrl,
            enabled: !_busy && !_scanning,
            decoration: const InputDecoration(
              hintText: 'http://192.168.0.10:7878',
              isDense: true,
              labelText: 'Ссылка с хоста',
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: (_busy || _scanning) ? null : () => _apply(SyncRole.client),
            child: const Text('Подключить как клиент'),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildDiagBody(BuildContext context, AppDiagnostics diag) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 110,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: diag.recentErrors.isEmpty
              ? Center(
                  child: Text('Лог пуст', style: GoogleFonts.manrope(color: AppColors.textDim)),
                )
              : ListView.builder(
                  itemCount: diag.recentErrors.length,
                  itemBuilder: (_, i) {
                    final e = diag.recentErrors[diag.recentErrors.length - 1 - i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        e.format(),
                        style: GoogleFonts.manrope(
                          color: e.level == 'error' || e.level == 'fatal'
                              ? AppColors.danger
                              : AppColors.textMuted,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: diag.formatLogForBugReport()));
                  if (!context.mounted) return;
                  showAppToast(context, 'Лог скопирован');
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Лог'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => BugReportDialog(
                      initialDetails: diag.formatLogForBugReport(limit: 30),
                      initialPlace: 'Индикатор связи',
                      initialSituation: _cloudDetail.isNotEmpty ? _cloudDetail : diag.statusDetail,
                    ),
                  );
                  if (ok == true) {
                    await diag.acknowledgeLocalErrors();
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.bug_report, size: 18),
                label: const Text('Баг'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

// --- Visual blocks -----------------------------------------------------------

class _CloudHero extends StatelessWidget {
  const _CloudHero({
    required this.pulse,
    required this.checking,
    required this.ok,
    required this.detail,
    required this.user,
  });

  final AnimationController pulse;
  final bool checking;
  final bool? ok;
  final String detail;
  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final online = ok == true;
    final accent = checking
        ? AppColors.textMuted
        : online
            ? AppColors.success
            : (ok == false ? AppColors.danger : AppColors.primary);
    final title = checking
        ? 'Проверка облака…'
        : online
            ? 'Облако онлайн'
            : (ok == false ? 'Облако недоступно' : 'Облако');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primarySoft.withOpacity(0.55),
            AppColors.surface2,
            AppColors.bg.withOpacity(0.9),
          ],
        ),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: pulse,
                builder: (_, __) {
                  final t = online ? (0.55 + pulse.value * 0.45) : 1.0;
                  return Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withOpacity(t),
                      boxShadow: online
                          ? [
                              BoxShadow(
                                color: accent.withOpacity(0.35 * pulse.value),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.manrope(
                    color: AppColors.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Icon(Icons.cloud_outlined, color: accent.withOpacity(0.9), size: 22),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            detail.isNotEmpty ? detail : 'api.det-app.ru',
            style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            user.displayLabel,
            style: GoogleFonts.manrope(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            user.email.isNotEmpty ? user.email : (user.phone ?? ''),
            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _GuestCloudPrompt extends StatelessWidget {
  const _GuestCloudPrompt({required this.onRefresh, required this.cloudOk});

  final VoidCallback onRefresh;
  final bool? cloudOk;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surface2,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Войдите в аккаунт',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Общая база студии — через облако api.det-app.ru. '
            'Wi‑Fi-хост нужен только без интернета.',
            style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13, height: 1.35),
          ),
          if (cloudOk != null) ...[
            const SizedBox(height: 10),
            Text(
              cloudOk == true ? 'Сервер доступен' : 'Сервер недоступен',
              style: GoogleFonts.manrope(
                color: cloudOk == true ? AppColors.success : AppColors.danger,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onRefresh, child: const Text('Проверить')),
          ),
        ],
      ),
    );
  }
}

/// Владелец приложения: список студий + регистрация + филиалы.
class _PlatformStudiosBlock extends StatefulWidget {
  const _PlatformStudiosBlock();

  @override
  State<_PlatformStudiosBlock> createState() => _PlatformStudiosBlockState();
}

class _PlatformStudiosBlockState extends State<_PlatformStudiosBlock> {
  final _api = PlatformApi();
  List<PlatformCompany> _companies = const [];
  Map<int, List<CompanyBranch>> _branches = const {};
  Map<int, List<PlatformUser>> _users = const {};
  bool _loading = false;
  String? _error;
  int? _expandedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _api.listCompanies(accessToken: token);
      if (!mounted) return;
      setState(() {
        _companies = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _toggleBranches(PlatformCompany c) async {
    if (_expandedId == c.id) {
      setState(() => _expandedId = null);
      return;
    }
    setState(() => _expandedId = c.id);
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    try {
      if (!_branches.containsKey(c.id)) {
        final list = await _api.listCompanyBranches(accessToken: token, companyId: c.id);
        if (!mounted) return;
        setState(() => _branches = {..._branches, c.id: list});
      }
      if (!_users.containsKey(c.id)) {
        await _loadUsers(c);
      }
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '$e');
    }
  }

  Future<void> _createStudio() async {
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    final created = await showDialog<CompanyCreated>(
      context: context,
      builder: (ctx) => _CreateStudioDialog(accessToken: token),
    );
    if (created == null || !mounted) return;
    final msg = created.ownerEmail != null
        ? 'Студия «${created.company.name}» · владелец ${created.ownerEmail}'
        : 'Студия «${created.company.name}» создана';
    showAppToast(context, msg);
    await _load();
  }

  Future<void> _addBranch(PlatformCompany c) async {
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const _CreateBranchDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final b = await _api.createPlatformBranch(
        accessToken: token,
        companyId: c.id,
        name: name.trim(),
      );
      if (!mounted) return;
      showAppToast(context, 'Филиал: ${b.name}');
      setState(() {
        final cur = [...(_branches[c.id] ?? const <CompanyBranch>[])];
        cur.add(b);
        _branches = {..._branches, c.id: cur};
        _expandedId = c.id;
      });
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '$e');
    }
  }

  Future<void> _toggleCompanyActive(PlatformCompany c) async {
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    final next = !c.isActive;
    final title = next ? 'Включить студию «${c.name}»' : 'Выключить студию «${c.name}»';
    if (!next) {
      final pinOk = await confirmOwnerDestructivePin(context, actionTitle: title);
      if (!pinOk || !mounted) return;
    }
    try {
      final updated = await _api.setCompanyActive(
        accessToken: token,
        companyId: c.id,
        isActive: next,
      );
      if (!mounted) return;
      showAppToast(context, next ? 'Студия включена' : 'Студия выключена');
      setState(() {
        _companies = [
          for (final x in _companies) if (x.id == updated.id) updated else x,
        ];
      });
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '$e');
    }
  }

  Future<void> _wipeCompany(PlatformCompany c, {required bool hard}) async {
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    final title = hard
        ? 'Удалить студию «${c.name}» навсегда'
        : 'Очистить данные студии «${c.name}»';
    final pinOk = await confirmOwnerDestructivePin(context, actionTitle: title);
    if (!pinOk || !mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title, style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: Text(
          hard
              ? 'Будут удалены пользователи, заказы, касса и сама студия. Это необратимо.'
              : 'Заказы, клиенты, касса и пользователи студии будут стёрты. Студия останется выключенной (slug сохранится).',
          style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.35),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(hard ? 'Удалить' : 'Очистить'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final res = await _api.wipeOrDeleteCompany(
        accessToken: token,
        companyId: c.id,
        hard: hard,
        wipeData: !hard,
      );
      if (!mounted) return;
      final deleted = res['deleted'] == true;
      showAppToast(context, deleted ? 'Студия удалена' : 'Данные студии очищены');
      await _load();
      setState(() {
        _branches = {..._branches}..remove(c.id);
        _users = {..._users}..remove(c.id);
        if (deleted && _expandedId == c.id) _expandedId = null;
      });
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '$e');
    }
  }

  Future<void> _loadUsers(PlatformCompany c) async {
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    try {
      final list = await _api.listCompanyUsers(accessToken: token, companyId: c.id);
      if (!mounted) return;
      setState(() => _users = {..._users, c.id: list});
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '$e');
    }
  }

  Future<void> _toggleUser(PlatformCompany c, PlatformUser u) async {
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    try {
      final updated = await _api.setUserActive(
        accessToken: token,
        userId: u.id,
        isActive: !u.isActive,
      );
      if (!mounted) return;
      setState(() {
        final cur = [...(_users[c.id] ?? const <PlatformUser>[])];
        final i = cur.indexWhere((x) => x.id == u.id);
        if (i >= 0) cur[i] = updated;
        _users = {..._users, c.id: cur};
      });
      showAppToast(context, updated.isActive ? 'Пользователь включён' : 'Пользователь отключён');
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '$e');
    }
  }

  Future<void> _deleteUser(PlatformCompany c, PlatformUser u) async {
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    final pinOk = await confirmOwnerDestructivePin(
      context,
      actionTitle: 'Удалить логин ${u.displayLabel}',
    );
    if (!pinOk || !mounted) return;
    try {
      await _api.deleteUser(accessToken: token, userId: u.id);
      if (!mounted) return;
      setState(() {
        _users = {
          ..._users,
          c.id: [...(_users[c.id] ?? const <PlatformUser>[])].where((x) => x.id != u.id).toList(),
        };
      });
      showAppToast(context, 'Логин удалён');
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '$e');
    }
  }

  Future<void> _toggleBranch(PlatformCompany c, CompanyBranch b) async {
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    try {
      final updated = await _api.setBranchActive(
        accessToken: token,
        branchId: b.id,
        isActive: !b.isActive,
      );
      if (!mounted) return;
      setState(() {
        final cur = [...(_branches[c.id] ?? const <CompanyBranch>[])];
        final i = cur.indexWhere((x) => x.id == b.id);
        if (i >= 0) cur[i] = updated;
        _branches = {..._branches, c.id: cur};
      });
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.surface2,
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Студии',
                  style: GoogleFonts.manrope(
                    color: AppColors.textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (_loading)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              else
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Обновить',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 18, color: AppColors.textDim),
                ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _createStudio,
            icon: const Icon(Icons.add_business_outlined, size: 18),
            label: Text('Зарегистрировать студию', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Text(_error!, style: GoogleFonts.manrope(color: Colors.redAccent, fontSize: 12))
          else if (_companies.isEmpty)
            Text(
              'Пока нет студий. Создайте первую — с основным филиалом и владельцем.',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, height: 1.35),
            )
          else
            ..._companies.map((c) {
              final open = _expandedId == c.id;
              final branches = _branches[c.id];
              final users = _users[c.id];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: AppColors.bg.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                  child: Column(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _toggleBranches(c),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.apartment_outlined,
                                size: 18,
                                color: c.isActive ? AppColors.primary : AppColors.textDim,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.name,
                                      style: GoogleFonts.manrope(
                                        color: AppColors.text,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      c.isActive ? c.slug : '${c.slug} · выкл',
                                      style: GoogleFonts.manrope(
                                        color: c.isActive ? AppColors.textDim : AppColors.danger,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Ссылка-приглашение',
                                onPressed: () async {
                                  final link = encodeInviteQrPayload(
                                    slug: c.slug,
                                    apiBase: _kCloudBase,
                                  );
                                  await Clipboard.setData(ClipboardData(text: link));
                                  if (!context.mounted) return;
                                  showAppToast(context, 'Приглашение: ${c.slug}');
                                },
                                icon: const Icon(Icons.qr_code_2_rounded, size: 18, color: AppColors.primary),
                              ),
                              Icon(
                                open ? Icons.expand_less : Icons.expand_more,
                                color: AppColors.textDim,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (open) ...[
                        const Divider(height: 1, color: AppColors.borderSoft),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => _toggleCompanyActive(c),
                                    child: Text(c.isActive ? 'Выключить' : 'Включить'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => _wipeCompany(c, hard: false),
                                    child: const Text('Очистить данные'),
                                  ),
                                  if (c.slug != 'demo')
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.danger.withOpacity(0.9),
                                      ),
                                      onPressed: () => _wipeCompany(c, hard: true),
                                      child: const Text('Удалить студию'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Филиалы',
                                style: GoogleFonts.manrope(
                                  color: AppColors.textDim,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (branches == null)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Center(
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                )
                              else if (branches.isEmpty)
                                Text('Нет филиалов', style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12))
                              else
                                ...branches.map(
                                  (b) => Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '· ${b.name}${b.isActive ? '' : ' (выкл)'}',
                                            style: GoogleFonts.manrope(
                                              color: b.isActive ? AppColors.text : AppColors.textDim,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => _toggleBranch(c, b),
                                          child: Text(
                                            b.isActive ? 'выкл' : 'вкл',
                                            style: GoogleFonts.manrope(fontSize: 11),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              TextButton.icon(
                                onPressed: () => _addBranch(c),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Добавить филиал'),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    'Пользователи',
                                    style: GoogleFonts.manrope(
                                      color: AppColors.textDim,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Обновить список',
                                    onPressed: () => _loadUsers(c),
                                    icon: const Icon(Icons.refresh, size: 16, color: AppColors.textDim),
                                  ),
                                ],
                              ),
                              if (users == null)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Center(
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                )
                              else if (users.isEmpty)
                                Text('Нет пользователей', style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12))
                              else
                                ...users.map(
                                  (u) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                u.displayLabel,
                                                style: GoogleFonts.manrope(
                                                  color: u.isActive ? AppColors.text : AppColors.textDim,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              Text(
                                                [
                                                  u.email,
                                                  if (u.roles.isNotEmpty) u.roles.join(', '),
                                                  if (u.pendingAssignment) 'ожидает',
                                                  if (!u.isActive) 'выкл',
                                                ].join(' · '),
                                                style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 10),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          tooltip: u.isActive ? 'Отключить' : 'Включить',
                                          onPressed: () => _toggleUser(c, u),
                                          icon: Icon(
                                            u.isActive ? Icons.person_off_outlined : Icons.person_outline,
                                            size: 18,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          tooltip: 'Удалить логин',
                                          onPressed: () => _deleteUser(c, u),
                                          icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _CreateStudioDialog extends StatefulWidget {
  const _CreateStudioDialog({required this.accessToken});

  final String accessToken;

  @override
  State<_CreateStudioDialog> createState() => _CreateStudioDialogState();
}

class _CreateStudioDialogState extends State<_CreateStudioDialog> {
  final _api = PlatformApi();
  final _nameCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  final _branchCtrl = TextEditingController(text: 'Основной филиал');
  final _ownerNameCtrl = TextEditingController();
  final _ownerEmailCtrl = TextEditingController();
  final _ownerPhoneCtrl = TextEditingController();
  final _ownerPassCtrl = TextEditingController();
  bool _withOwner = true;
  bool _busy = false;
  bool _obscure = true;
  bool _slugTouched = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _slugCtrl.dispose();
    _branchCtrl.dispose();
    _ownerNameCtrl.dispose();
    _ownerEmailCtrl.dispose();
    _ownerPhoneCtrl.dispose();
    _ownerPassCtrl.dispose();
    super.dispose();
  }

  String _slugify(String raw) {
    const map = {
      'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e', 'ж': 'zh',
      'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o',
      'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f', 'х': 'h', 'ц': 'c',
      'ч': 'ch', 'ш': 'sh', 'щ': 'sch', 'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu',
      'я': 'ya',
    };
    final buf = StringBuffer();
    for (final ch in raw.toLowerCase().runes) {
      final s = String.fromCharCode(ch);
      if (map.containsKey(s)) {
        buf.write(map[s]);
      } else if (RegExp(r'[a-z0-9]').hasMatch(s)) {
        buf.write(s);
      } else if (s == ' ' || s == '-' || s == '_') {
        buf.write('-');
      }
    }
    return buf.toString().replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final slug = _slugCtrl.text.trim().toLowerCase();
    final branch = _branchCtrl.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Укажите название студии');
      return;
    }
    if (slug.length < 2) {
      setState(() => _error = 'Укажите slug (латиница)');
      return;
    }
    if (branch.length < 2) {
      setState(() => _error = 'Укажите название филиала');
      return;
    }
    String? ownerEmail;
    String? ownerPass;
    String? ownerName;
    String? ownerPhone;
    if (_withOwner) {
      ownerEmail = _ownerEmailCtrl.text.trim();
      ownerPass = _ownerPassCtrl.text;
      ownerName = _ownerNameCtrl.text.trim();
      ownerPhone = _ownerPhoneCtrl.text.trim();
      if (ownerEmail!.isEmpty || !ownerEmail.contains('@')) {
        setState(() => _error = 'Email владельца студии');
        return;
      }
      if (ownerPass!.length < 6) {
        setState(() => _error = 'Пароль владельца не короче 6 символов');
        return;
      }
      if (ownerName!.isEmpty) ownerName = name;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await _api.createCompany(
        accessToken: widget.accessToken,
        name: name,
        slug: slug,
        branchName: branch,
        ownerEmail: ownerEmail,
        ownerPassword: ownerPass,
        ownerFullName: ownerName,
        ownerPhone: (ownerPhone == null || ownerPhone.isEmpty) ? null : ownerPhone,
      );
      if (!mounted) return;
      Navigator.pop(context, created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Новая студия', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Название студии', isDense: true),
                onChanged: (v) {
                  if (_slugTouched) return;
                  setState(() => _slugCtrl.text = _slugify(v));
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _slugCtrl,
                decoration: const InputDecoration(
                  labelText: 'Slug (латиница)',
                  helperText: 'Для URL / invite, например demo, kdfx-spb',
                  isDense: true,
                ),
                onChanged: (_) => _slugTouched = true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _branchCtrl,
                decoration: const InputDecoration(labelText: 'Первый филиал', isDense: true),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Создать владельца студии', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13)),
                subtitle: Text('Логин в CRM этой студии', style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11)),
                value: _withOwner,
                onChanged: (v) => setState(() => _withOwner = v),
              ),
              if (_withOwner) ...[
                TextField(
                  controller: _ownerNameCtrl,
                  decoration: const InputDecoration(labelText: 'ФИО владельца', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _ownerEmailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email владельца', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _ownerPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Телефон (необязательно)', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _ownerPassCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Пароль владельца',
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: GoogleFonts.manrope(color: Colors.redAccent, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Создать'),
        ),
      ],
    );
  }
}

class _CreateBranchDialog extends StatefulWidget {
  const _CreateBranchDialog();

  @override
  State<_CreateBranchDialog> createState() => _CreateBranchDialogState();
}

class _CreateBranchDialogState extends State<_CreateBranchDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Новый филиал', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Название филиала', isDense: true),
        onSubmitted: (v) {
          if (v.trim().length >= 2) Navigator.pop(context, v.trim());
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            final t = _ctrl.text.trim();
            if (t.length < 2) return;
            Navigator.pop(context, t);
          },
          child: const Text('Создать'),
        ),
      ],
    );
  }
}

class _InviteBlock extends StatelessWidget {
  const _InviteBlock({
    required this.inviteUrl,
    required this.canManage,
    this.studioSlug,
    this.studioName,
    this.onStaffCreated,
  });

  final String? inviteUrl;
  final String? studioSlug;
  final String? studioName;
  final bool canManage;
  final VoidCallback? onStaffCreated;

  Future<void> _openCreate(BuildContext context) async {
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    final created = await showDialog<AuthUser>(
      context: context,
      builder: (ctx) => _CreateStaffDialog(accessToken: token),
    );
    if (created != null && context.mounted) {
      showAppToast(context, 'Создан: ${created.displayLabel}');
      onStaffCreated?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = inviteUrl;
    final slug = studioSlug?.trim().toLowerCase();
    final name = (studioName?.trim().isNotEmpty == true)
        ? studioName!.trim()
        : (slug != null && slug.isNotEmpty ? slug : null);
    final hasInvite = url != null && url.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.surface2,
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            canManage ? 'Сотрудники' : 'Подключение',
            style: GoogleFonts.manrope(
              color: AppColors.textDim,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          if (name != null) ...[
            const SizedBox(height: 6),
            Text(
              name,
              style: GoogleFonts.manrope(
                color: AppColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (canManage) ...[
            const SizedBox(height: 12),
            Text(
              'Два способа добавить человека',
              style: GoogleFonts.manrope(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            _InviteStepCard(
              step: '1',
              title: 'Вы создаёте логин сами',
              body:
                  'Сразу задаёте должность (владелец / управляющий / админ / мастер), филиал и пароль. Человек входит по этим данным — без заявки.',
              child: FilledButton.icon(
                onPressed: () => _openCreate(context),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: Text(
                  'Добавить сотрудника',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _InviteStepCard(
              step: '2',
              title: 'Человек входит сам по QR / ссылке',
              body:
                  'На телефоне: установить Det App → «Меня пригласили» → код студии или QR. '
                  'Появится заявка в блоке «Назначения» выше — вы нажмёте «Назначить» и выдадите должность.',
              child: hasInvite
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: QrImageView(
                              data: url,
                              version: QrVersions.auto,
                              size: 132,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                        if (slug != null && slug.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Код студии: $slug',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.manrope(
                              color: AppColors.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: url));
                            if (!context.mounted) return;
                            showAppToast(context, 'Ссылка приглашения скопирована');
                          },
                          icon: const Icon(Icons.link_rounded, size: 18),
                          label: const Text('Скопировать ссылку'),
                        ),
                      ],
                    )
                  : Text(
                      'QR появится после входа как пользователь студии (не как владелец приложения без студии).',
                      style: GoogleFonts.manrope(
                        color: AppColors.textDim,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
            ),
          ] else if (hasInvite) ...[
            const SizedBox(height: 10),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: url,
                  version: QrVersions.auto,
                  size: 148,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (slug != null && slug.isNotEmpty)
              Text(
                'Код: $slug',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (!context.mounted) return;
                showAppToast(context, 'Ссылка приглашения скопирована');
              },
              icon: const Icon(Icons.link_rounded, size: 18),
              label: const Text('Скопировать ссылку'),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              'Нет кода студии для QR — попросите администратора прислать ссылку.',
              style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _InviteStepCard extends StatelessWidget {
  const _InviteStepCard({
    required this.step,
    required this.title,
    required this.body,
    required this.child,
  });

  final String step;
  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.bg.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  step,
                  style: GoogleFonts.manrope(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.manrope(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: GoogleFonts.manrope(
                        color: AppColors.textDim,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SoftExpansion extends StatefulWidget {
  const _SoftExpansion({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.onOpen,
    this.initiallyExpanded = false,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback? onOpen;
  final bool initiallyExpanded;
  final Color? accent;

  @override
  State<_SoftExpansion> createState() => _SoftExpansionState();
}

class _SoftExpansionState extends State<_SoftExpansion> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? AppColors.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _open ? AppColors.border : AppColors.borderSoft),
          color: _open ? AppColors.surface2.withOpacity(0.65) : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                setState(() => _open = !_open);
                if (_open) widget.onOpen?.call();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(widget.icon, size: 20, color: _open ? AppColors.primary : accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: GoogleFonts.manrope(
                              color: AppColors.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            widget.subtitle,
                            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.expand_more, color: AppColors.textDim),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: widget.child,
              ),
              crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }
}

/// Филиал + должность + алерты назначения (по уровню доступа).
class _StudioAccessBlock extends StatefulWidget {
  const _StudioAccessBlock({super.key});

  @override
  State<_StudioAccessBlock> createState() => _StudioAccessBlockState();
}

class _StudioAccessBlockState extends State<_StudioAccessBlock> {
  final _api = CompanyApi();
  final _authApi = AuthApi();
  List<AuthUser> _pending = const [];
  List<CompanyBranch> _branches = const [];
  String? _studioName;
  bool _loading = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    final rank = accessRankOf(AuthController.instance.user);
    _resolveStudioName();
    _loadBranches();
    if (canManageAssignments(rank)) {
      _loadPending(quiet: false);
      _poll = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted) return;
        _loadPending(quiet: true);
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void reloadPending() => _loadPending(quiet: false);

  Future<void> _resolveStudioName() async {
    final user = AuthController.instance.user;
    final fromUser = user?.companyName?.trim();
    if (fromUser != null && fromUser.isNotEmpty) {
      if (mounted) setState(() => _studioName = fromUser);
      return;
    }
    final slug = user?.companySlug?.trim();
    if (slug == null || slug.isEmpty) return;
    try {
      final look = await _authApi.studioLookup(slug);
      if (!mounted) return;
      setState(() => _studioName = look.name);
    } catch (_) {
      if (!mounted) return;
      setState(() => _studioName = slug);
    }
  }

  Future<void> _loadBranches() async {
    final token = AuthController.instance.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      final rows = await _api.listBranches(accessToken: token);
      if (!mounted) return;
      setState(() => _branches = rows);
    } catch (_) {}
  }

  Future<void> _loadPending({required bool quiet}) async {
    final token = AuthController.instance.accessToken;
    if (token == null || token.isEmpty) return;
    if (!quiet && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _api.listUsers(accessToken: token, pending: true);
      if (!mounted) return;
      setState(() {
        _pending = rows;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (quiet) {
        setState(() => _loading = false);
      } else {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _openAssign(AuthUser u) async {
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _AssignUserDialog(user: u, accessToken: token),
    );
    if (ok == true) {
      showAppToast(context, 'Назначено: ${u.displayLabel}');
      await _loadPending(quiet: false);
    }
  }

  Future<void> _openCreate() async {
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    final created = await showDialog<AuthUser>(
      context: context,
      builder: (ctx) => _CreateStaffDialog(accessToken: token),
    );
    if (created != null && mounted) {
      showAppToast(context, 'Создан: ${created.displayLabel}');
      await _loadPending(quiet: false);
    }
  }

  Future<void> _openCreateBranch() async {
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const _CreateBranchDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final user = AuthController.instance.user;
      if (user?.isPlatformAdmin == true && user?.companyId == null) {
        showAppToast(context, 'Выберите студию в блоке «Студии» и добавьте филиал там');
        return;
      }
      final b = await _api.createBranch(accessToken: token, name: name.trim());
      if (!mounted) return;
      showAppToast(context, 'Филиал создан: ${b.name}');
      await _loadBranches();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthController.instance.user;
    final rank = accessRankOf(user);
    final branchLabel = _branchLabel(user, _branches);
    final jobLabel = _jobLabel(user, rank);
    final studioTitle = () {
      final n = _studioName?.trim();
      if (n != null && n.isNotEmpty) return n;
      final fromUser = user?.companyName?.trim();
      if (fromUser != null && fromUser.isNotEmpty) return fromUser;
      final slug = user?.companySlug?.trim();
      if (slug != null && slug.isNotEmpty) return slug;
      return null;
    }();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Студия',
                  style: GoogleFonts.manrope(
                    color: AppColors.textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (canManageAssignments(rank))
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Добавить сотрудника',
                  onPressed: _openCreate,
                  icon: const Icon(Icons.person_add_alt_1, size: 18, color: AppColors.primary),
                ),
              if (rank == AccessRank.studioFull || rank == AccessRank.platformOwner)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Новый филиал',
                  onPressed: _openCreateBranch,
                  icon: const Icon(Icons.storefront_outlined, size: 18, color: AppColors.primary),
                ),
            ],
          ),
          if (studioTitle != null) ...[
            const SizedBox(height: 6),
            Text(
              studioTitle,
              style: GoogleFonts.manrope(
                color: AppColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (user?.companySlug != null &&
                user!.companySlug!.trim().isNotEmpty &&
                user.companySlug!.trim().toLowerCase() != studioTitle.toLowerCase()) ...[
              const SizedBox(height: 2),
              Text(
                'Код: ${user.companySlug}',
                style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
              ),
            ],
          ],
          const SizedBox(height: 8),
          _kv('Филиал', branchLabel),
          const SizedBox(height: 4),
          _kv('Должность', jobLabel),
          if (user?.pendingAssignment == true) ...[
            const SizedBox(height: 8),
            Text(
              'Ожидаете назначение должности администратором.',
              style: GoogleFonts.manrope(color: const Color(0xFFE8A838), fontSize: 12, height: 1.35),
            ),
          ],
          if (canManageAssignments(rank)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Назначения',
                    style: GoogleFonts.manrope(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_loading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Обновить сейчас',
                    onPressed: () => _loadPending(quiet: false),
                    icon: const Icon(Icons.refresh, size: 18, color: AppColors.textDim),
                  ),
              ],
            ),
            Text(
              'Заявки по QR обновляются сами каждые 5 сек.',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11, height: 1.3),
            ),
            const SizedBox(height: 6),
            if (_error != null)
              Text(_error!, style: GoogleFonts.manrope(color: Colors.redAccent, fontSize: 11))
            else if (_pending.isEmpty)
              Text(
                'Пока пусто. Когда сотрудник войдёт через «Меня пригласили», заявка появится здесь.',
                style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, height: 1.35),
              )
            else
              ..._pending.map((p) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: AppColors.bg.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _openAssign(p),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        child: Row(
                          children: [
                            const Icon(Icons.person_outline, size: 18, color: Color(0xFFE8A838)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.displayLabel,
                                    style: GoogleFonts.manrope(
                                      color: AppColors.text,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    p.email,
                                    style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'Назначить',
                              style: GoogleFonts.manrope(
                                color: AppColors.primary,
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
              }),
          ] else if (rank == AccessRank.master) ...[
            const SizedBox(height: 8),
            Text(
              'Доступ мастера: связь и QR. Назначение ролей — у администратора.',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  static String _branchLabel(AuthUser? user, List<CompanyBranch> branches) {
    if (user == null) return 'Не вошли';
    final ids = user.branchIds;
    if (ids.isEmpty) {
      if (user.isPlatformAdmin) return 'Все филиалы (владелец приложения)';
      return 'Основной филиал';
    }
    String nameOf(int id) {
      for (final b in branches) {
        if (b.id == id) return b.name;
      }
      return 'Филиал #$id';
    }

    if (ids.length == 1) return nameOf(ids.first);
    return ids.map(nameOf).join(', ');
  }

  static String _jobLabel(AuthUser? user, AccessRank rank) {
    if (user == null) return '—';
    if (rank == AccessRank.platformOwner) return 'Владелец приложения';
    if (user.pendingAssignment == true) return 'Ожидает назначение';
    if (user.roles.isEmpty) return 'Без должности';
    return user.roles.join(', ');
  }

  static Widget _kv(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            k,
            style: GoogleFonts.manrope(
              color: AppColors.textDim,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: GoogleFonts.manrope(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _CreateStaffDialog extends StatefulWidget {
  const _CreateStaffDialog({required this.accessToken});

  final String accessToken;

  @override
  State<_CreateStaffDialog> createState() => _CreateStaffDialogState();
}

class _CreateStaffDialogState extends State<_CreateStaffDialog> {
  final _api = CompanyApi();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  List<CompanyRole> _roles = const [];
  List<CompanyBranch> _branches = const [];
  List<String> _workshops = const [];
  final Set<String> _pickedRoles = {};
  final Set<String> _pickedWorkshops = {};
  int? _branchId;

  @override
  void initState() {
    super.initState();
    _pickedRoles.add(JobTitles.admin);
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final roles = await _api.listRoles(accessToken: widget.accessToken);
      final branches = await _api.listBranches(accessToken: widget.accessToken);
      final workshops = await _api.listWorkshops(accessToken: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _roles = roles
            .where((r) => JobTitles.all.contains(r.name) || r.name == JobTitles.legacyCompanyAdmin)
            .toList();
        if (_roles.isEmpty) _roles = roles;
        _branches = branches;
        _workshops = workshops;
        _branchId = branches.isNotEmpty ? branches.first.id : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (name.isEmpty) {
      setState(() => _error = 'Укажите ФИО');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Укажите корректный email');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Пароль не короче 6 символов');
      return;
    }
    if (_pickedRoles.isEmpty) {
      setState(() => _error = 'Выберите должность');
      return;
    }
    if (_branchId == null) {
      setState(() => _error = 'Выберите филиал');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await _api.createUser(
        accessToken: widget.accessToken,
        email: email,
        password: pass,
        fullName: name,
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        roleNames: _pickedRoles.toList(),
        branchIds: [_branchId!],
        workshops: _pickedWorkshops.toList(),
      );
      if (!mounted) return;
      Navigator.pop(context, created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Новый сотрудник',
        style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'ФИО', isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email (логин)', isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Телефон (необязательно)', isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Временный пароль',
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Должность',
                style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _roles.map((r) {
                  final on = _pickedRoles.contains(r.name);
                  return FilterChip(
                    label: Text(r.name),
                    selected: on,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _pickedRoles.add(r.name);
                      } else {
                        _pickedRoles.remove(r.name);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Text(
                'Филиал',
                style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if (_branches.isEmpty)
                Text(
                  'Филиалы не загружены',
                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                )
              else
                DropdownButtonFormField<int>(
                  value: _branchId,
                  items: _branches
                      .map((b) => DropdownMenuItem(value: b.id, child: Text(b.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _branchId = v),
                ),
              const SizedBox(height: 14),
              Text(
                'Цех (для мастера, можно несколько)',
                style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _workshops.map((w) {
                  final on = _pickedWorkshops.contains(w);
                  return FilterChip(
                    label: Text(w),
                    selected: on,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _pickedWorkshops.add(w);
                      } else {
                        _pickedWorkshops.remove(w);
                      }
                    }),
                  );
                }).toList(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: GoogleFonts.manrope(color: Colors.redAccent, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Создать'),
        ),
      ],
    );
  }
}

class _AssignUserDialog extends StatefulWidget {
  const _AssignUserDialog({required this.user, required this.accessToken});

  final AuthUser user;
  final String accessToken;

  @override
  State<_AssignUserDialog> createState() => _AssignUserDialogState();
}

class _AssignUserDialogState extends State<_AssignUserDialog> {
  final _api = CompanyApi();
  bool _busy = false;
  String? _error;
  List<CompanyRole> _roles = const [];
  List<CompanyBranch> _branches = const [];
  List<String> _workshops = const [];
  final Set<String> _pickedRoles = {};
  final Set<String> _pickedWorkshops = {};
  int? _branchId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final roles = await _api.listRoles(accessToken: widget.accessToken);
      final branches = await _api.listBranches(accessToken: widget.accessToken);
      final workshops = await _api.listWorkshops(accessToken: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _roles = roles
            .where((r) => JobTitles.all.contains(r.name) || r.name == JobTitles.legacyCompanyAdmin)
            .toList();
        if (_roles.isEmpty) _roles = roles;
        _branches = branches;
        _workshops = workshops;
        _branchId = branches.isNotEmpty ? branches.first.id : null;
        _pickedRoles.add(JobTitles.master);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _save() async {
    if (_pickedRoles.isEmpty) {
      setState(() => _error = 'Выберите должность');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.assignUser(
        accessToken: widget.accessToken,
        userId: widget.user.id,
        roleNames: _pickedRoles.toList(),
        branchIds: _branchId != null ? [_branchId!] : const [],
        workshops: _pickedWorkshops.toList(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Назначить · ${widget.user.displayLabel}',
        style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Должность',
                style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _roles.map((r) {
                  final on = _pickedRoles.contains(r.name);
                  return FilterChip(
                    label: Text(r.name),
                    selected: on,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _pickedRoles.add(r.name);
                      } else {
                        _pickedRoles.remove(r.name);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Text(
                'Цех (можно несколько)',
                style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _workshops.map((w) {
                  final on = _pickedWorkshops.contains(w);
                  return FilterChip(
                    label: Text(w),
                    selected: on,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _pickedWorkshops.add(w);
                      } else {
                        _pickedWorkshops.remove(w);
                      }
                    }),
                  );
                }).toList(),
              ),
              if (_branches.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Филиал',
                  style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  value: _branchId,
                  items: _branches
                      .map((b) => DropdownMenuItem(value: b.id, child: Text(b.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _branchId = v),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: GoogleFonts.manrope(color: Colors.redAccent, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}
