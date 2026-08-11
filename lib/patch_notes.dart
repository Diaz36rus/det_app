import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'app_version.dart';
import 'database.dart';
import 'responsive.dart';

/// Ключ в app_settings: последний build, для которого уже показали патчноут.
const kLastSeenPatchBuildKey = 'last_seen_patch_build';

/// Откуда обновлялись (пишется перед установкой пакета) — чтобы показать весь диапазон.
const kPatchUpdateFromBuildKey = 'patch_update_from_build';

class PatchRelease {
  final int build;
  final String version;
  final List<String> items;

  const PatchRelease({
    required this.build,
    required this.version,
    required this.items,
  });

  String get label => '$version+$build';
}

/// Новые релизы — в начало списка.
/// При обновлении показываем все записи с build в (lastSeen; current].
const List<PatchRelease> kPatchNotes = [
  PatchRelease(
    build: 36,
    version: '1.0.1',
    items: [
      'Оплата заказа только при открытой смене — без обхода',
    ],
  ),
  PatchRelease(
    build: 35,
    version: '1.0.1',
    items: [
      'Убран таймер работ — не нужен в ежедневном сценарии',
    ],
  ),
  PatchRelease(
    build: 34,
    version: '1.0.1',
    items: [
      'Новый заказ: шаблоны корзины (сохранить / подставить)',
      'Сайдбар: последний бэкап + создать бэкап сейчас',
    ],
  ),
  PatchRelease(
    build: 33,
    version: '1.0.1',
    items: [
      'Z-отчёт: кириллица и ₽ в PDF (шрифт Noto Sans)',
    ],
  ),
  PatchRelease(
    build: 32,
    version: '1.0.1',
    items: [
      'Календарь: режим «Неделя» + полоска дней Пн–Вс',
      'Касса: Z-отчёт смены (PDF) после закрытия и из списка',
      'Склад: мин. остаток и алерт «мало» (схема БД 22)',
    ],
  ),
  PatchRelease(
    build: 31,
    version: '1.0.1',
    items: [
      'Новый заказ: «Как в прошлый раз» — корзина из последнего заказа клиента',
      'Касса→Долги: копирование текста, WhatsApp, быстрая оплата',
      'Доска: долг на карточке, быстрая оплата и PDF заказ-наряда',
      'Календарь (деталь): позиции без цеха больше не пропадают',
    ],
  ),
  PatchRelease(
    build: 30,
    version: '1.0.1',
    items: [
      'Календарь→заказ: переход «Календарь» после создания больше не ломается',
      'Календарь: скролл не открывает создание слота; без времени — только due/end день',
      'LAN: ревизия данных после оплаты, заказа, статуса, открытия/закрытия смены',
      'Касса: сумма opening_cash по всем наличным; dispose контроллеров при отмене',
    ],
  ),
  PatchRelease(
    build: 29,
    version: '1.0.1',
    items: [
      'Касса: транзакции по кассе, правка/удаление операций и оплат',
      'Чек-лист выдачи в логичном порядке; «Выдан» только при полном чек-листе',
      'Единый формат дат/времени в интерфейсе',
      'Календарь: ширина карточек по тексту; канал обновлений :8080',
    ],
  ),
  PatchRelease(
    build: 28,
    version: '1.0.1',
    items: [
      'Обновление: «Проверить» сохраняет URL из поля; порт :7878 автоматически → :8080',
    ],
  ),
  PatchRelease(
    build: 27,
    version: '1.0.1',
    items: [
      'Календарь (моб.): имя клиента не обрезается, параллельные заказы без зазора',
    ],
  ),
  PatchRelease(
    build: 26,
    version: '1.0.1',
    items: [
      'Календарь: карточки заказов уже по ширине (~вдвое), клик по пустому месту — новая запись',
    ],
  ),
  PatchRelease(
    build: 25,
    version: '1.0.1',
    items: [
      'Windows: после обновления приложение перезапускается само',
    ],
  ),
  PatchRelease(
    build: 24,
    version: '1.0.1',
    items: [
      'Календарь: справа свободная полоса «+» — клик записывает другую машину на это время',
      'Параллельные заказы не занимают всю ширину колонки',
    ],
  ),
  PatchRelease(
    build: 23,
    version: '1.0.1',
    items: [
      'Календарь: параллельные заказы рисуются рядом, без наложения «стопкой»',
      'Убрано предупреждение о конфликте слота — пересечения по времени разрешены',
    ],
  ),
  PatchRelease(
    build: 22,
    version: '1.0.1',
    items: [
      'QR хоста: камера открывает http-страницу /join → кнопка «Открыть Det App»',
      'Так работает со стандартным сканером (не «нет приложений для QR»)',
    ],
  ),
  PatchRelease(
    build: 21,
    version: '1.0.1',
    items: [
      'QR хоста: системная камера открывает Det App и подставляет адрес (detapp://)',
      'Больше не уходит в браузер или «Заметки»',
    ],
  ),
  PatchRelease(
    build: 20,
    version: '1.0.1',
    items: [
      'QR хоста: в приложении «Сканировать QR» — адрес подставляется сам (не через браузер)',
      'Системной камерой больше не пользуемся для QR связи',
    ],
  ),
  PatchRelease(
    build: 19,
    version: '1.0.1',
    items: [
      'Календарь: длинные заказы и пересечения снова отображаются (в т.ч. через полночь)',
      'Отмена оплаты в карточке заказа + подтверждение перед проведением',
      'Кнопка «Оплатить» зелёная, отдельно от «Закрыть»',
    ],
  ),
  PatchRelease(
    build: 18,
    version: '1.0.1',
    items: [
      'Выдача: больше не блокируется из‑за шапки пакета «Оклейка»/«Тонировка», если все зоны выполнены',
      'В ошибке выдачи показываются названия незакрытых работ',
    ],
  ),
  PatchRelease(
    build: 17,
    version: '1.0.1',
    items: [
      'Плёнки на телефоне: стабильный ввод м.п., автосохранение, кнопка «Сохранить»',
    ],
  ),
  PatchRelease(
    build: 16,
    version: '1.0.1',
    items: [
      'Цех Оклейка: расход плёнки (м.п.) заполняет мастер — кнопка «Плёнки · расход»',
    ],
  ),
  PatchRelease(
    build: 15,
    version: '1.0.1',
    items: [
      'Оклейка: состав зон снова свёрнут (не занимает весь экран на телефоне)',
    ],
  ),
  PatchRelease(
    build: 14,
    version: '1.0.1',
    items: [
      'Чек-лист выдачи свёрнут в кнопку (разворачивается по нажатию)',
    ],
  ),
  PatchRelease(
    build: 13,
    version: '1.0.1',
    items: [
      'Дефекты на ПК обновляются в реальном времени (с телефона, без перезапуска)',
      'Лента заказа подтягивает новые дефекты сразу',
    ],
  ),
  PatchRelease(
    build: 12,
    version: '1.0.1',
    items: [
      'Патчноут: при обновлении показываются все промежуточные версии (от старой до новой)',
      'Полный список изменений по сборкам 2→12',
    ],
  ),
  PatchRelease(
    build: 11,
    version: '1.0.1',
    items: [
      'Дефекты: автогруппировка по элементу из описания (капот, крыло, стойка…)',
      'Вкладки по элементам кузова + подсказка при вводе',
    ],
  ),
  PatchRelease(
    build: 10,
    version: '1.0.1',
    items: [
      'Дефекты: список раскрывается после сохранения, фото на весь экран',
      'Дефекты: надёжнее синк с ПК (таблицы, таймауты для фото)',
      'Клиенты на телефоне: форма «новый клиент» сворачивается — список снова листается',
    ],
  ),
  PatchRelease(
    build: 9,
    version: '1.0.1',
    items: [
      'Окно «Что нового» при первом запуске после обновления',
      'Патч сразу на Windows и Android (один канал обновлений)',
    ],
  ),
  PatchRelease(
    build: 8,
    version: '1.0.1',
    items: [
      'Дефекты с фото с телефона → лента заказа',
      'Чеклист выдачи («к выдаче») с проверкой перед статусом «Выдан»',
      'Плёнки оклейки: каталог + метры погонные, несколько на заказ',
      'Предупреждение о конфликте слотов в календаре',
      'История заказов по госномеру при создании',
      'QR-код URL хоста синхронизации',
      'Отчёт «мастера за день» в статистике',
      'Новая иконка приложения',
    ],
  ),
  PatchRelease(
    build: 7,
    version: '1.0.1',
    items: [
      'Обновления Android по LAN (APK в latest.json)',
      'Авто-обнаружение хоста синхронизации («Найти хост»)',
      'Двусторонняя подтяжка UI по ревизии БД (ПК ↔ телефон)',
      'Кассы / несколько регистров, доработки оплаты',
      'Календарь: карточки «Общая запись» по ширине текста (свободная полоса кликабельна)',
      'Мобильное меню: режим «ПК + телефон» и «полный телефон»',
      'Pull-to-refresh на доске, тосты после поиска хоста',
      'Заголовок Windows: Det App',
    ],
  ),
  PatchRelease(
    build: 6,
    version: '1.0.1',
    items: [
      'LAN-синхронизация: ПК-хост (:7878) + телефон-клиент',
      'Канал обновлений Windows (latest.json + zip)',
      'Превью в меню (калькулятор убран)',
    ],
  ),
  PatchRelease(
    build: 5,
    version: '1.0.1',
    items: [
      'Доработки календаря и записи слотов',
      'Стабилизация сборок и портативного пакета',
    ],
  ),
  PatchRelease(
    build: 4,
    version: '1.0.1',
    items: [
      'Пустые состояния корзины / оплаты',
      'Цех: «Готово» vs «Перевести»',
      'Утилиты VIN, туры по интерфейсу',
    ],
  ),
  PatchRelease(
    build: 3,
    version: '1.0.1',
    items: [
      'Доработки заказов и цехов',
      'Исправления по обратной связи смены',
    ],
  ),
  PatchRelease(
    build: 2,
    version: '1.0.1',
    items: [
      'Базовая CRM: заказы, клиенты, касса, статистика',
      'Канбан / цеха, календарь, сотрудники',
    ],
  ),
];

