import 'dart:async';

import 'package:flutter/material.dart';

import 'database.dart';
import 'sync/host_revision.dart';
import 'sync/sync_controller.dart';

/// Подписка на изменения БД в обе стороны (хост ↔ клиент по LAN).
mixin DbRefreshMixin<T extends StatefulWidget> on State<T> {
  Timer? _dbRefreshDebounce;
  Timer? _syncPoll;
  int? _lastRemoteRev;
  bool _pollBusy = false;

  /// Перезагрузить данные экрана (без обязательного спиннера).
  void onDatabaseChanged();

  @override
  void initState() {
    super.initState();
    DatabaseHelper.dataRevision.addListener(_onDataRevision);
    _syncPoll = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pollSync());
    });
  }

  void _onDataRevision() {
    _dbRefreshDebounce?.cancel();
    _dbRefreshDebounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) onDatabaseChanged();
    });
  }

  Future<void> _pollSync() async {
    if (!mounted || _pollBusy) return;
    final sync = SyncController.instance;

    // Хост: периодически перечитываем (подстраховка + локальные правки на других экранах).
    if (sync.isHosting) {
      onDatabaseChanged();
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
      if (rev == null) {
        // Нет rev (старый хост) — всё равно подтягиваем.
        onDatabaseChanged();
        return;
      }
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
