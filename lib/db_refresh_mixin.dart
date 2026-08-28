import 'dart:async';

import 'package:flutter/material.dart';

import 'crm/cloud_mode.dart';
import 'database.dart';
import 'sync/host_revision.dart';
import 'sync/sync_controller.dart';

/// Подписка на изменения БД в обе стороны (хост ↔ клиент по LAN).
mixin DbRefreshMixin<T extends StatefulWidget> on State<T> {
  Timer? _dbRefreshDebounce;
  Timer? _syncPoll;
  int? _lastRemoteRev;
  int _lastLocalRev = -1;
  bool _pollBusy = false;

  /// Перезагрузить данные экрана (без обязательного спиннера).
  void onDatabaseChanged();

  @override
  void initState() {
    super.initState();
    _lastLocalRev = DatabaseHelper.dataRevision.value;
    DatabaseHelper.dataRevision.addListener(_onDataRevision);
    // Облако: LAN-poll не нужен (данные с API по действию). Иначе цех на телефоне
    // мигает каждые 2с из‑за ложных/лишних перечитываний.
    if (!CloudMode.enabled) {
      _syncPoll = Timer.periodic(const Duration(seconds: 3), (_) {
        unawaited(_pollSync());
      });
    }
  }

  void _onDataRevision() {
    final rev = DatabaseHelper.dataRevision.value;
    if (rev == _lastLocalRev) return;
    _lastLocalRev = rev;
    _dbRefreshDebounce?.cancel();
    _dbRefreshDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) onDatabaseChanged();
    });
  }

  Future<void> _pollSync() async {
    if (!mounted || _pollBusy || CloudMode.enabled) return;
    final sync = SyncController.instance;

    // Хост: только если локальная ревизия сдвинулась (не долбим UI каждые N сек).
    if (sync.isHosting) {
      final rev = DatabaseHelper.dataRevision.value;
      if (rev != _lastLocalRev) {
        _lastLocalRev = rev;
        onDatabaseChanged();
      }
      return;
    }

    // Клиент: смотрим rev хоста — обновились данные на ПК → перечитываем.
    if (!sync.config.isClient) return;
    final url = sync.config.normalizedBaseUrl;
    if (url.isEmpty) return;

    _pollBusy = true;
    try {
      final rev = await HostRevision.fetch(baseUrl: url, token: sync.config.token);
      if (!mounted) return;
      if (rev == null) return;
      if (_lastRemoteRev != rev) {
        _lastRemoteRev = rev;
        onDatabaseChanged();
      }
    } finally {
      _pollBusy = false;
    }
  }

  @override
  void dispose() {
    _dbRefreshDebounce?.cancel();
    _syncPoll?.cancel();
    DatabaseHelper.dataRevision.removeListener(_onDataRevision);
    super.dispose();
  }
}
