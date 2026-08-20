import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'app_toast.dart';
import 'database.dart';

/// Мастера, чья роль подходит цеху (без уже выбранных «чужих»).
List<Map<String, dynamic>> mastersForWorkshop(
  List<Map<String, dynamic>> masters,
  String workshop,
) {
  final ws = workshop.trim();
  if (ws.isEmpty) return const [];
  return masters
      .where((m) => masterRoleFitsWorkshop(m['role']?.toString(), ws))
      .toList();
}

/// Уникальные цеха из списка, для которых нет ни одного подходящего мастера.
List<String> workshopsWithoutMasters(
  Iterable<String?> workshops,
  List<Map<String, dynamic>> masters,
) {
  final seen = <String>{};
  final missing = <String>[];
  for (final raw in workshops) {
    final ws = (raw ?? '').trim();
    if (ws.isEmpty || !WORKSHOPS.contains(ws) || !seen.add(ws)) continue;
    if (mastersForWorkshop(masters, ws).isEmpty) missing.add(ws);
  }
  return missing;
}

String missingMastersMessage(List<String> workshops) {
  if (workshops.isEmpty) return '';
  if (workshops.length == 1) {
    return 'Нет мастера на цех «${workshops.first}» — назначьте вручную.';
  }
  return 'Нет мастера на цеха: ${workshops.map((w) => '«$w»').join(', ')} — назначьте вручную.';
}

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

  if (filtered.isEmpty) {
    showAppToast(context, missingMastersMessage([workshop]));
  }

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
                      "${missingMastersMessage([workshop])}\nДобавьте сотрудников в разделе «Сотрудники».",
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

/// Одиночный выбор сотрудника (админ / приёмщик). `null` в результате — отмена;
/// пустой список `[]` — снять назначение.
Future<List<int>?> pickOrderStaff(
  BuildContext context, {
  required String title,
  required List<Map<String, dynamic>> candidates,
  int? currentId,
  String emptyHint = 'Нет подходящих сотрудников',
}) async {
  return showDialog<List<int>>(
    context: context,
    builder: (context) {
      int? selected = currentId;
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(title, style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
            content: SizedBox(
              width: 320,
              child: candidates.isEmpty
                  ? Text(
                      emptyHint,
                      style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.35),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        RadioListTile<int?>(
                          value: null,
                          groupValue: selected,
                          title: Text(
                            'Не назначен',
                            style: GoogleFonts.manrope(color: AppColors.textDim),
                          ),
                          onChanged: (v) => setDialogState(() => selected = v),
                        ),
                        ...candidates.map((m) {
                          final id = (m['id'] as num).toInt();
                          final name = m['name']?.toString() ?? '';
                          final role = m['role']?.toString() ?? '';
                          return RadioListTile<int?>(
                            value: id,
                            groupValue: selected,
                            title: Text(name, style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              role,
                              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                            ),
                            onChanged: (v) => setDialogState(() => selected = v),
                          );
                        }),
                      ],
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
              ElevatedButton(
                onPressed: () => Navigator.pop(
                  context,
                  selected == null ? <int>[] : <int>[selected!],
                ),
                child: const Text('Готово'),
              ),
            ],
          );
        },
      );
    },
  );
}
