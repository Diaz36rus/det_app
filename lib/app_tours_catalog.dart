import 'package:flutter/material.dart';

import 'app_menu.dart';
import 'tour_keys.dart';

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
  /// Разрешить клик по подсвеченному (сценарии). В справочнике по умолчанию нет.
  final bool allowTargetTap;

  const AppTourStep({
    required this.title,
    required this.body,
    this.targetKey,
    this.menuIndex,
    this.dismissOrderDetails = false,
    this.requireOrders = false,
    this.allowTargetTap = false,
  });
}

class AppTour {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<AppTourStep> steps;
  /// false = справочник, true = сценарий «делаем вместе».
  final bool isScenario;

  const AppTour({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.steps,
    this.isScenario = false,
  });
}

/// Каталог туров: справочники по темам, затем сценарии.
class AppTours {
  static final List<AppTour> all = [
    // ─── Справочники ─────────────────────────────────────────────
    AppTour(
      id: 'guide_shell',
      title: 'Меню слева',
      subtitle: 'Куда нажимать: доска, заказ, календарь, касса…',
      icon: Icons.menu_open_rounded,
      steps: [
        AppTourStep(
          title: 'Как пользоваться обучением',
          body: 'Подсветка показывает кнопку или блок, текст рядом объясняет простыми словами. '
              'Ничего сохранять не нужно — просто читайте и жмите «Далее». '
              '«Пропустить» — один шаг, «Закончить» — выход из обучения.',
        ),
        AppTourStep(
          title: 'Доска заказов',
          body: 'Главный экран смены. Здесь все машины по этапам: приняли, моют, полируют, выдали. '
              'Откройте карточку — увидите работы, деньги и заметки.',
          targetKey: TourKeys.menuBoard,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Новый заказ',
          body: 'Приём машины: кто клиент, какое авто, что делаем и когда забрать. '
              'После сохранения заказ появится на доске. '
              'У мастера этого пункта обычно нет — приём делает администратор.',
          targetKey: TourKeys.menuNewOrder,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Календарь',
          body: 'Расписание на день: кто когда записан и какие цеха заняты. '
              'Сюда заходят, чтобы не поставить две машины на одно время. '
              'Подробнее — в теме «Календарь».',
          targetKey: TourKeys.menuCalendar,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Клиенты',
          body: 'Список людей и их машин: телефон, имя, история визитов. '
              'Перед повторным визитом удобно глянуть, что уже делали.',
          targetKey: TourKeys.menuClients,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Касса',
          body: 'Деньги студии за день: оплаты, расходы, открытие и закрытие смены. '
              'У мастера кассы в меню нет.',
          targetKey: TourKeys.menuCash,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Статистика',
          body: 'Сводка: сколько заработали, какая загрузка, как сработали мастера. '
              'На телефоне в режиме «ПК + телефон» этого пункта нет — смотрите на компьютере.',
          targetKey: TourKeys.menuStats,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Сотрудники',
          body: 'Список мастеров и их специализации (мойка, полировка…). '
              'От этого зависит, в каком цехе человека видно и какие работы ему можно дать.',
          targetKey: TourKeys.menuStaff,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Прайс',
          body: 'Что продаём клиенту и по каким ценам (с учётом класса авто). '
              'Не путать со складом: прайс — услуги, склад — химия и расходники на полке.',
          targetKey: TourKeys.menuServices,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Склад',
          body: 'Что есть в наличии: химия, плёнка, расходники. Можно отметить приход и списание. '
              'На лёгком телефоне склад часто только на ПК.',
          targetKey: TourKeys.menuInventory,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Завершённые',
          body: 'Машины, которые уже отдали клиенту. Живая доска от них не забивается — '
              'старые заказы ищите здесь.',
          targetKey: TourKeys.menuCompleted,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Цеха',
          body: 'Отдельный вход для мастера: мойка, химчистка, полировка и т.д. '
              'Внутри — только работы своего цеха, без кассы и приёма новых заказов.',
          targetKey: TourKeys.workshops,
          menuIndex: AppMenuIds.board,
        ),
      ],
    ),
    AppTour(
      id: 'guide_header',
      title: 'Шапка и поиск',
      subtitle: 'Поиск, дата, обновление, ошибки, обучение',
      icon: Icons.search_rounded,
      steps: [
        AppTourStep(
          title: 'Поиск по всей базе',
          body: 'Ищет клиента, телефон, номер машины, VIN или номер заказа. '
              'На компьютере удобно нажать Ctrl+K. '
              'Это не то же самое, что поиск на доске — тот фильтрует только видимые карточки.',
          targetKey: TourKeys.search,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Мини-календарь в меню',
          body: 'Календарь слева у меню — быстрый переход к дню. '
              'Нажали дату — откроется большой календарь на этот день. '
              'Это не пункт «Календарь» в списке меню, а короткая кнопка к нему.',
          targetKey: TourKeys.quickCalendar,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Обновление',
          body: 'Проверяет, есть ли новая версия программы. '
              'После установки на компьютере и телефонах будет один и тот же номер сборки — '
              'так меньше путаницы в смене.',
          targetKey: TourKeys.updateButton,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Сообщить об ошибке',
          body: 'Нашли сбой или странное поведение — кратко опишите: где были и что нажали. '
              'Рядом видно, сколько открытых сообщений ещё не разобрали.',
          targetKey: TourKeys.bugReport,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Обучение',
          body: 'Вы здесь. Сначала справочники по экранам, ниже — сценарии «попробуем вместе». '
              'Можно проходить в любом порядке и сколько угодно раз.',
          targetKey: TourKeys.trainButton,
          menuIndex: AppMenuIds.board,
        ),
      ],
    ),
    AppTour(
      id: 'guide_board',
      title: 'Доска заказов',
      subtitle: 'Колонки, поиск на доске, фильтры',
      icon: Icons.view_kanban_outlined,
      steps: [
        AppTourStep(
          title: 'Зачем доска',
          body: 'Это «стена» смены: сразу видно, на каком этапе каждая машина. '
              'Не нужно держать всё в голове или в блокноте.',
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Колонки и карточки',
          body: 'Каждая колонка — этап (принят, мойка, полировка… выдан). '
              'На телефоне колонки листайте вбок. Нажмите на карточку — откроется заказ целиком.',
          targetKey: TourKeys.kanbanArea,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Поиск на доске',
          body: 'Строка над колонками — быстрый отбор среди того, что уже на доске '
              '(имя, номер, телефон). '
              'Поиск слева в меню ищет по всей базе — это другая кнопка.',
          targetKey: TourKeys.kanbanSearch,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Фильтр по этапу',
          body: 'Можно оставить на экране только один этап, например «Мойка». '
              'Когда машин много — так проще не потерять нужную.',
          targetKey: TourKeys.kanbanStatusFilter,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'С долгом',
          body: 'Показывает только тех, кто ещё не доплатил. '
              'Удобно вечером проверить, с кого ждать деньги.',
          targetKey: TourKeys.kanbanDebtFilter,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Сегодня',
          body: 'Оставляет заказы, связанные с сегодняшним днём. '
              'Хвосты прошлых дней временно прячутся, чтобы не мешали.',
          targetKey: TourKeys.kanbanTodayFilter,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Что на карточке',
          body: 'Обычно видно клиента, авто, номер, сумму или долг и ход работ. '
              'Откройте любую — внутри работы, оплата, заметки и фото дефектов.',
          targetKey: TourKeys.kanbanArea,
          menuIndex: AppMenuIds.board,
        ),
      ],
    ),
    AppTour(
      id: 'order_deep',
      title: 'Карточка заказа',
      subtitle: 'Работы, время, заметки, оплата',
      icon: Icons.fact_check_outlined,
      steps: [
        AppTourStep(
          title: 'Шапка',
          body: 'Клиент, телефон, машина, номер заказа и текущий этап. '
              'Этап меняйте по факту работ — от этого зависит, в какой колонке заказ на доске.',
          targetKey: TourKeys.orderDetailsHeader,
        ),
        AppTourStep(
          title: 'Работы',
          body: 'Список того, что делаем: цена, сделано или нет, кто мастер, время. '
              'Работы одного цеха собраны вместе; там же можно указать зарплату мастеру за этот цех. '
              'Мастер обычно правит только свой цех.',
          targetKey: TourKeys.orderDetailsWorks,
        ),
        AppTourStep(
          title: 'Время',
          body: 'Когда машину приняли и когда ориентировочно отдать. '
              'Это же видно в календаре, чтобы смена не накладывалась друг на друга.',
          targetKey: TourKeys.orderDetailsSchedule,
        ),
        AppTourStep(
          title: 'Заметки',
          body: 'Комментарии для клиента, для цеха или себе. '
              'Ниже — лента: кто что менял. Мастер в своём цехе видит цеховые сообщения.',
          targetKey: TourKeys.orderDetailsNotes,
        ),
        AppTourStep(
          title: 'Оплата и выдача',
          body: 'Итого, скидка, уже внесено, сколько осталось. '
              'Кнопка оплаты пишет приход в кассу (смена должна быть открыта). '
              'Перед выдачей — короткий чек-лист: ключи, осмотр и т.п.',
          targetKey: TourKeys.orderDetailsPayment,
        ),
        AppTourStep(
          title: 'Дальше — цех мастера',
          body: 'Закройте карточку и откройте «Цеха» в меню. '
              'Там мастер видит свои работы без кассы и без чужих настроек.',
          targetKey: TourKeys.workshops,
          dismissOrderDetails: true,
        ),
      ],
    ),
    AppTour(
      id: 'guide_calendar',
      title: 'Календарь',
      subtitle: 'Общая запись и время по цехам',
      icon: Icons.calendar_month_outlined,
      steps: [
        AppTourStep(
          title: 'Зачем календарь',
          body: 'Чтобы видеть загрузку дня и не записывать двух клиентов на одно окно. '
              'Сюда же смотрят, когда клиент спрашивает: «А когда будет готово?»',
          menuIndex: AppMenuIds.calendar,
        ),
        AppTourStep(
          title: 'Экран календаря',
          body: 'Сверху — день (листайте назад/вперёд). Ниже — сетка записей. '
              'Нажмите на запись — откроется заказ.',
          targetKey: TourKeys.calendarArea,
          menuIndex: AppMenuIds.calendar,
        ),
        AppTourStep(
          title: 'Два режима',
          body: '«Общая запись» — машина целиком: приём и ориентир выдачи. '
              '«Детально» — слоты по цехам (мойка, полировка…), чтобы мастера не пересеклись.',
          targetKey: TourKeys.calendarMode,
          menuIndex: AppMenuIds.calendar,
        ),
        AppTourStep(
          title: 'На телефоне',
          body: 'Подписи короче («Общая» / «Детально»), день удобнее листать пальцем. '
              'Суть та же, что на компьютере.',
          targetKey: TourKeys.calendarMode,
          menuIndex: AppMenuIds.calendar,
        ),
        AppTourStep(
          title: 'Мини-календарь в меню',
          body: 'Если нужно быстро прыгнуть на дату — откройте меню слева '
              '(на телефоне — кнопка «меню») и выберите день в мини-календаре. '
              'Это тот же календарь, только короткий путь.',
          targetKey: TourKeys.quickCalendar,
          menuIndex: AppMenuIds.board,
        ),
      ],
    ),
    AppTour(
      id: 'guide_clients',
      title: 'Клиенты',
      subtitle: 'База людей и машин',
      icon: Icons.people_outline,
      steps: [
        AppTourStep(
          title: 'Зачем раздел',
          body: 'Здесь хранятся телефоны, имена, машины и прошлые заказы. '
              'При новом визите не нужно всё спрашивать заново.',
          menuIndex: AppMenuIds.clients,
        ),
        AppTourStep(
          title: 'Список',
          body: 'Найдите человека по имени или телефону, откройте карточку — '
              'увидите авто и историю. Можно добавить нового клиента вручную.',
          targetKey: TourKeys.clientsArea,
          menuIndex: AppMenuIds.clients,
        ),
        AppTourStep(
          title: 'Кто этим пользуется',
          body: 'Обычно администратор и управляющий. '
              'У мастера пункта «Клиенты» в меню нет — ему достаточно цеха и доски.',
          menuIndex: AppMenuIds.clients,
        ),
      ],
    ),
    AppTour(
      id: 'guide_cash',
      title: 'Касса',
      subtitle: 'Смена, оплаты, расходы',
      icon: Icons.account_balance_wallet_outlined,
      steps: [
        AppTourStep(
          title: 'Зачем касса',
          body: 'Чтобы в конце дня было ясно: сколько взяли с клиентов и сколько потратили '
              '(химия, зарплата, мелочи). Не «на глаз» и не только в переписке.',
          menuIndex: AppMenuIds.cash,
        ),
        AppTourStep(
          title: 'Цифры сверху',
          body: 'Баланс касс, наличные в ящике и оплаты картой за период. '
              'С них удобно начинать разговор «как прошёл день».',
          targetKey: TourKeys.cashKpi,
          menuIndex: AppMenuIds.cash,
        ),
        AppTourStep(
          title: 'Смена',
          body: 'Утром смену открывают и указывают остатки по кассам '
              '(основная, терминал, переводы…). Вечером закрывают и сверяют факт.',
          targetKey: TourKeys.cashShift,
          menuIndex: AppMenuIds.cash,
        ),
        AppTourStep(
          title: 'Быстрые действия',
          body: '«Новый платёж» — шаблоны внутри диалога. Также возврат, инкассация и отчёт по смене.',
          targetKey: TourKeys.cashTemplates,
          menuIndex: AppMenuIds.cash,
        ),
        AppTourStep(
          title: 'История',
          body: 'Последние платежи справа. Нажали — правка; долгий тап — удалить/отменить.',
          targetKey: TourKeys.cashJournal,
          menuIndex: AppMenuIds.cash,
        ),
        AppTourStep(
          title: 'Зарплата мастеров',
          body: 'В кассе видно, сколько начислено мастеру, сколько уже выплатили и сколько осталось. '
              'Суммы по работам берутся из карточек заказов (поле ЗП по цеху).',
          menuIndex: AppMenuIds.cash,
        ),
      ],
    ),
    AppTour(
      id: 'guide_stats',
      title: 'Статистика',
      subtitle: 'Выручка и загрузка',
      icon: Icons.insights_outlined,
      steps: [
        AppTourStep(
          title: 'Что здесь',
          body: 'Сводка по деньгам и загрузке за период. '
              'Удобно владельцу и управляющему, не для каждой минуты смены.',
          targetKey: TourKeys.statsArea,
          menuIndex: AppMenuIds.stats,
        ),
        AppTourStep(
          title: 'Где смотреть',
          body: 'На компьютере — всегда. На телефоне в режиме «ПК + телефон» пункт скрыт: '
              'телефон для смены, отчёты — на большом экране. '
              'В «полном телефоне» статистика снова в меню.',
          menuIndex: AppMenuIds.board,
        ),
      ],
    ),
    AppTour(
      id: 'guide_staff',
      title: 'Сотрудники',
      subtitle: 'Мастера и специальности',
      icon: Icons.engineering_outlined,
      steps: [
        AppTourStep(
          title: 'Список людей',
          body: 'Кто работает в студии и какие у него специальности. '
              'От этого зависит назначение на работы в заказе.',
          targetKey: TourKeys.staffArea,
          menuIndex: AppMenuIds.staff,
        ),
        AppTourStep(
          title: 'Должность и цех — разное',
          body: 'Должность (администратор, мастер…) — что человеку можно в программе. '
              'Цех (мойка, полировка…) — какие работы он выполняет руками. '
              'У одного человека может быть несколько цехов.',
          menuIndex: AppMenuIds.staff,
        ),
      ],
    ),
    AppTour(
      id: 'guide_services',
      title: 'Прайс',
      subtitle: 'Услуги и цены',
      icon: Icons.home_repair_service_outlined,
      steps: [
        AppTourStep(
          title: 'Каталог услуг',
          body: 'Что предлагаем клиенту и сколько стоит по классам авто. '
              'Отсюда же услуги попадают в новый заказ.',
          targetKey: TourKeys.servicesArea,
          menuIndex: AppMenuIds.services,
        ),
        AppTourStep(
          title: 'Прайс и склад',
          body: 'Прайс — «что продаём». Склад — «что лежит на полке». '
              'К услуге можно привязать списание материалов, но это разные экраны.',
          menuIndex: AppMenuIds.services,
        ),
      ],
    ),
    AppTour(
      id: 'guide_warehouse',
      title: 'Склад',
      subtitle: 'Остатки и движения',
      icon: Icons.inventory_2_outlined,
      steps: [
        AppTourStep(
          title: 'Остатки',
          body: 'Что есть в наличии по категориям. Можно искать по названию. '
              'Если остаток ниже минимума — пора закупать.',
          targetKey: TourKeys.warehouseArea,
          menuIndex: AppMenuIds.inventory,
        ),
        AppTourStep(
          title: 'Добавить позицию',
          body: 'Кнопка «Добавить» — новая позиция на складе: название, количество, категория.',
          targetKey: TourKeys.warehouseAdd,
          menuIndex: AppMenuIds.inventory,
        ),
        AppTourStep(
          title: 'Движения',
          body: 'Вкладка «Движения» — история приходов и списаний. '
              'Мастер может списывать в рамках своих прав; закуп обычно у администратора.',
          targetKey: TourKeys.warehouseArea,
          menuIndex: AppMenuIds.inventory,
        ),
      ],
    ),
    AppTour(
      id: 'guide_completed',
      title: 'Завершённые',
      subtitle: 'Архив выданных машин',
      icon: Icons.task_alt_outlined,
      steps: [
        AppTourStep(
          title: 'Архив',
          body: 'Заказы, которые уже отдали клиенту. Здесь ищут старый визит, '
              'допечатывают документы или сверяют историю.',
          targetKey: TourKeys.completedArea,
          menuIndex: AppMenuIds.completed,
        ),
        AppTourStep(
          title: 'Почему не на доске',
          body: 'Живая доска нужна для текущей смены. Выданные машины уходят сюда, '
              'чтобы колонки не превращались в свалку.',
          menuIndex: AppMenuIds.completed,
        ),
      ],
    ),
    AppTour(
      id: 'guide_workshops',
      title: 'Цеха для мастера',
      subtitle: 'Свой экран работ без лишнего',
      icon: Icons.handyman_outlined,
      steps: [
        AppTourStep(
          title: 'Вход в цех',
          body: 'В меню слева блок «Цеха». Мастер открывает свой — мойку, полировку и т.д. '
              'Администратор тоже может зайти, чтобы проверить очередь.',
          targetKey: TourKeys.workshops,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Что видит мастер',
          body: 'Только работы своего направления: отметить сделано, фото дефектов, заметки цеха. '
              'Нет кассы, нет «Нового заказа», нет базы клиентов — это не его зона.',
          targetKey: TourKeys.workshops,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Если пунктов мало',
          body: 'Так и задумано: мастеру оставляют доску (или цех), склад со списанием и обучение. '
              'Полное меню — у администратора и управляющего.',
          menuIndex: AppMenuIds.board,
        ),
      ],
    ),
    AppTour(
      id: 'guide_phone',
      title: 'Телефон',
      subtitle: 'Меню, режимы ПК+телефон и полный',
      icon: Icons.smartphone_outlined,
      steps: [
        AppTourStep(
          title: 'Меню на телефоне',
          body: 'Слева нет постоянной панели — меню открывается кнопкой (три полоски). '
              'Внутри те же пункты: доска, календарь, касса…',
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Режим «ПК + телефон»',
          body: 'Телефон для смены: доска, заказ, календарь, клиенты, касса, завершённые. '
              'Статистика, сотрудники, прайс и склад — на компьютере, чтобы не засорять экран.',
          targetKey: TourKeys.mobileModeButton,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Режим «полный телефон»',
          body: 'Все пункты как на ПК. Включают, если работают в основном с телефона '
              'и нужен склад или статистика под рукой.',
          targetKey: TourKeys.mobileModeButton,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Где переключить',
          body: 'Откройте меню → внизу мелкая строка «Режим: …». '
              'У мастера переключателя нет: ему и так короткое меню.',
          targetKey: TourKeys.mobileModeButton,
          menuIndex: AppMenuIds.board,
        ),
      ],
    ),
    AppTour(
      id: 'guide_roles',
      title: 'Роли и права',
      subtitle: 'Владелец, админ, мастер — кто что видит',
      icon: Icons.admin_panel_settings_outlined,
      steps: [
        AppTourStep(
          title: 'Две разные вещи',
          body: 'Должность говорит, что можно в программе (касса, сотрудники, приём…). '
              'Цех говорит, какие работы человек делает руками. Их не путайте.',
        ),
        AppTourStep(
          title: 'Владелец и администратор',
          body: 'Полное меню: приём, клиенты, касса, статистика, прайс, склад, сотрудники. '
              'Они ведут смену «снаружи» и настраивают студию.',
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Мастер',
          body: 'Короткое меню: доска или свой цех, иногда склад для списания, обучение. '
              'Нет нового заказа, клиентов, кассы и настройки прайса — чтобы не отвлекать от работ.',
          targetKey: TourKeys.workshops,
          menuIndex: AppMenuIds.board,
        ),
        AppTourStep(
          title: 'Если чего-то не видно',
          body: 'Сначала проверьте должность и режим телефона. '
              'Часто «пропавший» пункт просто скрыт для роли или убран в «ПК + телефон». '
              'Права меняет администратор студии в панели связи / сотрудниках.',
          menuIndex: AppMenuIds.board,
        ),
      ],
    ),

    // ─── Сценарии ────────────────────────────────────────────────
    AppTour(
      id: 'order',
      title: 'Сценарий: создать заказ',
      subtitle: 'Попробуем приём вместе — по желанию',
      icon: Icons.add_shopping_cart_outlined,
      isScenario: true,
      steps: [
        AppTourStep(
          title: 'Что сделаем',
          body: 'Пройдём короткий путь: клиент → время → услуги → сохранить → '
              'найти на доске → принять оплату. Можно нажимать на подсвеченное.',
          menuIndex: AppMenuIds.newOrder,
          allowTargetTap: true,
        ),
        AppTourStep(
          title: 'Кто приехал',
          body: 'Введите телефон с +7. Если человек уже был — имя и машины подставятся. '
              'Укажите авто, номер и класс: от класса зависят цены.',
          targetKey: TourKeys.orderClient,
          menuIndex: AppMenuIds.newOrder,
          allowTargetTap: true,
        ),
        AppTourStep(
          title: 'Когда забрать и отдать',
          body: 'Поставьте время приёма и ориентир выдачи — это попадёт в календарь и на доску.',
          targetKey: TourKeys.orderSchedule,
          menuIndex: AppMenuIds.newOrder,
          allowTargetTap: true,
        ),
        AppTourStep(
          title: 'Что делаем',
          body: 'Выберите услуги из прайса или добавьте свою строку. Сумма справа обновится.',
          targetKey: TourKeys.orderGallery,
          menuIndex: AppMenuIds.newOrder,
          allowTargetTap: true,
        ),
        AppTourStep(
          title: 'Сохранить',
          body: 'Проверьте состав и нажмите создание заказа — он появится на доске.',
          targetKey: TourKeys.orderCart,
          menuIndex: AppMenuIds.newOrder,
          allowTargetTap: true,
        ),
        AppTourStep(
          title: 'На доске',
          body: 'Найдите новый заказ в колонке «Принят» (или вашем стартовом этапе).',
          targetKey: TourKeys.kanbanArea,
          menuIndex: AppMenuIds.board,
          requireOrders: true,
          allowTargetTap: true,
        ),
        AppTourStep(
          title: 'Как принять деньги',
          body: 'Откройте карточку с доски. Внизу — сколько должен клиент и кнопка оплаты. '
              'Выберите способ и подтвердите.',
          menuIndex: AppMenuIds.board,
          requireOrders: true,
          allowTargetTap: true,
        ),
        AppTourStep(
          title: 'Проверка в кассе',
          body: 'Зайдите в «Касса» — оплата уже должна быть в списке.',
          targetKey: TourKeys.menuCash,
          menuIndex: AppMenuIds.cash,
          allowTargetTap: true,
        ),
      ],
    ),
    AppTour(
      id: 'cash',
      title: 'Сценарий: касса и смена',
      subtitle: 'Открыть смену и провести расход — по желанию',
      icon: Icons.account_balance_wallet_outlined,
      isScenario: true,
      steps: [
        AppTourStep(
          title: 'Зачем практика',
          body: 'Один раз пройти открытие смены и тестовый расход — и вечером будет спокойнее.',
          menuIndex: AppMenuIds.cash,
          allowTargetTap: true,
        ),
        AppTourStep(
          title: 'Смотрим цифры',
          body: 'Сверху — итоги дня. Долги — кто ещё не расплатился.',
          targetKey: TourKeys.cashKpi,
          menuIndex: AppMenuIds.cash,
          allowTargetTap: true,
        ),
        AppTourStep(
          title: 'Откройте смену',
          body: 'Укажите остатки по кассам (наличные, терминал, переводы…). '
              'Можно добавить свою кассу, если так принято в студии.',
          targetKey: TourKeys.cashShift,
          menuIndex: AppMenuIds.cash,
          allowTargetTap: true,
        ),
        AppTourStep(
          title: 'Тестовый расход',
          body: 'Откройте «Новый платёж» — шаблоны внутри. Выберите «Кофе / еда», впишите сумму, сохраните.',
          targetKey: TourKeys.cashTemplates,
          menuIndex: AppMenuIds.cash,
          allowTargetTap: true,
        ),
        AppTourStep(
          title: 'Лента',
          body: 'Справа в «Последних платежах» появится операция. Потом смену можно закрыть.',
          targetKey: TourKeys.cashJournal,
          menuIndex: AppMenuIds.cash,
          allowTargetTap: true,
        ),
      ],
    ),
  ];

  static List<AppTour> get guides => all.where((t) => !t.isScenario).toList();
  static List<AppTour> get scenarios => all.where((t) => t.isScenario).toList();

  static AppTour? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}
