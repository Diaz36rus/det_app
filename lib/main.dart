import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app_theme.dart';
import 'app_tour.dart';
import 'backup_helper.dart';
import 'bug_report_dialog.dart';
import 'tour_keys.dart';
import 'calculator_screen.dart';
import 'calendar_screen.dart';
import 'cash_screen.dart';
import 'clients_screen.dart';
import 'completed_orders_screen.dart';
import 'database.dart';
import 'dev_guard.dart';
import 'inventory_screen.dart';
import 'kanban_screen.dart';
import 'masters_screen.dart';
import 'orders_screen.dart';
import 'search_dialog.dart';
import 'stats_screen.dart';
import 'workshops_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Шрифты из google_fonts/ в assets — без скачивания на рабочем ПК офлайн.
  GoogleFonts.config.allowRuntimeFetching = false;
  await initializeDateFormatting('ru');
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  await DatabaseHelper().initDefaultData();
  await BackupHelper.runDailyBackup();
  runApp(const DetApp());
}

class DetApp extends StatelessWidget {
  const DetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      theme: AppTheme.build(),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _selectedCalendarDate = DateTime.now();
  int _selectedIndex = 0;
  String _selectedWorkshop = WORKSHOPS.first;
  DateTime? _newOrderDate;
  TimeOfDay? _newOrderTime;
  int _openBugs = 0;

  @override
  void initState() {
    super.initState();
    _refreshOpenBugs();
  }

  Future<void> _refreshOpenBugs() async {
    final n = await DatabaseHelper().countOpenBugReports();
    if (!mounted) return;
    setState(() => _openBugs = n);
  }

