import 'package:flutter/foundation.dart';

import 'database.dart';

/// Типы событий inbox.
class AppNotificationTypes {
  AppNotificationTypes._();

  static const workshopDone = 'workshop_done';
  static const workDone = 'work_done';
  static const packageDone = 'package_done';
  static const statusChanged = 'status_changed';
  static const statusReady = 'status_ready';
  static const clientReadyWa = 'client_ready_wa';
}

/// Локальные prefs: какие типы писать / показывать долги.
class NotificationPrefs {
  NotificationPrefs._();

  /// Цех «Готово», работы, пакеты.
  static const workshopDone = 'notif_workshop_done';
  /// Смены статуса (в т.ч. подготовка к выдаче). Старый ключ сохранён.
  static const statusReady = 'notif_status_ready';
  static const showDebts = 'notif_show_debts';

  static Future<bool> isEnabled(String key, {bool defaultValue = true}) async {
    final v = await DatabaseHelper().getAppSetting(key);
    if (v == null || v.isEmpty) return defaultValue;
    return v == '1' || v.toLowerCase() == 'true';
  }

  static Future<void> setEnabled(String key, bool enabled) async {
    await DatabaseHelper().setAppSetting(key, enabled ? '1' : '0');
  }

  static Future<bool> worksEnabled() => isEnabled(workshopDone);
  static Future<bool> statusEnabled() => isEnabled(statusReady);
  static Future<bool> showDebtsEnabled() => isEnabled(showDebts);

  static Future<bool> workshopDoneEnabled() => worksEnabled();
  static Future<bool> statusReadyEnabled() => statusEnabled();
}

/// Центр in-app уведомлений + badge.
class AppNotifications {
  AppNotifications._();

  /// Меняется после insert / mark read — для бейджа на доске.
  static final ValueNotifier<int> unreadRevision = ValueNotifier(0);

  static Future<void> refreshUnread() async {
    unreadRevision.value = await DatabaseHelper().countUnreadNotifications();
  }

  static Future<String> _orderBody(int orderId, {String? clientName, String? carLabel}) async {
    var who = (clientName ?? '').trim();
    var car = (carLabel ?? '').trim();
    if (who.isEmpty || car.isEmpty) {
      final order = await DatabaseHelper().getOrderById(orderId);
      if (order != null) {
        if (who.isEmpty) who = order['client_name']?.toString().trim() ?? '';
        if (car.isEmpty) {
          car = [
            order['make_model']?.toString().trim() ?? '',
            order['plate']?.toString().trim() ?? '',
          ].where((s) => s.isNotEmpty).join(' · ');
        }
      }
    }
    return [
      if (who.isNotEmpty) who,
      if (car.isNotEmpty) car,
      'Заказ #$orderId',
    ].join(' · ');
  }

  static Future<int> post({
    required String type,
    required String title,
    String body = '',
    int? orderId,
    bool markRead = false,
    bool skipIfUnreadDuplicate = false,
  }) async {
    if (skipIfUnreadDuplicate && orderId != null) {
      final exists = await DatabaseHelper().hasUnreadNotification(
        type: type,
        orderId: orderId,
        title: title,
      );
      if (exists) return 0;
    }
    final id = await DatabaseHelper().insertNotification(
      type: type,
      title: title,
      body: body,
      orderId: orderId,
      markRead: markRead,
    );
    await refreshUnread();
    return id;
  }

  static Future<void> postWorkshopDone({
    required int orderId,
    required String workshop,
    String? clientName,
    String? carLabel,
  }) async {
    if (!await NotificationPrefs.worksEnabled()) return;
    final title = 'Цех «$workshop»: готово';
    final body = await _orderBody(orderId, clientName: clientName, carLabel: carLabel);
    await post(
      type: AppNotificationTypes.workshopDone,
      title: title,
      body: body,
      orderId: orderId,
      skipIfUnreadDuplicate: true,
    );
  }