/// Все непросмотренные релизы строго между [lastSeenBuild] и [currentBuild].
/// Если lastSeen ещё не было (старый ноут) — показываем все известные до текущей.
List<PatchRelease> unreadPatchNotes({
  required int currentBuild,
  required int? lastSeenBuild,
}) {
  final from = lastSeenBuild ?? 0;
  return kPatchNotes
      .where((r) => r.build > from && r.build <= currentBuild)
      .toList();
}

/// Запомнить текущую сборку перед установкой обновления (Windows/Android).
Future<void> markPatchNotesUpdateFrom() async {
  await AppVersion.ensureLoaded();
  final b = AppVersion.build;
  if (b <= 0) return;
  await DatabaseHelper().setAppSetting(kPatchUpdateFromBuildKey, '$b');
}

Future<void> maybeShowPatchNotes(BuildContext context) async {
  await AppVersion.ensureLoaded();
  final current = AppVersion.build;
  if (current <= 0) return;

  final fromUpdateRaw = await DatabaseHelper().getAppSetting(kPatchUpdateFromBuildKey);
  final lastSeenRaw = await DatabaseHelper().getAppSetting(kLastSeenPatchBuildKey);
  final fromUpdate = int.tryParse(fromUpdateRaw ?? '');
  final lastSeen = int.tryParse(lastSeenRaw ?? '');

  // Приоритет: «откуда обновились» → иначе последний просмотренный патчноут.
  // Если оба пустые (старый ноут без фичи) — from=0 → весь список до current.
  final effectiveFrom = fromUpdate ?? lastSeen;
  final unread = unreadPatchNotes(currentBuild: current, lastSeenBuild: effectiveFrom);
  if (unread.isEmpty) {
    await DatabaseHelper().setAppSetting(kLastSeenPatchBuildKey, '$current');
    if (fromUpdate != null) {
      await DatabaseHelper().setAppSetting(kPatchUpdateFromBuildKey, '');
    }
    return;
  }
  if (!context.mounted) return;

  await showPatchNotesDialog(context, unread, fromBuild: effectiveFrom);
  await DatabaseHelper().setAppSetting(kLastSeenPatchBuildKey, '$current');
  await DatabaseHelper().setAppSetting(kPatchUpdateFromBuildKey, '');
}

