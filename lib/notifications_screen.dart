import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'app_notifications.dart';
import 'app_theme.dart';
import 'app_toast.dart';
import 'database.dart';
import 'debt_reminder.dart';
import 'order_details_dialog.dart';
import 'responsive.dart';

/// Центр уведомлений: долги + лента событий.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static final _money = NumberFormat('#,##0.##', 'ru_RU');

  bool _loading = true;
  List<Map<String, dynamic>> _items = const [];
  List<Map<String, dynamic>> _debts = const [];
  List<Map<String, dynamic>> _warranties = const [];
  bool _showDebts = true;
  bool _prefWorkshop = true;
  bool _prefReady = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final showDebts = await NotificationPrefs.showDebtsEnabled();
    final prefWorkshop = await NotificationPrefs.workshopDoneEnabled();
    final prefReady = await NotificationPrefs.statusReadyEnabled();
    // Лента = только непрочитанные: после «Прочитать всё» строки исчезают.
    final items = await DatabaseHelper().listUnreadNotifications();
    var debts = showDebts ? await DatabaseHelper().getOrderDebts(limit: 30) : <Map<String, dynamic>>[];
    debts = debts.where((d) {
      final debt = (d['debt'] as num?)?.toDouble() ??
          (((d['price'] as num?)?.toDouble() ?? 0) - ((d['paid_amount'] as num?)?.toDouble() ?? 0));
      return debt > 0.01;
    }).map((d) {
      if (d['debt'] != null) return d;
      final m = Map<String, dynamic>.from(d);
      m['debt'] = ((m['price'] as num?)?.toDouble() ?? 0) - ((m['paid_amount'] as num?)?.toDouble() ?? 0);
      return m;
    }).toList();
    final warranties = await DatabaseHelper().getUpcomingWarrantyReminders(withinDays: 14);
    for (final w in warranties) {
      final id = (w['id'] as num?)?.toInt();
      final sent = (w['reminder_sent'] as num?)?.toInt() == 1 || w['reminder_sent'] == true;
      if (id == null || sent) continue;
      final kind = w['kind']?.toString() ?? 'Покрытие';
      final ends = w['ends_at']?.toString() ?? '';
      final client = w['client_name']?.toString() ?? '';
      await AppNotifications.post(
        type: 'warranty_due',
        title: 'ТО покрытия · $kind',
        body: [
          if (client.isNotEmpty) client,
          if ((w['make_model']?.toString() ?? '').isNotEmpty) w['make_model'],
          if (ends.isNotEmpty) 'до $ends',
        ].join(' · '),
      );
      await DatabaseHelper().markWarrantyReminderSent(id);
    }
    await AppNotifications.refreshUnread();
    if (!mounted) return;
    setState(() {
      _showDebts = showDebts;
      _prefWorkshop = prefWorkshop;
      _prefReady = prefReady;
      _items = items;
      _debts = debts;
      _warranties = warranties;
      _loading = false;
    });
  }

  Future<void> _openOrder(int? orderId) async {
    if (orderId == null) return;
    final order = await DatabaseHelper().getOrderById(orderId);
    if (!mounted || order == null) {
      if (mounted) showAppToast(context, 'Заказ не найден');
      return;
    }
    await OrderDetailsDialog.open(context, order);
    if (mounted) _reload();
  }

  Future<void> _onTapItem(Map<String, dynamic> row) async {
    final id = (row['id'] as num?)?.toInt();
    final orderId = (row['order_id'] as num?)?.toInt();
    final readAt = row['read_at']?.toString();
    if (id != null && (readAt == null || readAt.isEmpty)) {
      await AppNotifications.markRead(id);
    }
    await _openOrder(orderId);
  }

  Future<void> _markAll() async {
    await AppNotifications.markAllRead();
    if (!mounted) return;
    showAppToast(context, 'Все прочитаны');
    setState(() => _items = const []);
    await AppNotifications.refreshUnread();
  }

  Future<void> _remindDebt(Map<String, dynamic> d) async {
    final id = (d['id'] as num).toInt();
    final debt = (d['debt'] as num?)?.toDouble() ?? 0;
    final text = await DebtReminder.buildTextAsync(
      clientName: d['client_name']?.toString() ?? '',
      orderId: id,
      debt: debt,
      plate: d['plate']?.toString(),
      car: d['make_model']?.toString(),
    );
    if (!mounted) return;
    final r = await DebtReminder.sharePickChannel(
      context,
      phone: d['client_phone']?.toString(),
      text: text,
      title: 'Напоминание о долге',
    );
    if (!mounted || r == 'cancelled') return;
    final msg = DebtReminder.toastForResult(r);
    if (msg.isNotEmpty) showAppToast(context, msg);
  }

  String _fmtWhen(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw.contains('T') ? raw : raw.replaceFirst(' ', 'T'));
    if (dt == null) return raw;
    return DateFormat('dd.MM HH:mm').format(dt);
  }

  IconData _iconFor(String type) {
    switch (type) {
      case AppNotificationTypes.workshopDone:
        return Icons.handyman_outlined;
      case AppNotificationTypes.workDone:
        return Icons.check_circle_outline;
      case AppNotificationTypes.packageDone:
        return Icons.layers_outlined;
      case AppNotificationTypes.statusChanged:
        return Icons.swap_horiz_rounded;
      case AppNotificationTypes.statusReady:
        return Icons.outbound_outlined;
      case AppNotificationTypes.clientReadyWa:
        return Icons.chat_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hPad = AppResponsive.pagePadH(context);
    final mobile = AppResponsive.isMobile(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, mobile ? 14 : 20, hPad, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Уведомления', style: AppTheme.pageTitle),
                      const SizedBox(height: 4),
                      Text(
                        'Лента событий и открытые долги',
                        style: AppTheme.pageSubtitle,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _items.isEmpty ? null : _markAll,
                  child: Text(
                    'Прочитать всё',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Обновить',
                  onPressed: _loading ? null : _reload,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, color: AppColors.textDim),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 28),
                    children: [
                      if (_showDebts) ...[
                        _sectionLabel('Долги'),
                        const SizedBox(height: 8),
                        if (_debts.isEmpty)
                          _emptyHint('Открытых долгов нет')
                        else
                          ..._debts.map(_debtTile),
                        const SizedBox(height: 22),
                      ],
                      _sectionLabel('Гарантии · ТО (14 дней)'),
                      const SizedBox(height: 8),
                      if (_warranties.isEmpty)
                        _emptyHint('Ближайших гарантий нет')
                      else
                        ..._warranties.map(_warrantyTile),
                      const SizedBox(height: 22),
                      _sectionLabel('Лента'),
                      const SizedBox(height: 8),
                      if (_items.isEmpty)
                        _emptyHint('Нет новых · отмеченные «Прочитать всё» скрыты из ленты')
                      else
                        ..._items.map(_feedTile),
                      const SizedBox(height: 22),
                      _sectionLabel('Настройки'),
                      const SizedBox(height: 8),
                      _prefsCard(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _warrantyTile(Map<String, dynamic> w) {
    final kind = w['kind']?.toString() ?? 'Покрытие';
    final ends = w['ends_at']?.toString() ?? '';
    final client = w['client_name']?.toString() ?? '';
    final car = [
      w['make_model']?.toString() ?? '',
      w['plate']?.toString() ?? '',
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$kind · до $ends',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.text),
          ),
          const SizedBox(height: 4),
          Text(
            [if (client.isNotEmpty) client, if (car.isNotEmpty) car].join(' · '),
            style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.manrope(
        color: AppColors.textDim,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.7,
      ),
    );
  }

  Widget _emptyHint(String text) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Text(
        text,
        style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13, height: 1.35),
      ),
    );
  }

  Widget _debtTile(Map<String, dynamic> d) {
    final id = (d['id'] as num).toInt();
    final debt = (d['debt'] as num?)?.toDouble() ?? 0;
    final name = d['client_name']?.toString() ?? 'Клиент';
    final car = [
      d['make_model']?.toString() ?? '',
      d['plate']?.toString() ?? '',
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openOrder(id),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderSoft),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8A838).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.payments_outlined, size: 18, color: Color(0xFFE8A838)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#$id · $name',
                        style: GoogleFonts.manrope(
                          color: AppColors.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      if (car.isNotEmpty)
                        Text(car, style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12)),
                      Text(
                        '${_money.format(debt)} ₽',
                        style: GoogleFonts.manrope(
                          color: const Color(0xFFE8A838),
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Напомнить клиенту',
                  onPressed: () => _remindDebt(d),
                  icon: const Icon(Icons.chat_outlined, size: 20, color: AppColors.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _feedTile(Map<String, dynamic> row) {
    final type = row['type']?.toString() ?? '';
    final title = row['title']?.toString() ?? '';
    final body = row['body']?.toString() ?? '';
    final created = _fmtWhen(row['created_at']?.toString());
    final unread = (row['read_at'] == null || row['read_at'].toString().isEmpty);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: unread ? AppColors.surface : AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _onTapItem(row),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: unread ? AppColors.primary.withValues(alpha: 0.45) : AppColors.borderSoft,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: unread ? 0.18 : 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_iconFor(type), size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: GoogleFonts.manrope(
                                color: AppColors.text,
                                fontWeight: unread ? FontWeight.w800 : FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          if (unread)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12.5, height: 1.3),
                        ),
                      ],
                      if (created.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          created,
                          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _prefsCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            title: Text('Работы и цеха', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5)),
            subtitle: Text(
              'Готово в цехе, галочки работ, пакет оклейки',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11.5),
            ),
            value: _prefWorkshop,
            activeThumbColor: AppColors.primary,
            onChanged: (v) async {
              setState(() => _prefWorkshop = v);
              await NotificationPrefs.setEnabled(NotificationPrefs.workshopDone, v);
            },
          ),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            title: Text('Смены статуса', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5)),
            subtitle: Text(
              'Любой статус, в т.ч. подготовка к выдаче',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11.5),
            ),
            value: _prefReady,
            activeThumbColor: AppColors.primary,
            onChanged: (v) async {
              setState(() => _prefReady = v);
              await NotificationPrefs.setEnabled(NotificationPrefs.statusReady, v);
            },
          ),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            title: Text('Показывать долги', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5)),
            subtitle: Text('Блок сверху на этом экране', style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11.5)),
            value: _showDebts,
            activeThumbColor: AppColors.primary,
            onChanged: (v) async {
              await NotificationPrefs.setEnabled(NotificationPrefs.showDebts, v);
              if (mounted) _reload();
            },
          ),
        ],
      ),
    );
  }
}
