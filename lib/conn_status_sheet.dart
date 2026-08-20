import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'access_model.dart';
import 'auth/auth_controller.dart';
import 'app_diagnostics.dart';
import 'app_theme.dart';
import 'app_toast.dart';
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

  bool _apkExpanded = false;
  bool _apkLoading = false;
  String? _apkQrUrl;
  String? _apkLabel;
  String? _apkError;

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

  Future<void> _ensureApkQr() async {
    if (_apkLoading) return;
    if (_apkQrUrl != null && _apkError == null) return;
    setState(() {
      _apkLoading = true;
      _apkError = null;
    });
    try {
      // Постоянная ссылка (после деплоя API /updates/android).
      // Если её ещё нет — берём прямой android_url из latest.json.
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
    final mq = MediaQuery.of(context);
    // SafeArea + padding уже съедают высоту — не брать 0.82 от полного экрана.
    final h = (mq.size.height - mq.padding.vertical - mq.viewInsets.bottom) * 0.88;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + mq.viewInsets.bottom),
        child: SizedBox(
          height: h.clamp(320.0, mq.size.height),
          width: AppResponsive.dialogWidth(context, desktop: 520),
          child: ListenableBuilder(
            listenable: Listenable.merge([diag, sync]),
            builder: (context, _) {
              final ok = diag.isOk;
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
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                  _SyncStatusBanner(
                    role: role,
                    ok: ok,
                    detail: diag.statusDetail,
                    hostUrl: hostUrl,
                    clientUrl: role == SyncRole.client ? sync.config.normalizedBaseUrl : null,
                    isHosting: sync.isHosting,
                  ),
                  const SizedBox(height: 10),
                  _StudioAccessBlock(),
                  const SizedBox(height: 12),
                  if (CloudMode.enabled) ...[
                    Text(
                      'Облачный режим: заказы, касса, склад и статистика — через api.det-app.ru.\n'
                      'LAN-хост :7878 не нужен — оба устройства работают по интернету.',
                      style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _importLocalClients,
                      icon: const Icon(Icons.upload_file_outlined, size: 18),
                      label: Text(
                        'Импорт клиентов из локальной БД',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ] else ...[
                  Text(
                    'Обновления и APK — с сервера api.det-app.ru.\n'
                    'Общая база ПК↔телефон пока по Wi‑Fi (хост ниже) — до облачных логинов.',
                    style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, height: 1.35),
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
                      'Этот ПК — хост. База здесь. Телефон и другой ПК — в той же Wi‑Fi.',
                      style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Ссылка для другого ПК',
                      style: GoogleFonts.manrope(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: SelectableText(
                        hostUrl ?? 'IP не найден — проверьте Wi‑Fi',
                        style: GoogleFonts.manrope(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: hostUrl == null
                            ? null
                            : () async {
                                await Clipboard.setData(ClipboardData(text: hostUrl));
                                if (!context.mounted) return;
                                showAppToast(context, 'Ссылка скопирована — вставьте на другом ПК');
                              },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Копировать ссылку'),
                      ),
                    ),
                    if (sync.lanIps.length > 1) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Если не подключается — попробуйте другой адрес:\n'
                        '${sync.lanIps.skip(1).map((ip) => 'http://$ip:${sync.config.port}').join('\n')}',
                        style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 11, height: 1.35),
                      ),
                    ],
                    if (hostUrl != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        'QR для телефона',
                        style: GoogleFonts.manrope(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: QrImageView(
                            data: encodeSyncQrPayload(hostUrl),
                            version: QrVersions.auto,
                            size: 180,
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
                      const SizedBox(height: 8),
                      Text(
                        'На телефоне: лампочка → «Сканировать QR хоста» '
                        'или камера → QR → «Открыть Det App».',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, height: 1.35),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      'Windows может спросить firewall — разрешите в частных сетях.\n'
                      'Хост не уводить в сон, пока клиенты подключены.',
                      style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, height: 1.35),
                    ),
                  ] else ...[
                    Text(
                      role == SyncRole.client
                          ? 'Вставьте ссылку с хоста или найдите его в Wi‑Fi'
                          : 'На хосте: «Хост» → скопируйте ссылку / покажите QR.\n'
                              'Здесь: вставьте ссылку, «Найти хост» или сканируйте QR.',
                      style: GoogleFonts.manrope(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
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
                        labelText: 'Ссылка с хоста',
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
                  ], // end !CloudMode LAN host UI
                  const SizedBox(height: 10),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: false,
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      onExpansionChanged: (open) {
                        setState(() => _apkExpanded = open);
                        if (open) _ensureApkQr();
                      },
                      leading: Icon(
                        Icons.android,
                        color: _apkExpanded ? AppColors.primary : AppColors.textMuted,
                        size: 22,
                      ),
                      title: Text(
                        'QR на скачивание APK',
                        style: GoogleFonts.manrope(
                          color: AppColors.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        'Актуальная мобилка с сервера',
                        style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12),
                      ),
                      children: [
                        if (_apkLoading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                          )
                        else if (_apkError != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  _apkError!,
                                  style: GoogleFonts.manrope(color: AppColors.danger, fontSize: 12),
                                ),
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
                          )
                        else if (_apkQrUrl != null) ...[
                          if (_apkLabel != null)
                            Text(
                              'Сборка $_apkLabel',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.manrope(
                                color: AppColors.textDim,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          const SizedBox(height: 8),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: QrImageView(
                                data: _apkQrUrl!,
                                version: QrVersions.auto,
                                size: 150,
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
                          const SizedBox(height: 8),
                          SelectableText(
                            _apkQrUrl!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.manrope(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: _apkQrUrl!));
                                if (!context.mounted) return;
                                showAppToast(context, 'Ссылка на APK скопирована');
                              },
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('Копировать ссылку на APK'),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Телефон: камера → QR → скачать → установить',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Последние события',
                    style: GoogleFonts.manrope(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 120,
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
                        ],
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
              );
            },
          ),
        ),
      ),
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

/// Филиал + должность + алерты назначения (по уровню доступа).
class _StudioAccessBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = AuthController.instance.user;
    final rank = accessRankOf(user);
    final branchLabel = _branchLabel(user);
    final jobLabel = _jobLabel(user, rank);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Студия',
            style: GoogleFonts.manrope(
              color: AppColors.textDim,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          _kv('Филиал', branchLabel),
          const SizedBox(height: 4),
          _kv('Должность', jobLabel),
          if (canManageAssignments(rank)) ...[
            const SizedBox(height: 10),
            Text(
              'Назначения',
              style: GoogleFonts.manrope(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Пока никто не ждёт роль. Когда сотрудник подключится к филиалу, '
              'он появится здесь — назначьте должность и цех.',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, height: 1.35),
            ),
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
    final roles = (user.roles as List?)?.map((e) => e.toString()).toList() ?? const [];
    if (roles.isEmpty) return 'Мастер (без должности в облаке)';
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
