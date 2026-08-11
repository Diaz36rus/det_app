import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'database.dart';
import 'work_order_pdf.dart';

/// Открыть превью заказ-наряда по id (с доски / долгов).
class WorkOrderActions {
  WorkOrderActions._();

  static Future<void> previewByOrderId(BuildContext context, int orderId) async {
    final order = await DatabaseHelper().getOrderById(orderId);
    if (order == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Заказ не найден', style: GoogleFonts.manrope()),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final items = await DatabaseHelper().getOrderItems(orderId);
    final masters = await DatabaseHelper().getAllMastersFull();
    if (!context.mounted) return;
    try {
      await WorkOrderPdf.showPreview(
        context,
        order: order,
        items: items,
        masters: masters,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось открыть превью: $e', style: GoogleFonts.manrope()),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
