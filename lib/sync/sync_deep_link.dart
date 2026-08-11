import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../app_diagnostics.dart';
import '../app_toast.dart';
import '../conn_status_sheet.dart';
import 'sync_config.dart';
import 'sync_controller.dart';
import 'sync_qr.dart';

/// Глобальный ключ навигации — чтобы deep link открыл связь из любого экрана.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Слушает `detapp://connect?url=...` (QR с системной камеры → наше приложение).
class SyncDeepLink {
  SyncDeepLink._();
  static final SyncDeepLink instance = SyncDeepLink._();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _handling = false;
  String? _pendingUrl;

  Future<void> start() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        await _handleUri(initial, fromColdStart: true);
      }
    } catch (e) {
      debugPrint('SyncDeepLink initial: $e');
    }
    await _sub?.cancel();
    _sub = _appLinks.uriLinkStream.listen(
      (uri) => _handleUri(uri, fromColdStart: false),
      onError: (e) => debugPrint('SyncDeepLink stream: $e'),
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Если cold start ещё без context — вызвать после первого кадра Home.
  Future<void> flushPending(BuildContext context) async {
    final url = _pendingUrl;
    if (url == null || url.isEmpty) return;
    _pendingUrl = null;
    await _applyAndShow(context, url);
  }

  Future<void> _handleUri(Uri uri, {required bool fromColdStart}) async {
    final url = parseSyncQrPayload(uri.toString());
    if (url == null || url.isEmpty) {
      debugPrint('SyncDeepLink: ignore $uri');
      return;
    }
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) {
      _pendingUrl = url;
      return;
    }
    await _applyAndShow(ctx, url);
  }

  Future<void> _applyAndShow(BuildContext context, String url) async {
    if (_handling) return;
    _handling = true;
    try {
      final err = await SyncController.instance.applyRole(
        role: SyncRole.client,
        baseUrl: url,
      );
      await AppDiagnostics.instance.refreshConnection(force: true);
      if (!context.mounted) return;
      if (err != null) {
        showAppToast(context, err);
      } else {
        showAppToast(context, 'Подключено к $url');
      }
      // Показать экран связи с уже подставленным адресом.
      await showConnStatusSheet(context);
    } finally {
      _handling = false;
    }
  }
}
