import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../app_diagnostics.dart';
import '../app_toast.dart';
import '../auth/auth_controller.dart';
import '../conn_status_sheet.dart';
import 'sync_config.dart';
import 'sync_controller.dart';
import 'sync_qr.dart';

/// Глобальный ключ навигации — чтобы deep link открыл связь из любого экрана.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Слушает `detapp://connect?url=…` (LAN) и `detapp://invite?slug=…` (облако).
class SyncDeepLink {
  SyncDeepLink._();
  static final SyncDeepLink instance = SyncDeepLink._();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _handling = false;
  String? _pendingUrl;
  String? _pendingInviteSlug;

  /// Код студии из QR, пока ждём LoginScreen / Home.
  String? takePendingInviteSlug() {
    final s = _pendingInviteSlug;
    _pendingInviteSlug = null;
    return s;
  }

  void setPendingInviteSlug(String slug) {
    final s = slug.trim().toLowerCase();
    if (s.length >= 2) _pendingInviteSlug = s;
  }

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
    final invite = _pendingInviteSlug;
    if (invite != null && invite.isNotEmpty) {
      // На Home уже вошли — приглашение для другого сотрудника; только toast.
      if (AuthController.instance.isSignedIn) {
        _pendingInviteSlug = null;
        if (context.mounted) {
          showAppToast(
            context,
            'Приглашение «$invite»: выйдите и откройте «Меня пригласили», '
            'либо передайте QR коллеге.',
          );
        }
        return;
      }
      return;
    }
    final url = _pendingUrl;
    if (url == null || url.isEmpty) return;
    _pendingUrl = null;
    await _applyAndShow(context, url);
  }

  Future<void> _handleUri(Uri uri, {required bool fromColdStart}) async {
    final invite = parseInviteSlug(uri.toString());
    if (invite != null && invite.isNotEmpty) {
      _pendingInviteSlug = invite;
      debugPrint('SyncDeepLink invite slug=$invite cold=$fromColdStart');
      final ctx = appNavigatorKey.currentContext;
      if (ctx != null && AuthController.instance.isSignedIn) {
        showAppToast(
          ctx,
          'Приглашение в студию «$invite»: для заявки нужен экран входа '
          '(выйдите или откройте на телефоне без сессии).',
        );
      }
      // LoginScreen слушает AuthController / читает pending при init.
      AuthController.instance.notifyInvitePending();
      return;
    }

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
