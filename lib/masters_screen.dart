import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'app_toast.dart';
import 'database.dart';
import 'on_shift_controller.dart';
import 'outsourcers_panel.dart';
import 'pulse_anchor.dart';
import 'responsive.dart';
import 'tour_keys.dart';

class MastersScreen extends StatefulWidget {
  const MastersScreen({super.key});

  @override
  State<MastersScreen> createState() => _MastersScreenState();
}

class _MastersScreenState extends State<MastersScreen> with PulseHighlightMixin {
  List<Map<String, dynamic>> _masters = [];
  List<String> _roles = [];
  final _nameController = TextEditingController();
  final Set<String> _selectedRoles = {'Универсал'};
  bool _isLoading = true;

  static const _pulseToolbar = 'masters_toolbar';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final masters = await DatabaseHelper().getAllMastersFull();
    final roles = await DatabaseHelper().getRolesList();
    if (!mounted) return;
    setState(() {
      _masters = masters;
      _roles = roles;
      if (_roles.isNotEmpty && _selectedRoles.every((r) => !_roles.contains(r))) {
        _selectedRoles
          ..clear()
          ..add(_roles.first);
      }
      _isLoading = false;
    });
  }

  Future<void> _addMaster() async {
    if (_nameController.text.trim().isEmpty) return;
    if (_selectedRoles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите хотя бы одну роль')),
      );
      return;
    }
    await DatabaseHelper().addMaster(
      _nameController.text.trim(),
      joinMasterRoles(_selectedRoles),
    );
    _nameController.clear();
    _loadData();
  }

  Future<void> _setMasterRoles(Map<String, dynamic> master, List<String> roles) async {
    final joined = joinMasterRoles(roles);
    if (joined.isEmpty) return;
    if (joined == (master['role']?.toString() ?? '')) return;
    await DatabaseHelper().updateMaster((master['id'] as num).toInt(), role: joined);
    _loadData();
  }

  Future<void> _editRolesDialog(Map<String, dynamic> master) async {
    final masterId = (master['id'] as num).toInt();
    final selected = splitMasterRoles(master['role']?.toString()).toSet();
    final options = <String>[
      ...selected.where((r) => !_roles.contains(r)),
      ..._roles,
    ];
    final ok = await runWithPulseHighlight(
      masterId,
      () => showDialog<bool>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: AppColors.surface,
                title: Text(
                  "Роли · ${master['name'] ?? ''}",
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                ),
                content: SizedBox(
                  width: 340,
                  child: options.isEmpty
                      ? Text(
                          "Нет ролей. Добавьте через «Новая роль».",
                          style: GoogleFonts.manrope(color: AppColors.textMuted),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: options.map((r) {
                            final checked = selected.contains(r);
                            return CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(r, style: GoogleFonts.manrope(color: AppColors.text)),
                              value: checked,
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == true) {
                                    selected.add(r);
                                  } else {
                                    selected.remove(r);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Отмена")),
                  ElevatedButton(
                    onPressed: selected.isEmpty ? null : () => Navigator.pop(context, true),
                    child: const Text("Сохранить"),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
    if (ok == true) {
      await _setMasterRoles(master, selected.toList());
    }
  }

  Future<void> _renameMaster(Map<String, dynamic> master) async {
    final masterId = (master['id'] as num).toInt();
    final controller = TextEditingController(text: master['name']?.toString() ?? '');
    final ok = await runWithPulseHighlight(
      masterId,
      () => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text("Имя сотрудника", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: "Имя", isDense: true),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Отмена")),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Сохранить"),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final name = controller.text.trim();
    if (name.isEmpty || name == master['name']) return;
    await DatabaseHelper().updateMaster(masterId, name: name);
    _loadData();
  }

  Future<void> _showAddRoleDialog() async {
    final roleController = TextEditingController();
    await runWithPulseHighlight(
      _pulseToolbar,
      () => showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text("Новая роль", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
            content: TextField(
              controller: roleController,
              decoration: const InputDecoration(labelText: "Название роли", isDense: true),
              autofocus: true,
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Отмена")),
              ElevatedButton(
                onPressed: () async {
                  if (roleController.text.trim().isNotEmpty) {
                    await DatabaseHelper().addRole(roleController.text.trim());
                    if (context.mounted) Navigator.pop(context);
                    _loadData();
                  }
                },
                child: const Text("Добавить"),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> master) async {
    final masterId = (master['id'] as num).toInt();
    final ok = await runWithPulseHighlight(
      masterId,
      () => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text("Удалить сотрудника?", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          content: Text(
            "${master['name']} будет удалён из базы.",
            style: GoogleFonts.manrope(color: AppColors.textMuted),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Отмена")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Удалить"),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await DatabaseHelper().deleteMasterById(masterId);
        if (!mounted) return;
        _loadData();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось удалить: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Widget _roleChipWrap({
    required Iterable<String> options,
    required Set<String> selected,
    required void Function(String role, bool enable) onToggle,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((r) {
        final on = selected.contains(r);
        final color = _roleColor(r);
        return FilterChip(
          label: Text(
            r,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: on ? color : color.withOpacity(0.85),
            ),
          ),
          selected: on,
          onSelected: (val) => onToggle(r, val),
          selectedColor: color.withOpacity(0.28),
          checkmarkColor: color,
          backgroundColor: color.withOpacity(0.10),
          side: BorderSide(color: color.withOpacity(on ? 0.75 : 0.4)),
          showCheckmark: true,
        );
      }).toList(),
    );
  }

  Widget _buildToolbar({bool compactRoles = false}) {
    final mobile = AppResponsive.isMobile(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(mobile ? 12 : 24, 0, mobile ? 12 : 24, 12),
      child: PulseAnchor(
        active: isPulseActive(_pulseToolbar),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.panelDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text("НОВЫЙ СОТРУДНИК", style: AppTheme.sectionLabel),
                  const Spacer(),
                  TextButton(
                    onPressed: _showAddRoleDialog,
                    child: Text(
                      "Новая роль",
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "Имя", isDense: true),
                onSubmitted: (_) => _addMaster(),
              ),
              const SizedBox(height: 12),
              if (compactRoles)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 4),
                    initiallyExpanded: false,
                    title: Text(
                      'Роли (${_selectedRoles.length})',
                      style: GoogleFonts.manrope(
                        color: AppColors.textDim,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      _selectedRoles.isEmpty
                          ? 'не выбраны'
                          : _selectedRoles.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 11),
                    ),
                    children: [
                      _roleChipWrap(
                        options: _roles,
                        selected: _selectedRoles,
                        onToggle: (r, enable) {
                          setState(() {
                            if (enable) {
                              _selectedRoles.add(r);
                            } else {
                              _selectedRoles.remove(r);
                            }
                          });
                        },
                      ),
                    ],
                  ),
                )
              else ...[
                Text(
                  "Роли (можно несколько)",
                  style: GoogleFonts.manrope(
                    color: AppColors.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _roleChipWrap(
                  options: _roles,
                  selected: _selectedRoles,
                  onToggle: (r, enable) {
                    setState(() {
                      if (enable) {
                        _selectedRoles.add(r);
                      } else {
                        _selectedRoles.remove(r);
                      }
                    });
                  },
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _addMaster,
                  child: Text("Добавить", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _roleColor(String role) {
    return kOrderStatusColors[role] ?? AppColors.primary;
  }

  Color _masterAccent(List<String> roles) {
    for (final r in roles) {
      final c = kOrderStatusColors[r];
      if (c != null) return c;
    }
    return AppColors.primary;
  }

  Widget _buildMasterCard(Map<String, dynamic> m) {
    final roles = splitMasterRoles(m['role']?.toString());
    final masterId = (m['id'] as num).toInt();
    final accent = _masterAccent(roles);
    final onShift = m['on_shift'] == true || m['on_shift'] == 1;

    return PulseAnchor(
      active: isPulseActive(masterId),
      accent: accent,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.surface2.withOpacity(0.92),
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(color: accent.withOpacity(0.45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: ColoredBox(color: accent),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => _renameMaster(m),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    m['name']?.toString() ?? "",
                                    style: GoogleFonts.manrope(
                                      color: AppColors.text,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.edit_outlined, size: 16, color: AppColors.textDim),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (roles.isEmpty)
                          Text(
                            "Роль не задана",
                            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                          )
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: roles.map((r) {
                              final color = _roleColor(r);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(AppTheme.radius),
                                  border: Border.all(color: color.withOpacity(0.45)),
                                ),
                                child: Text(
                                  r,
                                  style: GoogleFonts.manrope(
                                    color: color,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: onShift ? AppColors.success : AppColors.textDim,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              onShift ? 'На смене' : 'Не на смене',
                              style: GoogleFonts.manrope(
                                color: onShift ? AppColors.success : AppColors.textMuted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Switch.adaptive(
                              value: onShift,
                              activeColor: AppColors.success,
                              onChanged: (v) async {
                                final err =
                                    await OnShiftController.instance.setMasterOnShift(masterId, v);
                                if (!mounted) return;
                                if (err != null) {
                                  showAppToast(context, err);
                                } else {
                                  await _loadData();
                                }
                              },
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: () => _editRolesDialog(m),
                          icon: Icon(Icons.badge_outlined, size: 16, color: accent),
                          label: Text(
                            "Роли",
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: "Удалить",
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 22),
                    onPressed: () => _confirmDelete(m),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = AppResponsive.isMobile(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: KeyedSubtree(
          key: TourKeys.staffArea,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(mobile ? 12 : 24, mobile ? 12 : 20, mobile ? 12 : 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Сотрудники', style: AppTheme.pageTitle),
                    const SizedBox(height: 4),
                    Text('Мастера цехов и подрядчики (аутсорс)', style: AppTheme.pageSubtitle),
                    const SizedBox(height: 10),
                    TabBar(
                      labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 13.5),
                      unselectedLabelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13.5),
                      labelColor: AppColors.primary,
                      unselectedLabelColor: AppColors.textDim,
                      indicatorColor: AppColors.primary,
                      tabs: const [
                        Tab(text: 'Штат'),
                        Tab(text: 'Аутсорс'),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _staffTab(mobile: mobile),
                    const OutsourcersPanel(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _staffTab({required bool mobile}) {
    if (mobile) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          _buildToolbar(compactRoles: true),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_masters.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
              child: Text(
                'Пока нет сотрудников — добавьте первого выше',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(color: AppColors.textMuted),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: Column(
                children: [
                  for (final m in _masters) _buildMasterCard(m),
                ],
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _masters.isEmpty
                  ? Center(
                      child: Text(
                        'Пока нет сотрудников',
                        style: GoogleFonts.manrope(color: AppColors.textMuted),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      itemCount: _masters.length,
                      itemBuilder: (context, index) => _buildMasterCard(_masters[index]),
                    ),
        ),
      ],
    );
  }
}