  Future<void> _confirmWipeDatabase() async {
    final pinCtrl = TextEditingController();
    var pinOk = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Очистить базу данных?',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: AppColors.danger),
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Будут удалены заказы, клиенты, оплаты, касса и прочие данные. '
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
              child: Text('Очистить', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    pinCtrl.dispose();
    if (confirmed != true || !mounted) return;

    await BackupHelper.forceBackupNow();
    await DatabaseHelper().resetDatabase();
    await _restartApplication();
  }

  /// Полный перезапуск процесса (Windows/desktop). Если не удалось — remount UI.
  Future<void> _restartApplication() async {
    try {
      final exe = Platform.resolvedExecutable;
      await Process.start(
        exe,
        const [],
        mode: ProcessStartMode.detached,
        workingDirectory: Directory.current.path,
      );
      exit(0);
    } catch (_) {
      runApp(DetApp(key: UniqueKey()));
    }
  }

  final List<Map<String, dynamic>> _menuItems = [
    {"icon": Icons.dashboard_outlined, "label": "Доска заказов"},
    {"icon": Icons.add_shopping_cart_outlined, "label": "Новый заказ"},
    {"icon": Icons.calendar_month_outlined, "label": "Календарь"},
    {"icon": Icons.people_outline, "label": "Клиенты"},
    {"icon": Icons.account_balance_wallet_outlined, "label": "Касса"},
    {"icon": Icons.insights_outlined, "label": "Статистика"},
    {"icon": Icons.engineering_outlined, "label": "Сотрудники"},
    {"icon": Icons.inventory_2_outlined, "label": "Услуги и Склад"},
    {"icon": Icons.calculate_outlined, "label": "Калькулятор"},
    {"icon": Icons.task_alt_outlined, "label": "Завершённые"},
  ];

  Widget _buildContent() {
    if (_selectedIndex == 100) {
      return WorkshopsScreen(selectedWorkshop: _selectedWorkshop, key: ValueKey("ws_$_selectedWorkshop"));
    }
    switch (_selectedIndex) {
      case 0:
        return const KanbanScreen(key: ValueKey(0));
      case 1:
        final d = _newOrderDate;
        final t = _newOrderTime;
        final key = d != null && t != null
            ? "order_${d.year}-${d.month}-${d.day}_${t.hour}:${t.minute}"
            : "order_default";
        return OrdersScreen(
          key: ValueKey(key),
          initialDate: _newOrderDate,
          initialTime: _newOrderTime,
        );
      case 2:
        final cal = _selectedCalendarDate;
        return CalendarScreen(
          selectedDate: DateTime(cal.year, cal.month, cal.day),
          key: ValueKey("cal_${cal.year}-${cal.month}-${cal.day}"),
          onCreateAt: (date, time) {
            setState(() {
              _newOrderDate = date;
              _newOrderTime = time;
              _selectedIndex = 1;
            });
          },
        );
      case 3:
        return const ClientsScreen(key: ValueKey(3));
      case 4:
        return const CashScreen(key: ValueKey(4));
      case 5:
        return const StatsScreen(key: ValueKey(5));
      case 6:
        return const MastersScreen(key: ValueKey(6));
      case 7:
        return const InventoryScreen(key: ValueKey(7));
      case 8:
        return const CalculatorScreen(key: ValueKey(8));
      case 9:
        return const CompletedOrdersScreen(key: ValueKey(9));
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
          if (index == 1) {
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
    Key? key,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 8 : 11),
            decoration: BoxDecoration(
              color: active ? AppColors.primarySoft : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: active ? AppColors.primary.withOpacity(0.45) : Colors.transparent),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 3,
                  height: 22,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Icon(icon, size: 20, color: active ? AppColors.primary : AppColors.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.manrope(
                      color: active ? AppColors.text : AppColors.textMuted,
                      fontSize: compact ? 13.5 : 14.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Row(
        children: [
          // --- Боковое меню ---
          Container(
            width: 268,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(right: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Det App",
                        style: GoogleFonts.manrope(
                          color: AppColors.text,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          height: 1.05,
                        ),
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
                    ],
                  ),
                ),
                Padding(
                  key: TourKeys.search,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => showDialog(context: context, builder: (context) => const SearchDialog()),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary.withOpacity(0.35)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search, color: AppColors.primary, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              "Поиск",
                              style: GoogleFonts.manrope(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.bg,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Text("Ctrl+K", style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
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
                              final active = _selectedIndex == 100 && _selectedWorkshop == w;
                              return _navItem(
                                icon: Icons.circle,
                                label: w,
                                active: active,
                                compact: true,
                                onTap: () => setState(() {
                                  _selectedIndex = 100;
                                  _selectedWorkshop = w;
                                }),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        child: Text("МЕНЮ", style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                      ),
                      ..._menuItems.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        return _navItem(
                          key: TourKeys.menuKeyForIndex(index),
                          icon: item["icon"] as IconData,
                          label: item["label"] as String,
                          active: _selectedIndex == index,
                          onTap: () => setState(() {
                            if (index == 1) {
                              _newOrderDate = null;
                              _newOrderTime = null;
                            }
                            _selectedIndex = index;
                          }),
                        );
                      }),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text("БЫСТРАЯ ДАТА", style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        key: TourKeys.quickCalendar,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.dark(primary: AppColors.primary),
                          ),
                          child: CalendarDatePicker(
                            initialDate: DateTime(
                              _selectedCalendarDate.year,
                              _selectedCalendarDate.month,
                              _selectedCalendarDate.day,
                            ),
                            firstDate: DateTime(2023),
                            lastDate: DateTime(2030),
                            onDateChanged: (date) {
                              final day = DateTime(date.year, date.month, date.day);
                              setState(() {
                                _selectedCalendarDate = day;
                                _selectedIndex = 2;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: TourKeys.trainButton,
                      onPressed: _openTraining,
                      icon: const Icon(Icons.school_outlined, size: 18, color: AppColors.primary),
                      label: Text(
                        'Обучение',
                        style: GoogleFonts.manrope(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary.withOpacity(0.55)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (context) => const BugReportDialog(),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _confirmWipeDatabase,
                      icon: const Icon(Icons.delete_forever_outlined, size: 18, color: AppColors.danger),
                      label: Text(
                        'Очистить БД',
                        style: GoogleFonts.manrope(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: BorderSide(color: AppColors.danger.withOpacity(0.65)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // --- Контент ---
          Expanded(
            child: ColoredBox(
              color: AppColors.bg,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: KeyedSubtree(
                  key: ValueKey<Object>(_selectedIndex == 100 ? "100_$_selectedWorkshop" : _selectedIndex == 2 ? "2_${_selectedCalendarDate.day}" : _selectedIndex),
                  child: _buildContent(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