Future<void> showPatchNotesDialog(
  BuildContext context,
  List<PatchRelease> releases, {
  int? fromBuild,
  bool markSeen = false,
}) async {
  final newest = releases.isEmpty ? null : releases.first.build;
  final oldest = releases.isEmpty ? null : releases.last.build;
  final rangeTitle = (newest != null && oldest != null && newest != oldest)
      ? 'Что нового · +$oldest → +$newest'
      : 'Что нового';

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final mobile = AppResponsive.isMobile(ctx);
      return AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            Icon(Icons.auto_awesome, color: AppColors.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                rangeTitle,
                style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: AppResponsive.dialogWidth(ctx, desktop: 440),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: mobile ? 420 : 520),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (fromBuild != null && fromBuild > 0) ...[
                    Text(
                      'Обновление с сборки +$fromBuild',
                      style: GoogleFonts.manrope(
                        color: AppColors.textDim,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else if (releases.length > 1) ...[
                    Text(
                      'Все изменения с предыдущей установки',
                      style: GoogleFonts.manrope(
                        color: AppColors.textDim,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (var i = 0; i < releases.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    Text(
                      releases[i].label,
                      style: GoogleFonts.manrope(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final line in releases[i].items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '•  ',
                              style: GoogleFonts.manrope(
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                line,
                                style: GoogleFonts.manrope(
                                  color: AppColors.textMuted,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Понятно', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ],
      );
    },
  );

  if (markSeen) {
    await AppVersion.ensureLoaded();
    await DatabaseHelper().setAppSetting(kLastSeenPatchBuildKey, '${AppVersion.build}');
  }
}
