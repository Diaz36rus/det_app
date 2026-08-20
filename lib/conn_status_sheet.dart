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
import 'bug_report_dialog.dart';
import 'crm/cloud_mode.dart';
import 'database.dart';
import 'responsive.dart';
import 'sync/lan_discover.dart';
import 'sync/qr_scan_sheet.dart';
import 'sync/sync_config.dart';
import 'sync/sync_controller.dart';
import 'sync/sync_qr.dart';
import 'update/update_channel.dart';

bool get _canScanSyncQr => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Публичная точка облака (приглашение / health).
const _kCloudBase = AuthApi.defaultBaseUrl;
const _kInviteUrl = AuthApi.defaultBaseUrl;

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
      try {
        final head = await http
            .head(Uri.parse(UpdateChannel.cloudApkUrl))
            .timeout(const Duration(seconds: 6));
        if (head.statusCode < 200 || head.statusCode >= 400) {
          qrUrl = '';
        }
      } catch (_) {
        qrUrl = '';
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
                            const SizedBox(height: 12),
                            _InviteBlock(
                              inviteUrl: _kInviteUrl,
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

class _InviteBlock extends StatelessWidget {
  const _InviteBlock({
    required this.inviteUrl,
    required this.canManage,
    this.onStaffCreated,
  });

  final String inviteUrl;
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
            canManage ? 'Пригласить в студию' : 'Подключение',
            style: GoogleFonts.manrope(
              color: AppColors.textDim,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          if (canManage) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => _openCreate(context),
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: Text(
                'Добавить с должностью',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Владелец / управляющий / админ / мастер — сразу с филиалом и доступом.',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 14),
            Text(
              'Или по QR (сам запросит доступ)',
              style: GoogleFonts.manrope(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: inviteUrl,
                version: QrVersions.auto,
                size: canManage ? 132 : 148,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            canManage
                ? 'Сотрудник ставит приложение и запрашивает доступ — появится в «Назначениях».'
                : 'Облако Det App · api.det-app.ru',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: inviteUrl));
              if (!context.mounted) return;
              showAppToast(context, 'Ссылка скопирована');
            },
            icon: const Icon(Icons.link_rounded, size: 18),
            label: const Text('Скопировать ссылку'),
          ),
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
  List<AuthUser> _pending = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final rank = accessRankOf(AuthController.instance.user);
    if (canManageAssignments(rank)) {
      _loadPending();
    }
  }

  void reloadPending() => _loadPending();

  Future<void> _loadPending() async {
    final token = AuthController.instance.accessToken;
    if (token == null || token.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _api.listUsers(accessToken: token, pending: true);
      if (!mounted) return;
      setState(() {
        _pending = rows;
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

  Future<void> _openAssign(AuthUser u) async {
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _AssignUserDialog(user: u, accessToken: token),
    );
    if (ok == true) {
      showAppToast(context, 'Назначено: ${u.displayLabel}');
      await _loadPending();
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
      await _loadPending();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthController.instance.user;
    final rank = accessRankOf(user);
    final branchLabel = _branchLabel(user);
    final jobLabel = _jobLabel(user, rank);

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
            ],
          ),
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
                    tooltip: 'Обновить',
                    onPressed: _loadPending,
                    icon: const Icon(Icons.refresh, size: 18, color: AppColors.textDim),
                  ),
              ],
            ),
            if (_error != null)
              Text(_error!, style: GoogleFonts.manrope(color: Colors.redAccent, fontSize: 11))
            else if (_pending.isEmpty)
              Text(
                'Никто не ждёт роль. Новый сотрудник появится здесь после подключения.',
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

  static String _branchLabel(dynamic user) {
    if (user == null) return 'Не вошли';
    final ids = (user.branchIds as List?) ?? const [];
    if (ids.isEmpty) {
      if (user.isPlatformAdmin == true) return 'Все филиалы (владелец приложения)';
      return 'Основной филиал';
    }
    if (ids.length == 1) return 'Филиал #${ids.first}';
    return '${ids.length} филиала(ов)';
  }

  static String _jobLabel(dynamic user, AccessRank rank) {
    if (user == null) return '—';
    if (rank == AccessRank.platformOwner) return 'Владелец приложения';
    if (user.pendingAssignment == true) return 'Ожидает назначение';
    final roles = (user.roles as List?)?.map((e) => e.toString()).toList() ?? const [];
    if (roles.isEmpty) return 'Без должности';
    return roles.join(', ');
  }

  static Widget _kv(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            k,
            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w700),
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
