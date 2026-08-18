/// Пункты главного меню. Индексы стабильны (не позиция в отфильтрованном списке).
class AppMenuIds {
  AppMenuIds._();

  static const board = 0;
  static const newOrder = 1;
  static const calendar = 2;
  static const clients = 3;
  static const cash = 4;
  static const stats = 5;
  static const staff = 6;
  static const inventory = 7;
  static const preview = 8;
  static const completed = 9;
  /// Прайс и рецепты (отдельно от склада).
  static const services = 10;
  /// Облачные заказы (C1) — REST, без LAN.
  static const cloudOrders = 11;
  /// Облачная касса (C2).
  static const cloudCash = 12;
  static const workshop = 100;

  /// На облегчённом телефоне (ПК + мобилка) эти экраны только на десктопе.
  static const lightHidden = {stats, staff, inventory, services, preview};

  /// Пункты меню без перехода (заглушка).
  static const disabled = {preview};

  static const settingKey = 'mobile_menu_mode';
  static const modeLight = 'light';
  static const modeFull = 'full';
}