  /// Отдельная работа отмечена выполненной.
  static Future<void> postWorkDone({
    required int orderId,
    required String workName,
    String? workshop,
    String? clientName,
    String? carLabel,
  }) async {
    if (!await NotificationPrefs.worksEnabled()) return;
    final name = workName.trim();
    if (name.isEmpty) return;
    final ws = (workshop ?? '').trim();
    final title = ws.isNotEmpty ? '$ws: работа выполнена' : 'Работа выполнена';
    final bodyParts = <String>[
      name,
      await _orderBody(orderId, clientName: clientName, carLabel: carLabel),
    ];
    await post(
      type: AppNotificationTypes.workDone,
      title: title,
      body: bodyParts.join(' · '),
      orderId: orderId,
    );
  }

  /// Пакет оклейки выполнен.
  static Future<void> postPackageDone({
    required int orderId,
    required String packageName,
    int positions = 0,
    String? clientName,
    String? carLabel,
  }) async {
    if (!await NotificationPrefs.worksEnabled()) return;
    final label = packageName.trim().isEmpty ? 'Оклейка' : packageName.trim();
    final title = positions > 0
        ? 'Пакет «$label» выполнен ($positions поз.)'
        : 'Пакет «$label» выполнен';
    final body = await _orderBody(orderId, clientName: clientName, carLabel: carLabel);
    await post(
      type: AppNotificationTypes.packageDone,
      title: title,
      body: body,
      orderId: orderId,
    );
  }

  /// Если все работы цеха выполнены — доп. сводка (без дубля того же заголовка).
  static Future<void> maybePostWorkshopAllDone({
    required int orderId,
    required String workshop,
    String? clientName,
    String? carLabel,
  }) async {
    final ws = workshop.trim();
    if (ws.isEmpty) return;
    final items = await DatabaseHelper().getOrderItems(orderId);
    final inWs = items.where((i) {
      final itemWs = (i['workshop']?.toString() ?? '').trim();
      if (itemWs.isNotEmpty) return itemWs == ws;
      final name = i['name']?.toString() ?? '';
      return name == ws || name.startsWith('$ws ·') || name.startsWith('$ws·');
    }).toList();
    if (inWs.isEmpty) return;
    final allDone = inWs.every((i) => (i['is_done'] as num?)?.toInt() == 1);
    if (!allDone) return;
    await postWorkshopDone(
      orderId: orderId,
      workshop: ws,
      clientName: clientName,
      carLabel: carLabel,
    );
  }

  /// Любая смена статуса заказа.
  static Future<void> postStatusChanged({
    required int orderId,
    required String newStatus,
    String? clientName,
    String? carLabel,
  }) async {
    if (!await NotificationPrefs.statusEnabled()) return;
    final status = newStatus.trim();
    if (status.isEmpty) return;
    final body = await _orderBody(orderId, clientName: clientName, carLabel: carLabel);
    if (status == 'Подготовка к выдаче') {
      await post(
        type: AppNotificationTypes.statusReady,
        title: 'Готов к выдаче',
        body: body,
        orderId: orderId,
        skipIfUnreadDuplicate: true,
      );
      return;
    }
    await post(
      type: AppNotificationTypes.statusChanged,
      title: 'Статус → $status',
      body: body,
      orderId: orderId,
      skipIfUnreadDuplicate: true,
    );
  }

  /// WA клиенту — в ленту без badge (сразу прочитано).
  static Future<void> postClientReadyWa({
    required int orderId,
    String? clientName,
  }) async {
    final who = (clientName ?? '').trim();
    await post(
      type: AppNotificationTypes.clientReadyWa,
      title: 'Клиенту отправлено «готов»',
      body: [
        if (who.isNotEmpty) who,
        'Заказ #$orderId',
      ].join(' · '),
      orderId: orderId,
      markRead: true,
    );
  }

  static Future<void> markRead(int id) async {
    await DatabaseHelper().markNotificationRead(id);
    await refreshUnread();
  }

  static Future<void> markAllRead() async {
    await DatabaseHelper().markAllNotificationsRead();
    await refreshUnread();
  }
}
