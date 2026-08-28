import 'package:flutter/material.dart';

import 'app_menu.dart';

/// GlobalKey для подсветки элементов в обучении.
class TourKeys {
  static final search = GlobalKey(debugLabel: 'tour_search');
  static final workshops = GlobalKey(debugLabel: 'tour_workshops');
  static final menuBoard = GlobalKey(debugLabel: 'tour_menu_board');
  static final menuNewOrder = GlobalKey(debugLabel: 'tour_menu_new_order');
  static final menuCalendar = GlobalKey(debugLabel: 'tour_menu_calendar');
  static final menuClients = GlobalKey(debugLabel: 'tour_menu_clients');
  static final menuCash = GlobalKey(debugLabel: 'tour_menu_cash');
  static final menuStats = GlobalKey(debugLabel: 'tour_menu_stats');
  static final menuStaff = GlobalKey(debugLabel: 'tour_menu_staff');
  static final menuServices = GlobalKey(debugLabel: 'tour_menu_services');
  static final menuInventory = GlobalKey(debugLabel: 'tour_menu_inventory');
  static final menuCalc = GlobalKey(debugLabel: 'tour_menu_calc');
  static final menuCompleted = GlobalKey(debugLabel: 'tour_menu_completed');
  static final quickCalendar = GlobalKey(debugLabel: 'tour_quick_calendar');
  static final trainButton = GlobalKey(debugLabel: 'tour_train');
  static final bugReport = GlobalKey(debugLabel: 'tour_bug_report');

  static final orderClient = GlobalKey(debugLabel: 'tour_order_client');
  static final orderSchedule = GlobalKey(debugLabel: 'tour_order_schedule');
  static final orderGallery = GlobalKey(debugLabel: 'tour_order_gallery');
  static final orderCart = GlobalKey(debugLabel: 'tour_order_cart');

  static final cashKpi = GlobalKey(debugLabel: 'tour_cash_kpi');
  static final cashShift = GlobalKey(debugLabel: 'tour_cash_shift');
  static final cashTemplates = GlobalKey(debugLabel: 'tour_cash_templates');
  static final cashJournal = GlobalKey(debugLabel: 'tour_cash_journal');

  static final kanbanArea = GlobalKey(debugLabel: 'tour_kanban');
  static final kanbanSearch = GlobalKey(debugLabel: 'tour_kanban_search');
  static final kanbanStatusFilter = GlobalKey(debugLabel: 'tour_kanban_status');
  static final kanbanDebtFilter = GlobalKey(debugLabel: 'tour_kanban_debt');
  static final kanbanTodayFilter = GlobalKey(debugLabel: 'tour_kanban_today');
  static final updateButton = GlobalKey(debugLabel: 'tour_update');

  /// Карточка заказа (OrderDetailsDialog).
  static final orderDetailsHeader = GlobalKey(debugLabel: 'tour_od_header');
  static final orderDetailsWorks = GlobalKey(debugLabel: 'tour_od_works');
  static final orderDetailsSchedule = GlobalKey(debugLabel: 'tour_od_schedule');
  static final orderDetailsNotes = GlobalKey(debugLabel: 'tour_od_notes');
  static final orderDetailsPayment = GlobalKey(debugLabel: 'tour_od_payment');

  static final calendarArea = GlobalKey(debugLabel: 'tour_calendar');
  static final calendarMode = GlobalKey(debugLabel: 'tour_calendar_mode');
  static final clientsArea = GlobalKey(debugLabel: 'tour_clients');
  static final warehouseArea = GlobalKey(debugLabel: 'tour_warehouse');
  static final warehouseAdd = GlobalKey(debugLabel: 'tour_warehouse_add');
  static final completedArea = GlobalKey(debugLabel: 'tour_completed');
  static final statsArea = GlobalKey(debugLabel: 'tour_stats');
  static final staffArea = GlobalKey(debugLabel: 'tour_staff');
  static final servicesArea = GlobalKey(debugLabel: 'tour_services');
  static final mobileModeButton = GlobalKey(debugLabel: 'tour_mobile_mode');
  static final menuDrawerHint = GlobalKey(debugLabel: 'tour_drawer_hint');

  static GlobalKey? menuKeyForIndex(int id) {
    switch (id) {
      case AppMenuIds.board:
        return menuBoard;
      case AppMenuIds.newOrder:
        return menuNewOrder;
      case AppMenuIds.calendar:
        return menuCalendar;
      case AppMenuIds.clients:
        return menuClients;
      case AppMenuIds.cash:
        return menuCash;
      case AppMenuIds.stats:
        return menuStats;
      case AppMenuIds.staff:
        return menuStaff;
      case AppMenuIds.services:
        return menuServices;
      case AppMenuIds.inventory:
        return menuInventory;
      case AppMenuIds.preview:
        return menuCalc;
      case AppMenuIds.completed:
        return menuCompleted;
      case AppMenuIds.cloudOrders:
        return null;
      case AppMenuIds.cloudCash:
        return null;
      default:
        return null;
    }
  }
}
