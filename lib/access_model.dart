/// Модель доступа Det App: «должность» (права) vs «цех» (работы).
///
/// ## Продажи / онбординг (тестовый контур)
/// - Приветственный экран: Войти / Создать студию / Меня пригласили.
/// - «Создать студию» → человек = владелец своей студии (не platform admin).
/// - «Меня пригласили» → заявка без роли, пока админ не назначит.
/// - Владелец приложения (platform) — отдельно: блок «Студии» в панели связи.
///
/// Должность — что можно в программе (Владелец / Управляющий / Администратор / Мастер).
/// Цех — куда ставить на работы (Мойка, Химчистка…). У человека может быть несколько цехов.
///
/// Владелец платформы (`isPlatformAdmin`) — доступ ко всему, кроме скрытых dev-штук;
/// опасные действия (wipe и т.п.) — только он + PIN.
library;

import 'app_menu.dart';
import 'auth/auth_models.dart';

/// Должности компании (отображаемые имена = имена Role в API).
class JobTitles {
  JobTitles._();

  static const owner = 'Владелец';
  static const manager = 'Управляющий';
  static const admin = 'Администратор';
  static const master = 'Мастер';

  /// Старое имя роли в сиде — считаем админом.
  static const legacyCompanyAdmin = 'Администратор компании';

  static const all = [owner, manager, admin, master];

  /// Полный доступ к студии (не platform-dev).
  static const fullAccess = {owner, manager, admin, legacyCompanyAdmin};
}

/// Уровень для UI панели связи / назначения.
enum AccessRank {
  /// Владелец приложения (platform admin).
  platformOwner,
  /// Владелец / управляющий / админ студии.
  studioFull,
  /// Мастер и прочие.
  master,
  /// Не вошёл.
  guest,
}

AccessRank accessRankOf(AuthUser? user) {
  if (user == null) return AccessRank.guest;
  if (user.isPlatformAdmin) return AccessRank.platformOwner;
  for (final r in user.roles) {
    if (JobTitles.fullAccess.contains(r)) return AccessRank.studioFull;
  }
  // Права users.manage / company.manage тоже = полный доступ.
  final perms = user.permissions.toSet();
  if (perms.contains('users.manage') ||
      perms.contains('company.manage') ||
      perms.contains('roles.manage')) {
    return AccessRank.studioFull;
  }
  return AccessRank.master;
}

bool canManageAssignments(AccessRank rank) =>
    rank == AccessRank.platformOwner || rank == AccessRank.studioFull;

bool canSeeConnectionExtras(AccessRank rank) => canManageAssignments(rank);

/// Мастер студии (не владелец/админ).
bool isStudioMaster(AuthUser? user) =>
    accessRankOf(user) == AccessRank.master;

bool userHasPermission(AuthUser? user, String code) {
  if (user == null) return false;
  if (user.isPlatformAdmin) return true;
  return user.permissions.contains(code);
}

/// Пункты меню, скрытые у мастера.
const Set<int> kMasterHiddenMenuIds = {
  AppMenuIds.newOrder,
  AppMenuIds.clients,
  AppMenuIds.cash,
  AppMenuIds.stats,
  AppMenuIds.staff,
  AppMenuIds.services,
  AppMenuIds.preview,
};

/// PIN владельца приложения для необратимых действий (wipe и т.п.).
const kOwnerDestructivePin = '9294';
