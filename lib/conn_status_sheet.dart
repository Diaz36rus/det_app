import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'app_diagnostics.dart';
import 'app_theme.dart';
import 'bug_report_dialog.dart';
import 'responsive.dart';
import 'app_toast.dart';
import 'sync/lan_discover.dart';
import 'sync/qr_scan_sheet.dart';
import 'sync/sync_config.dart';
import 'sync/sync_controller.dart';
import 'sync/sync_qr.dart';

bool get _canScanSyncQr => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

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

class _ConnStatusSheetState extends State<_ConnStatusSheet> {
  final _urlCtrl = TextEditingController();
  bool _busy = false;
  bool _scanning = false;
  int _scanDone = 0;
  int _scanTotal = 0;
  List<DiscoveredHost> _foundHosts = const [];

  @override
  void initState() {
    super.initState();
    final sync = SyncController.instance;
    _urlCtrl.text = sync.config.isClient
        ? sync.config.normalizedBaseUrl
        : (sync.suggestedClientUrl ?? '');
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanHostQr() async {
    if (_busy || _scanning) return;
    final url = await scanSyncHostQr(context);
    if (!mounted || url == null || url.trim().isEmpty) return;
    setState(() => _urlCtrl.text = url.trim());
    await _apply(SyncRole.client);
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
          // Не дёргаем UI на каждый IP.
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
        if (mounted) {
          showAppToast(
            context,
            'Хост не найден. ПК в режиме «Хост» и в той же Wi‑Fi?',
          );
        }
        return;
      }
      if (hosts.length == 1) {
        _urlCtrl.text = hosts.first.baseUrl;
        await _apply(SyncRole.client); // тост с URL — внутри _apply
        return;
      }
      // Несколько — подставим первый, выбор ниже в списке.
      _urlCtrl.text = hosts.first.baseUrl;
      if (mounted) {
        showAppToast(
          context,
          'Найдено хостов: ${hosts.length}. Выберите нужный.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Поиск не удался: $e')),
      );
    }
  }

  Future<void> _apply(SyncRole role) async {
    setState(() => _busy = true);
    final sync = SyncController.instance;
    String? err;
    if (role == SyncRole.client) {
      err = await sync.applyRole(role: role, baseUrl: _urlCtrl.text);
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
            ? 'Хост запущен. Клиенты: «Найти хост» или URL с этого ПК.'
            : role == SyncRole.client
                ? 'Подключено к ${_urlCtrl.text.trim().isNotEmpty ? _urlCtrl.text.trim() : 'хосту'} — заказы общие'
                : 'Локальный режим (данные только на этом устройстве).';
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
    final h = MediaQuery.sizeOf(context).height * 0.82;

    return ListenableBuilder(
      listenable: Listenable.merge([diag, sync]),
      builder: (context, _) {
        final ok = diag.isOk;
        final role = sync.config.role;
        final hostUrl = sync.suggestedClientUrl;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
            child: SizedBox(
              height: h,
              width: AppResponsive.dialogWidth(context, desktop: 520),
              child: Column(
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
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'Связь и синхронизация',
                        style: GoogleFonts.manrope(
                          color: AppColors.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Обновить',
                        onPressed: _busy
                            ? null
                            : () => diag.refreshConnection(force: true),
                        icon: const Icon(Icons.refresh, color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _SyncStatusBanner(
                    role: role,
                    ok: ok,
                    detail: diag.statusDetail,
                    hostUrl: hostUrl,
                    clientUrl: role == SyncRole.client ? sync.config.normalizedBaseUrl : null,
                    isHosting: sync.isHosting,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Режим работы',
                    style: GoogleFonts.manrope(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
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
                        onSelected: _busy
                            ? null
                            : (_) {
                                _apply(SyncRole.client);
                              },
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
                    Text(
                      'Этот ноут — главный. База здесь. На втором ноуте вставьте адрес:',
                      style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      hostUrl ?? 'IP не найден — проверьте Wi‑Fi',
                      style: GoogleFonts.manrope(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    if (sync.lanIps.length > 1) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Другие IP: ${sync.lanIps.skip(1).map((ip) => 'http://$ip:${sync.config.port}').join(', ')}',
                        style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: hostUrl == null
                          ? null
                          : () async {
                              await Clipboard.setData(ClipboardData(text: hostUrl));
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('URL скопирован')),
                              );
                            },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Копировать URL для клиента'),
                    ),
                    if (hostUrl != null) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: QrImageView(
                            // Не чистый http:// — иначе системная камера уходит в браузер.
                            data: encodeSyncQrPayload(hostUrl),
                            version: QrVersions.auto,
                            size: 168,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Color(0xFF111827),
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Телефон: камера → QR → «Открыть Det App». '
                        'Или на телефоне: связь → «Сканировать QR хоста» / «Найти хост».',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Firewall: при запросе Windows разрешите доступ в частных сетях.\n'
                      'Оба ноута — в одной Wi‑Fi (не «гостевая» с изоляцией клиентов).\n'
                      'Хост не выключать и не уводить в сон на время смены.',
                      style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, height: 1.35),
                    ),
                  ] else ...[
                    Text(
                      role == SyncRole.client
                          ? 'Адрес хоста — найдите в сети или вставьте вручную'
                          : 'На ПК: «Хост». Здесь: «Найти хост» или вставьте URL',
                      style: GoogleFonts.manrope(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
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
                            ? (_scanTotal > 0
                                ? 'Поиск… $_scanDone/$_scanTotal'
                                : 'Поиск в сети…')
                            : 'Найти хост в Wi‑Fi',
                      ),
                    ),
                    if (_scanning) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        minHeight: 2,
                        value: _scanTotal > 0 ? _scanDone / _scanTotal : null,
                      ),
                    ],
                    if (_foundHosts.length > 1) ...[
                      const SizedBox(height: 8),
                      ..._foundHosts.map(
                        (h) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Material(
                            color: AppColors.surface2,
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
                                child: Row(
                                  children: [
                                    const Icon(Icons.dns_outlined, size: 18, color: AppColors.primary),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        h.baseUrl,
                                        style: GoogleFonts.manrope(
                                          color: AppColors.text,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'Подключить',
                                      style: GoogleFonts.manrope(
                                        color: AppColors.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    TextField(
                      controller: _urlCtrl,
                      enabled: !_busy && !_scanning,
                      decoration: const InputDecoration(
                        hintText: 'http://192.168.0.10:7878',
                        isDense: true,
                        labelText: 'Вручную (если поиск не нашёл)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: (_busy || _scanning) ? null : () => _apply(SyncRole.client),
                            child: const Text('Подключить как клиент'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: (_busy || _scanning)
                              ? null
                              : () async {
                                  _urlCtrl.clear();
                                  setState(() => _foundHosts = const []);
                                  await _apply(SyncRole.local);
                                },
                          child: const Text('Сброс'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Последние события',
                    style: GoogleFonts.manrope(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: diag.recentErrors.isEmpty
                          ? Center(
                              child: Text(
                                'Лог пока пуст',
                                style: GoogleFonts.manrope(color: AppColors.textDim),
                              ),
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
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final text = diag.formatLogForBugReport();
                            await Clipboard.setData(ClipboardData(text: text));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Лог скопирован')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Копировать лог'),
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
                                initialSituation: diag.statusDetail,
                              ),
                            );
                            if (ok == true) {
                              await diag.acknowledgeLocalErrors();
                              if (context.mounted) Navigator.pop(context);
                            }
                          },
                          icon: const Icon(Icons.bug_report, size: 18),
                          label: const Text('В баг-репорт'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SyncStatusBanner extends StatelessWidget {
  final SyncRole role;
  final bool ok;
  final String detail;
  final String? hostUrl;
  final String? clientUrl;
  final bool isHosting;

  const _SyncStatusBanner({
    required this.role,
    required this.ok,
    required this.detail,
    required this.hostUrl,
    required this.clientUrl,
    required this.isHosting,
  });

  @override
  Widget build(BuildContext context) {
    late final Color accent;
    late final IconData icon;
    late final String title;
    late final String subtitle;

    switch (role) {
      case SyncRole.host:
        accent = isHosting && ok ? AppColors.success : AppColors.primary;
        icon = Icons.dns_outlined;
        title = isHosting ? 'Хост активен — база на этом ПК' : 'Хост (запуск…)';
        subtitle = hostUrl?.isNotEmpty == true
            ? 'Клиенты подключаются к $hostUrl'
            : detail;
      case SyncRole.client:
        accent = ok ? AppColors.success : AppColors.danger;
        icon = ok ? Icons.cloud_done_outlined : Icons.cloud_off_outlined;
        title = ok ? 'Клиент подключён — заказы общие' : 'Клиент: хост недоступен';
        subtitle = (clientUrl != null && clientUrl!.isNotEmpty) ? clientUrl! : detail;
      case SyncRole.local:
        accent = AppColors.textMuted;
        icon = Icons.computer_outlined;
        title = 'Один ПК — данные только здесь';
        subtitle = detail.isNotEmpty ? detail : 'Телефон/второй ПК не синхронизируются';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border(
          left: BorderSide(color: accent.withOpacity(0.9), width: 3.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    color: AppColors.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: GoogleFonts.manrope(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: ok ? AppColors.success : AppColors.danger,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (ok ? AppColors.success : AppColors.danger).withOpacity(0.45),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
