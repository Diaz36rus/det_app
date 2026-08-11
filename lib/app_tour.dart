import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'database.dart';
import 'order_details_dialog.dart';
import 'tour_keys.dart';

/// Считает PopupRoute (диалоги) на корневом навигаторе.
/// Нужен в [MaterialApp.navigatorObservers], чтобы обучение пряталось,
/// пока пользователь работает с открытым окном (поиск, баг-репорт и т.д.).
class TourNavBridge extends NavigatorObserver {
  TourNavBridge._();
  static final TourNavBridge instance = TourNavBridge._();

  final ValueNotifier<int> popupDepth = ValueNotifier<int>(0);

  void _delta(Route<dynamic> route, int d) {
    if (route is PopupRoute) {
      popupDepth.value = (popupDepth.value + d).clamp(0, 99);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _delta(route, 1);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _delta(route, -1);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _delta(route, -1);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _delta(oldRoute, -1);
    if (newRoute != null) _delta(newRoute, 1);
  }
}

class AppTourStep {
  final String title;
  final String body;
  final GlobalKey? targetKey;
  /// Индекс пункта меню HomeScreen (null = не переключать).
  final int? menuIndex;
  /// Перед шагом закрыть открытую карточку заказа (и подобные dialog).
  final bool dismissOrderDetails;
  /// Нужен хотя бы один заказ в БД (иначе шаг бессмыслен / ломает сценарий).
  final bool requireOrders;

  const AppTourStep({
    required this.title,
    required this.body,
    this.targetKey,
    this.menuIndex,
    this.dismissOrderDetails = false,
    this.requireOrders = false,
  });
}

class AppTour {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<AppTourStep> steps;

