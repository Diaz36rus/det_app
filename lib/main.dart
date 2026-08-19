import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app_datetime.dart';
import 'app_diagnostics.dart';
import 'app_menu.dart';
import 'app_theme.dart';
import 'app_tour.dart';
import 'app_version.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_gate.dart';
import 'backup_helper.dart';
import 'bug_report_dialog.dart';
import 'conn_status_sheet.dart';
import 'crm/cloud_db_bridge.dart';
import 'crm/cloud_mode.dart';
import 'tour_keys.dart';
import 'update/update_dialog.dart';
import 'update/update_service.dart';
import 'calendar_screen.dart';
import 'cash_screen.dart';
import 'clients_screen.dart';
import 'completed_orders_screen.dart';
import 'database.dart';
import 'dev_guard.dart';
import 'kanban_screen.dart';
import 'services_screen.dart';
import 'warehouse_screen.dart';
import 'masters_screen.dart';
import 'menu_backgrounds.dart';
import 'orders_screen.dart';
import 'patch_notes.dart';
import 'pulse_anchor.dart';
import 'responsive.dart';
import 'search_dialog.dart';
import 'stats_screen.dart';
import 'sync/sync_controller.dart';
import 'sync/sync_deep_link.dart';
import 'workshops_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Шрифты из google_fonts/ в assets — без скачивания на рабочем ПК офлайн.
  GoogleFonts.config.allowRuntimeFetching = false;
  await initializeDateFormatting('ru');
  await AppVersion.ensureLoaded();
  // Desktop: sqflite через FFI. Android/iOS: встроенный sqflite-плагин.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  try {
    await SyncController.instance.load();
    await DatabaseHelper().initDefaultData();
    // Хост: раздаём локальную БД по Wi‑Fi. Клиент: бэкап локального файла не нужен.
    if (!SyncController.instance.config.isClient) {
      await BackupHelper.runDailyBackup();
    }
    await AppDiagnostics.instance.start();
    // QR / deep link detapp:// — только на телефоне имеет смысл.
    if (Platform.isAndroid || Platform.isIOS) {
      await SyncDeepLink.instance.start();
    }
    // Облачная сессия: после bootstrap решаем, нужен ли LAN-хост.
    await AuthController.instance.bootstrap();
    AuthController.instance.addListener(_syncLanWithCloudMode);
    await _syncLanWithCloudMode();
    runApp(const DetApp());
  } catch (e, st) {
    debugPrint('Startup failed: $e\n$st');
    runApp(_StartupErrorApp(message: '$e'));
  }
}

Future<void> _syncLanWithCloudMode() async {
  if (CloudMode.enabled) {
    await SyncController.instance.stopHost();
  } else {
    await SyncController.instance.startHostIfNeeded();
  }
}

