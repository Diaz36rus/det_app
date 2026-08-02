import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'database.dart';

/// Multi-select мастеров для цеха. Возвращает выбранные id или `null` при отмене.
Future<List<int>?> pickWorkshopMasters(
  BuildContext context, {
  required String workshop,
  required List<Map<String, dynamic>> masters,
  List<int> initialIds = const [],
}) async {
  final currentIds = List<int>.from(initialIds);

  final filtered = masters.where((m) {
    final mId = (m['id'] as num).toInt();
    if (currentIds.contains(mId)) return true;
    return masterRoleFitsWorkshop(m['role']?.toString(), workshop);
  }).toList();

  return showDialog<List<int>>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(
              "Мастера цеха · $workshop",
              style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
            ),
            content: SizedBox(
              width: 300,
              child: filtered.isEmpty
                  ? Text(
                      "Нет мастеров с ролью для цеха «$workshop».\nДобавь их в разделе Сотрудники.",
                      style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.35),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: filtered.map((m) {
                        final mId = (m['id'] as num).toInt();
                        final isSelected = currentIds.contains(mId);
                        final role = m['role']?.toString() ?? "";
                        final fits = masterRoleFitsWorkshop(role, workshop);
                        return CheckboxListTile(
                          title: Text(m['name'], style: GoogleFonts.manrope(color: AppColors.text)),
                          subtitle: Text(
                            fits ? role : "$role (не по цеху)",
                            style: GoogleFonts.manrope(
                              color: fits ? AppColors.textDim : AppColors.danger,
                              fontSize: 12,
                            ),
                          ),
                          value: isSelected,
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                currentIds.add(mId);
                              } else {
                                currentIds.remove(mId);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Отмена"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, List<int>.from(currentIds)),
                child: const Text("Назначить"),
              ),
            ],
          );
        },
      );
    },
  );
}

String masterNamesFromIds(List<Map<String, dynamic>> masters, List<int> ids) {
  return ids.map((id) {
    final found = masters.where((m) => (m['id'] as num).toInt() == id).toList();
    return found.isNotEmpty ? found.first['name']?.toString() ?? '' : '';
  }).where((n) => n.isNotEmpty).join(', ');
}

List<int> parseMasterIds(dynamic raw) {
  if (raw == null) return [];
  final s = raw.toString().trim();
  if (s.isEmpty) return [];
  return s
      .split(',')
      .map((e) => int.tryParse(e.trim()))
      .whereType<int>()
      .toList();
}