  const AppTour({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.steps,
  });
}

/// Каталог туров обучения.
class AppTours {
  static final List<AppTour> all = [
    AppTour(
      id: 'ui',
      title: 'Знакомство с интерфейсом',
      subtitle: 'Где что лежит — за 2 минуты',
      icon: Icons.map_outlined,
      steps: [
        AppTourStep(
          title: 'Давайте осмотримся',
          body: 'Это короткая прогулка по приложению. Подсветка покажет, о чём речь — '
              'туда можно нажимать и вводить данные. '
              '«Пропустить» — только этот шаг, «Закончить» — выйти из обучения.',
        ),
        AppTourStep(
          title: 'Глобальный поиск',
          body: 'Это одна из сильных сторон Det App: один поиск по всему приложению. '
              'Нажмите сюда и попробуйте: окно поиска откроется поверх обучения — '
              'можно ввести имя, телефон, номер, VIN или заказ, посмотреть результат и закрыть. '
              'Потом продолжайте тур кнопкой «Далее».',
          targetKey: TourKeys.search,
        ),
        AppTourStep(
          title: 'Рабочие зоны (цеха)',
          body: 'Здесь мастер заходит «в свой цех»: мойка, полировка, оклейка и т.д. '
              'Видит только свои задачи, без лишнего.',
          targetKey: TourKeys.workshops,
        ),
        // В туре «интерфейс» не переключаем тяжёлые экраны — только подсветка меню.
        AppTourStep(
          title: 'Доска заказов',
          body: 'Главный экран дня. Все машины в работе — по этапам, как на стене со стикерами. '
              'Отсюда открывают любой заказ.',
          targetKey: TourKeys.menuBoard,
          menuIndex: 0,
        ),
        AppTourStep(
          title: 'Новый заказ',
          body: 'Сюда заходите, когда клиент приехал или записался. '
              'Заполните данные, выберите услуги — и заказ появится на доске.',
          targetKey: TourKeys.menuNewOrder,
          menuIndex: 0,
        ),
        AppTourStep(
          title: 'Календарь дня',
          body: 'Здесь видно загрузку студии по времени. Есть две вкладки: '
              '«Общая запись» — машина целиком: когда приехала и когда примерно отдаём. '
              'Удобно смотреть день и ставить новую запись. '
              '«Детальное время» — уже по работам и цехам: когда мойка, полировка, оклейка. '
              'Нужно, чтобы не пересечь мастеров и понять реальную очередь.',
          targetKey: TourKeys.menuCalendar,
          menuIndex: 0,
        ),
        AppTourStep(
          title: 'Клиенты и их история',
          body: 'Телефонная книга студии: кто был, какие авто, какой класс. '
              'Откройте клиента — увидите историю заказов: что уже делали раньше. '
              'Так проще предложить повторный сервис и не спрашивать всё с нуля.',
          targetKey: TourKeys.menuClients,
          menuIndex: 0,
        ),
        AppTourStep(
          title: 'Касса',
          body: 'Все деньги: что приняли с клиентов и на что потратили. '
              'Подробнее — в отдельном обучении «Касса и смена».',
          targetKey: TourKeys.menuCash,
          menuIndex: 0,
        ),
        AppTourStep(
          title: 'Остальное меню',
          body: 'На телефоне в режиме «ПК + телефон» меню укорочено: смена здесь, '
              'а статистика, сотрудники, услуги и склад — на компьютере. '
              'Если ПК нет — в меню выберите «Полный телефон». '
              'Для первого дня достаточно доски, нового заказа и кассы.',
          targetKey: TourKeys.menuCompleted,
          menuIndex: 0,
        ),
        AppTourStep(
          title: 'Быстрый выбор дня',
          body: 'Нажмите дату здесь — сразу откроется календарь на этот день. '
              'Удобно, не заходя в меню.',
          targetKey: TourKeys.quickCalendar,
          menuIndex: 0,
        ),
        AppTourStep(
          title: 'Сообщить об ошибке',
          body: 'Нашли сбой или странное поведение — нажмите «Сообщить об ошибке». '
              'Кратко укажите: где случилось, что делали и в чём ошибка. Сообщение сохранится в базе. '
              'Иконка списка справа — все ваши репорты: открытые, исправленные, с пометкой. '
              'Красный значок — сколько ещё не закрыто. Так тестировщик и разработчик не теряют баги.',
          targetKey: TourKeys.bugReport,
          menuIndex: 0,
        ),
        AppTourStep(
          title: 'Можно начинать работу',
          body: 'Дальше лучше пройти «Создание заказа от и до» — это главный сценарий смены.',
          targetKey: TourKeys.trainButton,
          menuIndex: 0,
        ),
      ],
    ),
    AppTour(
      id: 'order',
      title: 'Создание заказа от и до',
      subtitle: 'Как принять машину и не упустить детали',
      icon: Icons.add_shopping_cart_outlined,
      steps: [
        AppTourStep(
          title: 'Сценарий приёмщика',
          body: 'Сейчас пройдём путь: клиент → когда забрать → что делаем → сохранить → '
              'увидеть на доске → принять оплату.',
          menuIndex: 1,
        ),
        AppTourStep(
          title: 'Кто приехал',
          body: 'Введите телефон с +7. Если человек уже был у вас — имя и машины подставятся сами. '
              'Укажите авто, номер и класс — от класса зависят цены.',
          targetKey: TourKeys.orderClient,
          menuIndex: 1,
        ),
        AppTourStep(
          title: 'Когда принять и когда отдать',
          body: 'Поставьте дату и время приёма и примерной выдачи. '
              'Так заказ попадёт в календарь, и клиенту проще назвать срок.',
          targetKey: TourKeys.orderSchedule,
          menuIndex: 1,
        ),
        AppTourStep(
          title: 'Что делаем с машиной',
          body: 'Нажмите картинку услуги (мойка, полировка…). '
              'Отметьте нужные позиции — они появятся внизу в списке. '
              'Для оклейки откроется пакет зон: отметьте детали и сумму пакета.',
          targetKey: TourKeys.orderGallery,
          menuIndex: 1,
        ),
        AppTourStep(
          title: 'Проверьте список и сохраните',
          body: 'Внизу — корзина и кнопка «Создать заказ» (она в подсветке — нажмите её). '
              'Нужны телефон, имя, авто и хотя бы одна услуга — без услуг кнопка неактивна. '
              'После сохранения можно сразу перейти на доску или в календарь.',
          targetKey: TourKeys.orderCart,
          menuIndex: 1,
        ),
        AppTourStep(
          title: 'Заказ на доске',
          body: 'Вот он среди других. Нажмите на карточку — откроется полная информация: '
              'статус, работы, оплата.',
          targetKey: TourKeys.kanbanArea,
          menuIndex: 0,
          requireOrders: true,
        ),
        AppTourStep(
          title: 'Как принять деньги',
          body: 'Откройте карточку заказа с доски. Внизу: сколько должен клиент и кнопка оплаты. '
              'Выберите способ (нал / карта / перевод) и подтвердите.',
          menuIndex: 0,
          requireOrders: true,
        ),
        AppTourStep(
          title: 'Деньги в кассе',
          body: 'Зайдите в «Касса» — оплата уже должна быть видна. '
              'Так вы всегда видите, сколько пришло за день.',
          targetKey: TourKeys.menuCash,
          menuIndex: 4,
        ),
      ],
    ),
    AppTour(
      id: 'cash',
      title: 'Касса и смена',
      subtitle: 'Несколько касс, смена и журнал',
      icon: Icons.account_balance_wallet_outlined,
      steps: [
        AppTourStep(
          title: 'Зачем касса',
          body: 'Здесь видно: сколько взяли с клиентов и сколько потратили '
              '(химия, зарплата, аренда…). Не только «в голове» и не только в блокноте.',
          menuIndex: 4,
        ),
        AppTourStep(
          title: 'Цифры сверху',
          body: 'Полоска сверху — итоги за день (или неделю/месяц). '
              'Нал, карта, перевод, по счету, расходы. «Долги» — кто ещё не расплатился.',
          targetKey: TourKeys.cashKpi,
          menuIndex: 4,
        ),
        AppTourStep(
          title: 'Несколько касс в смене',
          body: 'Утром откройте смену и укажите остатки по кассам: Основная, Терминал, Переводы, счёт. '
              'Можно добавить свою кассу. Вечером закройте и сверьте факт с ожиданием.',
          targetKey: TourKeys.cashShift,
          menuIndex: 4,
        ),
        AppTourStep(
          title: 'Быстрые кнопки расходов и приходов',
          body: 'Красные — потратили, зелёные — получили не из заказа (например, продали химию). '
              'Нажали — почти всё уже заполнено, осталось вписать сумму и выбрать кассу.',
          targetKey: TourKeys.cashTemplates,
          menuIndex: 4,
        ),
        AppTourStep(
          title: 'История операций',
          body: 'Ниже — лента всего, что произошло. Можно оставить только оплаты или только расходы. '
              'Нажали на оплату заказа — откроется сам заказ.',
          targetKey: TourKeys.cashJournal,
          menuIndex: 4,
        ),
        AppTourStep(
          title: 'Попробуйте сами',
          body: 'Откройте смену → сделайте один тестовый расход (например «Кофе / еда») → '
              'закройте смену. Так привыкнете за одну минуту.',
          menuIndex: 4,
        ),
      ],
    ),
    AppTour(
      id: 'order_deep',
      title: 'Карточка заказа подробно',
      subtitle: 'Что делать с заказом, пока машина в работе',
      icon: Icons.fact_check_outlined,
      steps: [
        AppTourStep(
          title: 'Это «паспорт» заказа',
          body: 'Сейчас открыт пример. Сюда заходят, чтобы двигать статус, назначать мастеров, '
              'принимать оплату и писать заметки.',
          targetKey: TourKeys.orderDetailsHeader,
        ),
        AppTourStep(
          title: 'Список работ',
          body: 'Слева — что заказано. Можно отметить «сделано», поставить время и выбрать мастера. '
              'Для оклейки зоны могут быть собраны в один пакет.',
          targetKey: TourKeys.orderDetailsWorks,
        ),
        AppTourStep(
          title: 'Когда начать и когда закончить',
          body: 'Здесь общее время по заказу и техмойка. Это помогает не забыть машину в графике.',
          targetKey: TourKeys.orderDetailsSchedule,
        ),
        AppTourStep(
          title: 'Переписка по заказу',
          body: 'Можно оставить заметку для себя, для клиента или для цеха. '
              'Справа — история: кто что написал и что менялось.',
          targetKey: TourKeys.orderDetailsNotes,
        ),
        AppTourStep(
          title: 'Оплата и документы',
          body: 'Внизу — сколько должны и сколько уже внесли. Печать заказ-наряда — иконка принтера в шапке. '
              'Когда всё готово — доводите статус до выдачи.',
          targetKey: TourKeys.orderDetailsPayment,
        ),
        AppTourStep(
          title: 'Экран для мастера',
          body: 'Карточку закрыли. Откройте «Цеха»: мастер видит только свою зону, без всей админки.',
          targetKey: TourKeys.workshops,
          dismissOrderDetails: true,
        ),
      ],
    ),
  ];