class _StartupErrorApp extends StatelessWidget {
  final String message;
  const _StartupErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0F1419),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Не удалось запустить',
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(color: const Color(0xFF94A3B8), height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DetApp extends StatelessWidget {
  const DetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Детейлинг Студия',
      locale: const Locale('ru', 'RU'),
      supportedLocales: const [
        Locale('ru', 'RU'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: [TourNavBridge.instance],
      theme: AppTheme.build(),
      home: const AuthGate(child: HomeScreen()),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with PulseHighlightMixin {
  DateTime _selectedCalendarDate = DateTime.now();
  int _selectedIndex = AppMenuIds.board;
  String _selectedWorkshop = WORKSHOPS.first;
  DateTime? _newOrderDate;
  TimeOfDay? _newOrderTime;
  int _openBugs = 0;
  DateTime? _lastBackupAt;

  static const _pulseSearch = 'nav_search';
  static const _pulseUpdate = 'nav_update';
  static const _pulseBackup = 'nav_backup';

  /// Mobile: false = ПК+телефон (облегчённый), true = «полный телефон».
  /// Desktop меню всегда полное.
  bool _mobileFullPhone = false;

  /// Единый список пунктов меню. [id] стабилен для switch / туров / навигации.
  final List<Map<String, dynamic>> _menuItems = [
    {"id": AppMenuIds.board, "icon": Icons.dashboard_outlined, "label": "Доска заказов"},
    {"id": AppMenuIds.newOrder, "icon": Icons.add_shopping_cart_outlined, "label": "Новый заказ"},
    {"id": AppMenuIds.calendar, "icon": Icons.calendar_month_outlined, "label": "Календарь"},
    {"id": AppMenuIds.clients, "icon": Icons.people_outline, "label": "Клиенты"},
    {"id": AppMenuIds.cash, "icon": Icons.account_balance_wallet_outlined, "label": "Касса"},
    {"id": AppMenuIds.stats, "icon": Icons.insights_outlined, "label": "Статистика"},
    {"id": AppMenuIds.staff, "icon": Icons.engineering_outlined, "label": "Сотрудники"},
    {"id": AppMenuIds.services, "icon": Icons.home_repair_service_outlined, "label": "Прайс"},
    {"id": AppMenuIds.inventory, "icon": Icons.inventory_2_outlined, "label": "Склад"},
    {
      "id": AppMenuIds.preview,
      "icon": Icons.directions_car_filled_outlined,
      "label": "Превью",
      "disabled": true,
      "subtitle": "В разработке",
    },
    {"id": AppMenuIds.completed, "icon": Icons.task_alt_outlined, "label": "Завершённые"},
  ];

  Future<void> _refreshLastBackup() async {
    final at = await BackupHelper.lastBackupAt();
    if (!mounted) return;
    setState(() => _lastBackupAt = at);
  }

  @override
  void initState() {
    super.initState();
    _refreshOpenBugs();
    _refreshLastBackup();
    _loadMobileMenuMode();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await SyncDeepLink.instance.flushPending(context);
      if (!mounted) return;
      await _maybeShowPatchNotes();
      await _maybeOfferCloudUpdate();
    });
  }

  Future<void> _maybeShowPatchNotes() async {
    if (!mounted) return;
    await maybeShowPatchNotes(context);
  }

  /// Тихая проверка облачного канала; диалог только если есть более новый build.
  Future<void> _maybeOfferCloudUpdate() async {
    if (!mounted) return;
    try {
      final result = await UpdateService.instance.check();
      if (!mounted) return;
      if (result.status != UpdateCheckStatus.available) return;
      final ver = result.manifest == null
          ? ''
          : '${result.manifest!.version}+${result.manifest!.build}';
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Доступно обновление',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
          ),
          content: Text(
            ver.isEmpty
                ? 'На сервере есть новая версия Det App.'
                : 'На сервере версия $ver.\nУстановить сейчас?',
            style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.4),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Позже')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Обновить')),
          ],
        ),
      );
      if (go == true && mounted) {
        await UpdateDialog.open(context);
      }
    } catch (e) {
      debugPrint('cloud update check: $e');
    }
  }

  Future<void> _loadMobileMenuMode() async {
    final v = await DatabaseHelper().getAppSetting(AppMenuIds.settingKey);
    if (!mounted) return;
    setState(() => _mobileFullPhone = v == AppMenuIds.modeFull);
  }

  Future<void> _setMobileFullPhone(bool full) async {
    setState(() {
      _mobileFullPhone = full;
      if (!full && AppMenuIds.lightHidden.contains(_selectedIndex)) {
        _selectedIndex = AppMenuIds.board;
      }
    });
    await DatabaseHelper().setAppSetting(
      AppMenuIds.settingKey,
      full ? AppMenuIds.modeFull : AppMenuIds.modeLight,
    );
  }

  /// Пункты, видимые в текущем контексте (desktop / full phone / light).
  List<Map<String, dynamic>> _visibleMenuItems(BuildContext context) {
    final mobile = AppResponsive.isMobile(context);
    if (!mobile || _mobileFullPhone) return _menuItems;
    return _menuItems.where((m) => !AppMenuIds.lightHidden.contains(m['id'] as int)).toList();
  }

  Future<void> _refreshOpenBugs() async {
    final n = await DatabaseHelper().countOpenBugReports();
    if (!mounted) return;
    setState(() => _openBugs = n);
  }

  String get _currentTitle {
    if (_selectedIndex == AppMenuIds.workshop) return _selectedWorkshop;
    for (final m in _menuItems) {
      if (m['id'] == _selectedIndex) return m['label'] as String;
    }
    return "Det App";
  }

  void _selectMenu(int id) {
    setState(() {
      // Сброс слота календаря только при уходе с «Новый заказ».
      // Нельзя чистить в onOrderCreated: ValueKey remount'ит экран
      // посреди диалога «Что дальше?» и ломает переход в Календарь.
      if (_selectedIndex == AppMenuIds.newOrder && id != AppMenuIds.newOrder) {
        _newOrderDate = null;
        _newOrderTime = null;
      }
      _selectedIndex = id;
    });
  }

  void _selectWorkshop(String w) {
    setState(() {
      _selectedIndex = AppMenuIds.workshop;
      _selectedWorkshop = w;
    });
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Выйти из аккаунта?',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Локальные данные на этом устройстве останутся. '
          'Чтобы снова работать с облаком, нужно будет войти.',
          style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Выйти', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await AuthController.instance.logout();
    }
  }

  Future<void> _confirmWipeDatabase() async {
    final pinCtrl = TextEditingController();
    var pinOk = false;
    final cloud = CloudMode.enabled;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            cloud ? 'Очистить доску заказов?' : 'Очистить базу данных?',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: AppColors.danger),
          ),
          content: SizedBox(
            width: AppResponsive.dialogWidth(ctx, desktop: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  cloud
                      ? 'В облаке удалятся все заказы, клиенты и авто. '
                          'Прайс и склад останутся.'
                      : 'Будут удалены заказы, клиенты, оплаты, касса и прочие данные. '
                          'Перед очисткой создастся бэкап. После очистки приложение перезапустится.',
                  style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13, height: 1.35),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'PIN-код',
                    isDense: true,
                  ),
                  onChanged: (v) => setInner(() => pinOk = v.trim() == kDbWipePin),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                disabledBackgroundColor: AppColors.danger.withOpacity(0.25),
              ),
              onPressed: pinOk ? () => Navigator.pop(ctx, true) : null,
              child: Text(
                cloud ? 'Очистить' : 'Очистить',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
    pinCtrl.dispose();
    if (confirmed != true || !mounted) return;

    if (cloud) {
      try {
        final res = await CloudDbBridge.instance.clearBoard(clients: true);
        if (!mounted) return;
        final orders = res['deleted'] ?? res['cleared'] ?? 0;
        final clientsN = res['deleted_clients'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Очищено: заказов $orders, клиентов $clientsN')),
        );
        setState(() => _selectedIndex = AppMenuIds.board);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось очистить доску: $e')),
        );
      }
      return;
    }

    await BackupHelper.forceBackupNow();
    await DatabaseHelper().resetDatabase();
    await _restartApplication();
  }

  /// Desktop: новый процесс. Mobile / fallback: remount UI.
  Future<void> _restartApplication() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        final exe = Platform.resolvedExecutable;
        await Process.start(
          exe,
          const [],
          mode: ProcessStartMode.detached,
          workingDirectory: Directory.current.path,
        );
        exit(0);
      } catch (_) {}
    }
    runApp(DetApp(key: UniqueKey()));
  }

  Widget _buildContent() {
    // При CloudMode данные идут через CloudDbBridge в DatabaseHelper —
    // визуал и экраны те же, что локально.
    if (_selectedIndex == AppMenuIds.workshop) {
      return WorkshopsScreen(selectedWorkshop: _selectedWorkshop, key: ValueKey("ws_$_selectedWorkshop"));
    }
    switch (_selectedIndex) {
      case AppMenuIds.board:
        return const KanbanScreen(key: ValueKey(AppMenuIds.board));
      case AppMenuIds.newOrder:
        final d = _newOrderDate;
        final t = _newOrderTime;
        final key = d != null && t != null
            ? "order_${d.year}-${d.month}-${d.day}_${t.hour}:${t.minute}"
            : "order_default";
        return OrdersScreen(
          key: ValueKey(key),
          initialDate: _newOrderDate,
          initialTime: _newOrderTime,
          onNavigateMenu: (i) => _selectMenu(i),
        );
      case AppMenuIds.calendar:
        final cal = _selectedCalendarDate;
        return CalendarScreen(
          selectedDate: DateTime(cal.year, cal.month, cal.day),
          key: ValueKey("cal_${cal.year}-${cal.month}-${cal.day}"),
          onDateChanged: (date) {
            setState(() {
              _selectedCalendarDate = DateTime(date.year, date.month, date.day);
            });
          },
          onCreateAt: (date, time) {
            setState(() {
              _newOrderDate = date;
              _newOrderTime = time;
              _selectedIndex = AppMenuIds.newOrder;
            });
          },
        );
      case AppMenuIds.clients:
        return const ClientsScreen(key: ValueKey(AppMenuIds.clients));
      case AppMenuIds.cash:
        return const CashScreen(key: ValueKey(AppMenuIds.cash));
      case AppMenuIds.stats:
        return const StatsScreen(key: ValueKey(AppMenuIds.stats));
      case AppMenuIds.staff:
        return const MastersScreen(key: ValueKey(AppMenuIds.staff));
      case AppMenuIds.services:
        return const ServicesScreen(key: ValueKey(AppMenuIds.services));
      case AppMenuIds.inventory:
        return const WarehouseScreen(key: ValueKey(AppMenuIds.inventory));
      case AppMenuIds.preview:
        return const Center(
          key: ValueKey(AppMenuIds.preview),
          child: Text("Превью — в разработке", style: TextStyle(color: AppColors.textMuted)),
        );
      case AppMenuIds.completed:
        return const CompletedOrdersScreen(key: ValueKey(AppMenuIds.completed));
      default:
        return const Center(child: Text("Выберите экран", style: TextStyle(color: AppColors.textMuted)));
    }
  }

  Future<void> _openTraining() async {
    await AppTourLauncher.showMenu(
      context,
      onNavigate: (index) async {
        if (!mounted) return;
        setState(() {
          if (index == AppMenuIds.newOrder) {
            _newOrderDate = null;
            _newOrderTime = null;
          }
          _selectedIndex = index;
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    bool compact = false,
    bool disabled = false,
    String? subtitle,
    Key? key,
  }) {
    final fg = disabled
        ? AppColors.textDim
        : (active ? AppColors.primary : AppColors.textMuted);
    final titleColor = disabled
        ? AppColors.textDim
        : (active ? AppColors.text : AppColors.textMuted);
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 8 : 11),
            decoration: BoxDecoration(
              color: active && !disabled ? AppColors.primarySoft.withOpacity(0.55) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 3,
                  height: 22,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: active && !disabled ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.manrope(
                          color: titleColor,
                          fontSize: compact ? 13.5 : 14.5,
                          fontWeight: active && !disabled ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: GoogleFonts.manrope(
                            color: AppColors.textDim,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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

  Widget _buildBrandHeader({bool compact = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, compact ? 16 : 28, 20, compact ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Det App",
                  style: GoogleFonts.manrope(
                    color: AppColors.text,
                    fontSize: compact ? 20 : 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    height: 1.05,
                  ),
                ),
              ),
              ConnStatusDot(onTap: () => showConnStatusSheet(context)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "Detailing CRM Studio",
            style: GoogleFonts.manrope(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          ListenableBuilder(
            listenable: AuthController.instance,
            builder: (context, _) {
              final u = AuthController.instance.user;
              if (u == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  u.displayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    color: AppColors.textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchTile({required bool showShortcut, VoidCallback? afterTap}) {
    return Padding(
      key: TourKeys.search,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: PulseAnchor(
        active: isPulseActive(_pulseSearch),
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              afterTap?.call();
              await runWithPulseHighlight(
                _pulseSearch,
                () => showDialog(context: context, builder: (context) => const SearchDialog()),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.bg.withOpacity(0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    "Поиск",
                    style: GoogleFonts.manrope(color: AppColors.textMuted, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  if (showShortcut) ...[
                    const Spacer(),
                    Text("Ctrl+K", style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMenuList({
    VoidCallback? afterSelect,
    bool includeQuickCalendar = true,
  }) {
    final items = _visibleMenuItems(context);
    return [
      KeyedSubtree(
        key: TourKeys.workshops,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 4),
            childrenPadding: const EdgeInsets.only(left: 8, bottom: 6),
            leading: const Icon(Icons.build_circle_outlined, color: AppColors.textMuted, size: 20),
            title: Text("Цеха", style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 14.5, fontWeight: FontWeight.w600)),
            iconColor: AppColors.primary,
            collapsedIconColor: AppColors.textMuted,
            children: WORKSHOPS.map((w) {
              final active = _selectedIndex == AppMenuIds.workshop && _selectedWorkshop == w;
              return _navItem(
                icon: Icons.circle,
                label: w,
                active: active,
                compact: true,
                onTap: () {
                  _selectWorkshop(w);
                  afterSelect?.call();
                },
              );
            }).toList(),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Text("МЕНЮ", style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      ),
      if (AppResponsive.isMobile(context) && !_mobileFullPhone)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'Смена на телефоне. Прайс, склад и статистика — на ПК.',
            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11, height: 1.3),
          ),
        ),
      ...items.map((item) {
        final id = item["id"] as int;
        final disabled = item["disabled"] == true || AppMenuIds.disabled.contains(id);
        return _navItem(
          key: TourKeys.menuKeyForIndex(id),
          icon: item["icon"] as IconData,
          label: item["label"] as String,
          subtitle: item["subtitle"] as String?,
          disabled: disabled,
          active: _selectedIndex == id,
          onTap: () {
            _selectMenu(id);
            afterSelect?.call();
          },
        );
      }),
      if (includeQuickCalendar) ...[
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text("БЫСТРАЯ ДАТА", style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        ),
        const SizedBox(height: 6),
        Container(
          key: TourKeys.quickCalendar,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: _buildQuickDatePicker(afterSelect: afterSelect),
        ),
      ],
    ];
  }

  Widget _buildQuickDatePicker({VoidCallback? afterSelect}) {
    final selected = DateTime(
      _selectedCalendarDate.year,
      _selectedCalendarDate.month,
      _selectedCalendarDate.day,
    );
    final first = DateTime(2023);
    final last = DateTime(2030, 12, 31);
    final monthLabel = DateFormat('LLLL yyyy', 'ru').format(selected);
    final daysInMonth = DateTime(selected.year, selected.month + 1, 0).day;
    // Monday-based week: weekday 1=Mon … 7=Sun
    final firstWeekday = DateTime(selected.year, selected.month, 1).weekday; // 1..7
    final leading = firstWeekday - 1;
    final weekdays = const ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];

    void goMonth(int delta) {
      final next = DateTime(selected.year, selected.month + delta, 1);
      if (next.isBefore(DateTime(first.year, first.month, 1)) ||
          next.isAfter(DateTime(last.year, last.month, 1))) {
        return;
      }
      final maxDay = DateTime(next.year, next.month + 1, 0).day;
      final day = selected.day.clamp(1, maxDay);
      setState(() {
        _selectedCalendarDate = DateTime(next.year, next.month, day);
      });
    }

    void pickDay(int day) {
      final date = DateTime(selected.year, selected.month, day);
      setState(() {
        _selectedCalendarDate = date;
        _selectedIndex = AppMenuIds.calendar;
      });
      afterSelect?.call();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => goMonth(-1),
              icon: const Icon(Icons.chevron_left, size: 20, color: AppColors.textMuted),
            ),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  monthLabel,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: GoogleFonts.manrope(
                    color: AppColors.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => goMonth(1),
              icon: const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final w in weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: GoogleFonts.manrope(
                      color: AppColors.textDim,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        for (var row = 0; row < 6; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: Builder(
                    builder: (_) {
                      final index = row * 7 + col;
                      final dayNum = index - leading + 1;
                      if (dayNum < 1 || dayNum > daysInMonth) {
                        return const SizedBox(height: 30);
                      }
                      final isSelected = dayNum == selected.day;
                      final isToday = DateTime.now().year == selected.year &&
                          DateTime.now().month == selected.month &&
                          DateTime.now().day == dayNum;
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => pickDay(dayNum),
                        child: Container(
                          height: 30,
                          margin: const EdgeInsets.all(1),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary
                                : (isToday ? AppColors.primary.withOpacity(0.18) : Colors.transparent),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$dayNum',
                            style: GoogleFonts.manrope(
                              color: isSelected ? Colors.white : AppColors.text,
                              fontWeight: isSelected || isToday ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _openMobileModeSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Режим телефона',
                  style: GoogleFonts.manrope(
                    color: AppColors.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Если есть компьютер — оставьте облегчённый режим. '
                  'Полный телефон нужен, когда работаете только с мобильного.',
                  style: GoogleFonts.manrope(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                _mobileModeSheetTile(
                  title: 'ПК + телефон',
                  subtitle: 'На телефоне только смена. Остальное — на ПК.',
                  selected: !_mobileFullPhone,
                  onTap: () async {
                    await _setMobileFullPhone(false);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
                const SizedBox(height: 8),
                _mobileModeSheetTile(
                  title: 'Полный телефон',
                  subtitle: 'Все разделы на телефоне, если нет ПК.',
                  selected: _mobileFullPhone,
                  onTap: () async {
                    await _setMobileFullPhone(true);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _mobileModeSheetTile({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary.withOpacity(0.45) : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: selected ? AppColors.primary : AppColors.textDim,
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
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.manrope(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooterActions({
    required bool showTraining,
    required bool showWipe,
    bool showMobileMode = false,
    VoidCallback? afterAction,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () async {
                afterAction?.call();
                await _confirmLogout();
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textMuted,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                alignment: Alignment.centerLeft,
              ),
              child: Row(
                children: [
                  const Icon(Icons.logout, size: 18, color: AppColors.textDim),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Выйти',
                      style: GoogleFonts.manrope(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showTraining)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: TourKeys.trainButton,
                onPressed: () {
                  afterAction?.call();
                  _openTraining();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary.withOpacity(0.55)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  alignment: Alignment.centerLeft,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.school_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Обучение',
                        style: GoogleFonts.manrope(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: PulseAnchor(
            active: isPulseActive(_pulseUpdate),
            borderRadius: BorderRadius.circular(AppTheme.radius),
            child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                afterAction?.call();
                await runWithPulseHighlight(_pulseUpdate, () => UpdateDialog.open(context));
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                side: BorderSide(color: AppColors.border.withOpacity(0.9)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                alignment: Alignment.centerLeft,
              ),
              child: Row(
                children: [
                  const Icon(Icons.system_update_alt, size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Обновить',
                      style: GoogleFonts.manrope(
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    AppVersion.label,
                    style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11),
                  ),
                ],
              ),
            ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: PulseAnchor(
            active: isPulseActive(_pulseBackup),
            borderRadius: BorderRadius.circular(AppTheme.radius),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () async {
                  afterAction?.call();
                  await runWithPulseHighlight(_pulseBackup, () async {
                    final path = await BackupHelper.forceBackupNow();
                    await _refreshLastBackup();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          path == null ? 'Не удалось создать бэкап' : 'Бэкап создан',
                          style: GoogleFonts.manrope(),
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  });
                },
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_done_outlined,
                      size: 18,
                      color: _lastBackupAt == null ? AppColors.danger : AppColors.textDim,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _lastBackupAt == null
                            ? 'Бэкап: нет'
                            : 'Бэкап: ${AppDateTime.format(_lastBackupAt)}',
                        style: GoogleFonts.manrope(
                          color: _lastBackupAt == null ? AppColors.danger : AppColors.textDim,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          key: TourKeys.bugReport,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () async {
                    afterAction?.call();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => const BugReportDialog(attachDiagLog: true),
                    );
                    if (ok == true) _refreshOpenBugs();
                  },
                  icon: const Icon(Icons.bug_report_outlined, size: 18, color: AppColors.textDim),
                  label: Text(
                    "Сообщить об ошибке",
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      color: AppColors.textDim,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  ),
                ),
              ),
              Tooltip(
                message: 'Ошибки и правки',
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      onPressed: () async {
                        afterAction?.call();
                        await showDialog<void>(
                          context: context,
                          builder: (context) => const BugReportsListDialog(),
                        );
                        _refreshOpenBugs();
                      },
                      icon: const Icon(Icons.list_alt_outlined, size: 20, color: AppColors.textDim),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    if (_openBugs > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _openBugs > 9 ? '9+' : '$_openBugs',
                            style: GoogleFonts.manrope(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showWipe)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: TextButton(
              onPressed: () {
                afterAction?.call();
                _confirmWipeDatabase();
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textDim,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                alignment: Alignment.centerLeft,
              ),
              child: Text(
                'Очистить БД…',
                style: GoogleFonts.manrope(
                  color: AppColors.textDim.withOpacity(0.75),
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        if (showMobileMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  afterAction?.call();
                  _openMobileModeSheet();
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textDim,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _mobileFullPhone ? 'Режим: полный телефон' : 'Режим: ПК + телефон',
                  style: GoogleFonts.manrope(
                    color: AppColors.textDim.withOpacity(0.45),
                    fontWeight: FontWeight.w500,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 268,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.borderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBrandHeader(),
          _buildSearchTile(showShortcut: true),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _buildMenuList(),
            ),
          ),
          _buildFooterActions(showTraining: true, showWipe: true),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBrandHeader(compact: true),
            _buildSearchTile(
              showShortcut: false,
              afterTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _buildMenuList(
                  afterSelect: () => Navigator.of(context).pop(),
                  includeQuickCalendar: false,
                ),
              ),
            ),
            _buildFooterActions(
              showTraining: true,
              showWipe: false,
              showMobileMode: true,
              afterAction: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedContent() {
    return MenuBackgrounds.buildLayer(
      selectedIndex: _selectedIndex,
      workshop: _selectedIndex == AppMenuIds.workshop ? _selectedWorkshop : null,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: KeyedSubtree(
          key: ValueKey<Object>(
            _selectedIndex == AppMenuIds.workshop
                ? "${AppMenuIds.workshop}_$_selectedWorkshop"
                : _selectedIndex == AppMenuIds.calendar
                    ? "${AppMenuIds.calendar}_${_selectedCalendarDate.day}"
                    : _selectedIndex,
          ),
          child: _buildContent(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = AppResponsive.isMobile(context);

    if (mobile) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.text,
          elevation: 0,
          title: Text(
            _currentTitle,
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          actions: [
            ConnStatusDot(onTap: () => showConnStatusSheet(context)),
            IconButton(
              tooltip: 'Поиск',
              onPressed: () => showDialog(context: context, builder: (_) => const SearchDialog()),
              icon: const Icon(Icons.search, color: AppColors.primary),
            ),
          ],
        ),
        drawer: _buildDrawer(),
        body: SafeArea(
          top: false,
          child: _buildAnimatedContent(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(child: _buildAnimatedContent()),
        ],
      ),
    );
  }
}
