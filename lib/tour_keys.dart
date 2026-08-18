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

  /// Карточка заказа (OrderDetailsDialog).
  static final orderDetailsHeader = GlobalKey(debugLabel: 'tour_od_header');
  static final orderDetailsWorks = GlobalKey(debugLabel: 'tour_od_works');
  static final orderDetailsSchedule = GlobalKey(debugLabel: 'tour_od_schedule');
  static final orderDetailsNotes = GlobalKey(debugLabel: 'tour_od_notes');
  static final orderDetailsPayment = GlobalKey(debugLabel: 'tour_od_payment');

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