  static AppTour? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}

typedef TourNavigate = Future<void> Function(int menuIndex);

/// Выбор тура + запуск.
class AppTourLauncher {
  static Future<void> showMenu(
    BuildContext context, {
    required TourNavigate onNavigate,
  }) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Обучение', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Короткие сценарии по основным экранам — от меню до кассы и карточки заказа.',
                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, height: 1.35),
                ),
              ),
              for (final t in AppTours.all)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(t.icon, color: AppColors.primary),
                  title: Text(t.title, style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: Text(t.subtitle, style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, t.id),
                ),
              const Divider(color: AppColors.border),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bolt_outlined, color: Color(0xFFF59E0B)),
                title: Text('Быстрый старт', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: Text(
                  'Интерфейс → затем создание заказа',
                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'quick'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
        ],
      ),
    );

    if (choice == null || !context.mounted) return;
    if (choice == 'quick') {
      final ui = AppTours.byId('ui');
      final order = AppTours.byId('order');
      if (ui != null) {
        final ok = await runTour(context, ui, onNavigate: onNavigate);
        if (!ok || !context.mounted) return;
      }
      if (order != null && context.mounted) {
        await runTour(context, order, onNavigate: onNavigate);
      }
      return;
    }
    if (choice == 'order_deep') {
      await _startOrderDeepTour(context, onNavigate: onNavigate);
      return;
    }
    final tour = AppTours.byId(choice);
    if (tour != null) {
      await runTour(context, tour, onNavigate: onNavigate);
    }
  }

  /// Гейт: нужен хотя бы один активный заказ; иначе предложить создать.
  static Future<void> _startOrderDeepTour(
    BuildContext context, {
    required TourNavigate onNavigate,
  }) async {
    final orders = await DatabaseHelper().getAllOrders();
    if (!context.mounted) return;

    if (orders.isEmpty) {
      final goCreate = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Нужен заказ-пример',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Создайте заказ, и на его примере мы изучим детали.',
            style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 14, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Позже'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Создать заказ', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (goCreate == true && context.mounted) {
        await onNavigate(1);
      }
      return;
    }

    await onNavigate(0);
    await Future<void>.delayed(const Duration(milliseconds: 380));
    if (!context.mounted) return;

    final order = Map<String, dynamic>.from(orders.first);
    // Не ждём закрытия — тур идёт поверх открытой карточки.
    // ignore: unawaited_futures
    OrderDetailsDialog.open(context, order);
    // Ждём, пока карточка загрузится и ключи появятся в дереве.
    await _waitForTourTarget(TourKeys.orderDetailsHeader);
    if (!context.mounted) return;

    final tour = AppTours.byId('order_deep');
    if (tour != null) {
      await runTour(context, tour, onNavigate: onNavigate);
    }
  }

  static Future<void> _waitForTourTarget(GlobalKey key, {int tries = 40}) async {
    for (var i = 0; i < tries; i++) {
      final ctx = key.currentContext;
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize && box.size.width > 0) {
          // Дать анимации открытия дорисоваться
          await Future<void>.delayed(const Duration(milliseconds: 120));
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  static Future<void> _dismissOrderDetailsIfOpen(BuildContext context) async {
    final odCtx = TourKeys.orderDetailsHeader.currentContext;
    if (odCtx == null) return;
    // PopScope(canPop: false) → maybePop запускает _closeDialog с анимацией.
    await Navigator.of(odCtx, rootNavigator: true).maybePop();
    await _waitForTourTargetGone(TourKeys.orderDetailsHeader);
    if (context.mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  static Future<void> _waitForTourTargetGone(GlobalKey key, {int tries = 25}) async {
    for (var i = 0; i < tries; i++) {
      if (key.currentContext == null) return;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  /// Показ шага через Overlay навигатора (не rootOverlay и не ModalRoute).
  /// Так диалоги (поиск, баг-репорт и т.д.), открытые во время шага, оказываются
  /// выше тура — с ними можно полноценно работать, затем закрыть и продолжить обучение.
  static Future<_TourAction?> _presentStep(
    BuildContext context, {
    required String tourTitle,
    required int stepIndex,
    required int stepCount,
    required AppTourStep step,
  }) {
    final completer = Completer<_TourAction?>();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _TourOverlay(
        tourTitle: tourTitle,
        stepIndex: stepIndex,
        stepCount: stepCount,
        step: step,
        onAction: (action) {
          entry.remove();
          if (!completer.isCompleted) completer.complete(action);
        },
      ),
    );
    // Navigator.overlay: последующие showDialog / showGeneralDialog лягут сверху.
    // rootOverlay: true клал тур поверх всего — поиск открывался «под затемнением».
    final navOverlay = Navigator.of(context, rootNavigator: true).overlay;
    (navOverlay ?? Overlay.of(context)).insert(entry);
    return completer.future;
  }

  /// Возвращает false, если пользователь прервал тур.
  static Future<bool> runTour(
    BuildContext context,
    AppTour tour, {
    required TourNavigate onNavigate,
  }) async {
    // Если диалогов нет, а счётчик «залип» — выровнять.
    final nav = Navigator.of(context, rootNavigator: true);
    if (!nav.canPop() && TourNavBridge.instance.popupDepth.value != 0) {
      TourNavBridge.instance.popupDepth.value = 0;
    }

    for (var i = 0; i < tour.steps.length; i++) {
      if (!context.mounted) return false;
      final step = tour.steps[i];

      if (step.requireOrders) {
        final orders = await DatabaseHelper().getAllOrders();
        if (!context.mounted) return false;
        if (orders.isEmpty) {
          await _warnNeedCreateOrder(context);
          if (!context.mounted) return false;
          // Вернуться к шагу с корзиной / созданием заказа.
          final back = tour.steps.indexWhere((s) => s.targetKey == TourKeys.orderCart);
          i = back >= 0 ? back - 1 : i - 2;
          if (i < -1) i = -1;
          continue;
        }
      }

      if (step.dismissOrderDetails) {
        await _dismissOrderDetailsIfOpen(context);
        if (!context.mounted) return false;
      }
      if (step.menuIndex != null) {
        await onNavigate(step.menuIndex!);
        await Future<void>.delayed(const Duration(milliseconds: 380));
      }
      if (step.targetKey != null) {
        await _waitForTourTarget(step.targetKey!, tries: 20);
      }
      if (!context.mounted) return false;

      final action = await _presentStep(
        context,
        tourTitle: tour.title,
        stepIndex: i,
        stepCount: tour.steps.length,
        step: step,
      );
      if (action == null || action == _TourAction.finish) return false;
      // next и skip — следующий шаг
      if (action == _TourAction.next || action == _TourAction.skip) continue;
    }
    return true;
  }

  static Future<void> _warnNeedCreateOrder(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Сначала создайте заказ',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Заполните клиента и услуги, затем нажмите «Создать заказ» в подсвеченной зоне. '
          'После этого можно продолжить обучение.',
          style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 14, height: 1.35),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Понятно', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

enum _TourAction { next, skip, finish }

class _TourOverlay extends StatefulWidget {
  final String tourTitle;
  final int stepIndex;
  final int stepCount;
  final AppTourStep step;
  final ValueChanged<_TourAction> onAction;

  const _TourOverlay({
    required this.tourTitle,
    required this.stepIndex,
    required this.stepCount,
    required this.step,
    required this.onAction,
  });

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _dimColor = Color(0xB8000000); // ~72% black
  /// Зазор между карточкой и целью — чтобы была видна дуга стрелки.
  static const _gap = 64.0;
  static const _holeRadius = 12.0;

  final GlobalKey _cardKey = GlobalKey();

  Rect? _hole;
  Offset _cardPos = Offset.zero;
  double _cardWidth = 340;
  Size _cardSize = const Size(340, 220);
  late final AnimationController _arrowCtrl;
  bool _refineScheduled = false;
  /// Глубина PopupRoute на момент показа шага (для order_deep уже может быть 1).
  late int _popupDepthAtOpen;

  bool get _pausedForDialog =>
      TourNavBridge.instance.popupDepth.value > _popupDepthAtOpen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _popupDepthAtOpen = TourNavBridge.instance.popupDepth.value;
    TourNavBridge.instance.popupDepth.addListener(_onPopupDepth);
    _arrowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateLayout(restartArrow: true));
  }

  void _onPopupDepth() {
    if (!mounted) return;
    setState(() {});
    // После закрытия диалога — перемерить цель (layout мог сдвинуться).
    if (!_pausedForDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateLayout(restartArrow: false);
      });
    }
  }

  @override
  void dispose() {
    TourNavBridge.instance.popupDepth.removeListener(_onPopupDepth);
    WidgetsBinding.instance.removeObserver(this);
    _arrowCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateLayout(restartArrow: false);
    });
  }

  @override
  void didUpdateWidget(covariant _TourOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stepIndex != widget.stepIndex ||
        oldWidget.step.title != widget.step.title ||
        oldWidget.step.targetKey != widget.step.targetKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateLayout(restartArrow: true);
      });
    }
  }

  Rect? _measureHole() {
    final key = widget.step.targetKey;
    if (key == null) return null;
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final offset = box.localToGlobal(Offset.zero);
    return (offset & box.size).inflate(6);
  }

  Offset _placeCard({
    required Size screen,
    required EdgeInsets padding,
    required double cardW,
    required double cardH,
    required Rect? hole,
  }) {
    final minL = padding.left + 16;
    final minT = padding.top + 16;
    final maxR = screen.width - padding.right - 16;
    final maxB = screen.height - padding.bottom - 16;
    final maxW = math.max(0.0, maxR - minL);
    final maxH = math.max(0.0, maxB - minT);
    final w = math.min(cardW, maxW);
    final h = math.min(cardH, maxH);

    Offset clampPos(double left, double top) {
      final l = left.clamp(minL, math.max(minL, maxR - w));
      final t = top.clamp(minT, math.max(minT, maxB - h));
      return Offset(l.toDouble(), t.toDouble());
    }

    if (hole == null) {
      return clampPos((screen.width - w) / 2, screen.height * 0.32);
    }

    // Огромная цель (доска на весь экран): карточку в правый верх — иначе уезжает
    // вниз за край и кнопки попадают в «дырку» hit-test.
    final screenArea = screen.width * screen.height;
    final holeArea = hole.width * hole.height;
    if (holeArea > screenArea * 0.40) {
      return clampPos(maxR - w, minT + 12);
    }

    final spaceRight = maxR - hole.right - _gap;
    final spaceLeft = hole.left - minL - _gap;
    final spaceBelow = maxB - hole.bottom - _gap;
    final spaceAbove = hole.top - minT - _gap;

    final options = <({Offset pos, double score, Rect rect})>[];

    void addOption(Offset raw, double freeSpace) {
      final pos = clampPos(raw.dx, raw.dy);
      final rect = Rect.fromLTWH(pos.dx, pos.dy, w, h);
      // Реальный зазор после clamp — штрафуем, если карточка «прилипла» к цели
      final clearGap = _clearGap(rect, hole);
      final overlap = rect.overlaps(hole.inflate(8)) ? 10000.0 : 0.0;
      final gapPenalty = clearGap < _gap * 0.75 ? (_gap - clearGap) * 40 : 0.0;
      options.add((
        pos: pos,
        score: freeSpace + clearGap * 2 - overlap - gapPenalty,
        rect: rect,
      ));
    }

    if (spaceRight >= w * 0.55) {
      addOption(Offset(hole.right + _gap, hole.center.dy - h / 2), spaceRight);
    }
    if (spaceLeft >= w * 0.55) {
      addOption(Offset(hole.left - _gap - w, hole.center.dy - h / 2), spaceLeft);
    }
    if (spaceBelow >= h * 0.55) {
      addOption(Offset(hole.center.dx - w / 2, hole.bottom + _gap), spaceBelow);
    }
    if (spaceAbove >= h * 0.55) {
      addOption(Offset(hole.center.dx - w / 2, hole.top - _gap - h), spaceAbove);
    }

    if (options.isEmpty) {
      // Нет места сбоку — правый верх, не низ экрана
      return clampPos(maxR - w, minT + 12);
    }

    options.sort((a, b) => b.score.compareTo(a.score));
    return options.first.pos;
  }

  void _updateLayout({required bool restartArrow}) {
    if (!mounted) return;
    final mq = MediaQuery.of(context);
    final screen = mq.size;
    final padding = mq.padding;
    final hole = _measureHole();
    final cardW = math.min(340.0, screen.width - 48);

    var cardH = _cardSize.height;
    final cardCtx = _cardKey.currentContext;
    if (cardCtx != null) {
      final box = cardCtx.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        cardH = box.size.height;
      }
    }

    final pos = _placeCard(
      screen: screen,
      padding: padding,
      cardW: cardW,
      cardH: cardH,
      hole: hole,
    );

    setState(() {
      _hole = hole;
      _cardWidth = cardW;
      _cardPos = pos;
      _cardSize = Size(cardW, cardH);
    });

    if (hole != null && restartArrow) {
      _arrowCtrl.forward(from: 0);
    } else if (hole == null) {
      _arrowCtrl.value = 0;
    }

    if (!_refineScheduled) {
      _refineScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refineScheduled = false;
        if (!mounted) return;
        final ctx = _cardKey.currentContext;
        if (ctx == null) return;
        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final nextHole = _measureHole();
        final hChanged = (box.size.height - _cardSize.height).abs() > 1;
        final holeChanged = nextHole != _hole &&
            (nextHole == null ||
                _hole == null ||
                (nextHole.left - _hole!.left).abs() > 1 ||
                (nextHole.top - _hole!.top).abs() > 1 ||
                (nextHole.width - _hole!.width).abs() > 1 ||
                (nextHole.height - _hole!.height).abs() > 1);
        if (hChanged || holeChanged) {
          _updateLayout(restartArrow: false);
        }
      });
    }
  }

  List<Widget> _dimPanels(Size screen, Rect? hole) {
    if (hole == null) {
      return [
        Positioned.fill(
          child: ColoredBox(color: _dimColor),
        ),
      ];
    }

    final h = hole;
    final panels = <Widget>[];

    // Top
    if (h.top > 0) {
      panels.add(Positioned(
        left: 0,
        top: 0,
        width: screen.width,
        height: h.top,
        child: const ColoredBox(color: _dimColor),
      ));
    }
    // Bottom
    if (h.bottom < screen.height) {
      panels.add(Positioned(
        left: 0,
        top: h.bottom,
        width: screen.width,
        height: screen.height - h.bottom,
        child: const ColoredBox(color: _dimColor),
      ));
    }
    // Left (between top and bottom of hole)
    if (h.left > 0) {
      panels.add(Positioned(
        left: 0,
        top: h.top,
        width: h.left,
        height: h.height,
        child: const ColoredBox(color: _dimColor),
      ));
    }
    // Right
    if (h.right < screen.width) {
      panels.add(Positioned(
        left: h.right,
        top: h.top,
        width: screen.width - h.right,
        height: h.height,
        child: const ColoredBox(color: _dimColor),
      ));
    }
    return panels;
  }

  @override
  Widget build(BuildContext context) {
    // Любой новый диалог поверх шага — полностью прячем тур (без затемнения),
    // клики идут в открытое окно. После закрытия диалога тур возвращается.
    if (_pausedForDialog) {
      return const IgnorePointer(child: SizedBox.expand());
    }

    final screen = MediaQuery.sizeOf(context);
    final hole = _hole;
    final isLast = widget.stepIndex >= widget.stepCount - 1;
    final cardRect = Rect.fromLTWH(_cardPos.dx, _cardPos.dy, _cardWidth, _cardSize.height);

    // Overlay + pass-through в hole; зона карточки всегда кликабельна (даже над hole).
    final cardHit = cardRect.inflate(4);
    return _HolePassThrough(
      hole: hole?.deflate(3),
      card: cardHit,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ..._dimPanels(screen, hole),
          if (hole != null)
            Positioned(
              left: hole.left,
              top: hole.top,
              width: hole.width,
              height: hole.height,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_holeRadius),
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
            ),
          if (hole != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _arrowCtrl,
                  builder: (_, __) => CustomPaint(
                    painter: _TourArrowPainter(
                      card: cardRect,
                      hole: hole,
                      progress: Curves.easeOutCubic.transform(_arrowCtrl.value),
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: _cardPos.dx,
            top: _cardPos.dy,
            width: _cardWidth,
            child: Material(
              key: _cardKey,
              color: AppColors.surface,
              elevation: 12,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary.withOpacity(0.45)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.tourTitle,
                      style: GoogleFonts.manrope(
                        color: AppColors.textDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.stepIndex + 1} / ${widget.stepCount}',
                      style: GoogleFonts.manrope(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.step.title,
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 17),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.step.body,
                      style: GoogleFonts.manrope(
                        color: AppColors.textMuted,
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => widget.onAction(_TourAction.finish),
                          child: Text(
                            'Закончить',
                            style: GoogleFonts.manrope(color: AppColors.textDim),
                          ),
                        ),
                        TextButton(
                          onPressed: () => widget.onAction(_TourAction.skip),
                          child: Text(
                            'Пропустить',
                            style: GoogleFonts.manrope(color: AppColors.textMuted),
                          ),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () => widget.onAction(_TourAction.next),
                          child: Text(
                            isLast ? 'Готово' : 'Далее',
                            style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// В зоне [hole] hit-test пропускается в UI под оверлеем,
/// кроме [card] — подсказка тура и её кнопки всегда принимают клики.
class _HolePassThrough extends SingleChildRenderObjectWidget {
  final Rect? hole;
  final Rect? card;

  const _HolePassThrough({
    required this.hole,
    required this.card,
    required Widget child,
  }) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHolePassThrough(hole: hole, card: card);

  @override
  void updateRenderObject(BuildContext context, _RenderHolePassThrough renderObject) {
    renderObject.hole = hole;
    renderObject.card = card;
  }
}

class _RenderHolePassThrough extends RenderProxyBox {
  _RenderHolePassThrough({Rect? hole, Rect? card})
      : _hole = hole,
        _card = card;

  Rect? _hole;
  Rect? _card;

  set hole(Rect? value) {
    if (_hole == value) return;
    _hole = value;
  }

  set card(Rect? value) {
    if (_card == value) return;
    _card = value;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final c = _card;
    if (c != null && c.contains(position)) {
      return super.hitTest(result, position: position);
    }
    final h = _hole;
    if (h != null && h.contains(position)) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}

/// Минимальный зазор между двумя прямоугольниками (0, если пересекаются).
double _clearGap(Rect a, Rect b) {
  final dx = math.max(0.0, math.max(a.left - b.right, b.left - a.right));
  final dy = math.max(0.0, math.max(a.top - b.bottom, b.top - a.bottom));
  if (a.overlaps(b)) return 0;
  // Разделены по одной оси — берём зазор по ней; по диагонали — гипотенуза
  if (dx > 0 && dy > 0) return math.sqrt(dx * dx + dy * dy);
  return math.max(dx, dy);
}

/// Точка на границе [rect] в направлении к [toward].
Offset _anchorOnRect(Rect rect, Offset toward) {
  final c = rect.center;
  final dx = toward.dx - c.dx;
  final dy = toward.dy - c.dy;
  if (dx.abs() < 0.001 && dy.abs() < 0.001) {
    return Offset(rect.right, c.dy);
  }
  final scaleX = dx.abs() > 0.001 ? (rect.width / 2) / dx.abs() : double.infinity;
  final scaleY = dy.abs() > 0.001 ? (rect.height / 2) / dy.abs() : double.infinity;
  final scale = math.min(scaleX, scaleY);
  return Offset(c.dx + dx * scale, c.dy + dy * scale);
}

Offset _nudge(Offset from, Offset to, double px) {
  final v = to - from;
  final d = v.distance;
  if (d < 1) return from;
  return from + v * (px / d);
}

class _TourArrowPainter extends CustomPainter {
  final Rect card;
  final Rect hole;
  final double progress;
  final Color color;

  _TourArrowPainter({
    required this.card,
    required this.hole,
    required this.progress,
    required this.color,
  });

  Path _curve() {
    // Старт чуть от края карточки, конец чуть до края цели — дуга в зазоре.
    final rawStart = _anchorOnRect(card, hole.center);
    final rawEnd = _anchorOnRect(hole, card.center);
    final start = _nudge(rawStart, rawEnd, 6);
    final end = _nudge(rawEnd, rawStart, 10);
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1) {
      return Path()..moveTo(start.dx, start.dy);
    }
    // Изгиб ~28% длины — дуга заметнее
    final bend = len * 0.28;
    final nx = -dy / len * bend;
    final ny = dx / len * bend;
    final cp1 = Offset(start.dx + dx * 0.3 + nx, start.dy + dy * 0.3 + ny);
    final cp2 = Offset(start.dx + dx * 0.7 + nx, start.dy + dy * 0.7 + ny);
    return Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final path = _curve();
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;

    final metric = metrics.first;
    final drawLen = metric.length * progress.clamp(0.0, 1.0);
    if (drawLen < 0.5) return;
    final drawn = metric.extractPath(0, drawLen);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(drawn, paint);

    if (progress > 0.06) {
      // Направление — по вектору касательной (не angle: надёжнее на кривых).
      final tangent = metric.getTangentForOffset(drawLen);
      Offset dir;
      if (tangent != null && tangent.vector.distance > 1e-4) {
        dir = tangent.vector;
      } else {
        // fallback: небольшой сегмент назад по пути
        final back = metric.getTangentForOffset(math.max(0.0, drawLen - 4));
        final tip = tangent?.position ?? Offset.zero;
        dir = back != null ? tip - back.position : const Offset(1, 0);
      }
      final tip = tangent?.position;
      if (tip != null) {
        _drawArrowHead(canvas, tip, dir, color);
      }
    }
  }

  /// Наконечник смотрит вдоль [direction] (куда растёт путь → к цели).
  void _drawArrowHead(Canvas canvas, Offset tip, Offset direction, Color color) {
    final d = direction.distance;
    if (d < 1e-6) return;
    final dir = Offset(direction.dx / d, direction.dy / d);
    final normal = Offset(-dir.dy, dir.dx);
    const len = 12.0;
    const halfW = 7.0;
    final base = tip - dir * len;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(base.dx + normal.dx * halfW, base.dy + normal.dy * halfW)
      ..lineTo(base.dx - normal.dx * halfW, base.dy - normal.dy * halfW)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _TourArrowPainter old) =>
      old.card != card || old.hole != hole || old.progress != progress || old.color != color;
}
