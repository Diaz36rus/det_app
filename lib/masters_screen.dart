import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';
import 'database.dart';
import 'pulse_anchor.dart';
import 'responsive.dart';

class MastersScreen extends StatefulWidget {
  const MastersScreen({super.key});

  @override
  State<MastersScreen> createState() => _MastersScreenState();
}

class _MastersScreenState extends State<MastersScreen> with PulseHighlightMixin {
  List<Map<String, dynamic>> _masters = [];
  List<String> _roles = [];
  final _nameController = TextEditingController();
  String _selectedRole = "Универсал";
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
      if (_roles.isNotEmpty && !_roles.contains(_selectedRole)) {
        _selectedRole = _roles.first;
      }
      _isLoading = false;
    });
  }

  Future<void> _addMaster() async {
    if (_nameController.text.trim().isEmpty) return;
    await DatabaseHelper().addMaster(_nameController.text.trim(), _selectedRole);
    _nameController.clear();
    _loadData();
  }

  Future<void> _changeRole(Map<String, dynamic> master, String? role) async {
    if (role == null || role == master['role']) return;
    await DatabaseHelper().updateMaster((master['id'] as num).toInt(), role: role);
    _loadData();
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

  Widget _buildToolbar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(AppResponsive.isMobile(context) ? 12 : 24, 0, AppResponsive.isMobile(context) ? 12 : 24, 12),
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
              Text(
                "НОВЫЙ СОТРУДНИК",
                style: AppTheme.sectionLabel,
              ),
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
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: "Имя", isDense: true),
                  onSubmitted: (_) => _addMaster(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _roles.contains(_selectedRole) ? _selectedRole : null,
                  decoration: const InputDecoration(labelText: "Роль", isDense: true),
                  dropdownColor: AppColors.surface2,
                  items: _roles
                      .map(
                        (r) => DropdownMenuItem(
                          value: r,
                          child: Text(r, style: GoogleFonts.manrope(color: AppColors.text)),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedRole = val);
                  },
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _addMaster,
                child: Text("Добавить", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _buildMasterCard(Map<String, dynamic> m) {
    final role = m['role']?.toString() ?? "";
    final roleOptions = [
      if (role.isNotEmpty && !_roles.contains(role)) role,
      ..._roles,
    ];
    final roleValue = roleOptions.contains(role) ? role : null;
    final masterId = (m['id'] as num).toInt();

    return PulseAnchor(
      active: isPulseActive(masterId),
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2.withOpacity(0.92),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border(
          left: BorderSide(color: AppColors.primary.withOpacity(0.8), width: 3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
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
                      DropdownButtonFormField<String>(
                        value: roleValue,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: "Роль",
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        dropdownColor: AppColors.surface2,
                        items: roleOptions
                            .map(
                              (r) => DropdownMenuItem(
                                value: r,
                                child: Text(r, style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13)),
                              ),
                            )
                            .toList(),
                        onChanged: (val) => _changeRole(m, val),
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(AppResponsive.isMobile(context) ? 12 : 24, AppResponsive.isMobile(context) ? 12 : 24, AppResponsive.isMobile(context) ? 12 : 24, 16),
            child: Row(
              children: [
                Text("Сотрудники", style: AppTheme.pageTitle),
                const Spacer(),
                Text(
                  "${_masters.length}",
                  style: GoogleFonts.manrope(
                    color: AppColors.textDim,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _buildToolbar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _masters.isEmpty
                    ? Center(
                        child: Text(
                          "Нет сотрудников",
                          style: GoogleFonts.manrope(color: AppColors.textDim),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(AppResponsive.isMobile(context) ? 12 : 24, 0, AppResponsive.isMobile(context) ? 12 : 24, 24),
                        itemCount: _masters.length,
                        itemBuilder: (context, index) => _buildMasterCard(_masters[index]),
                      ),
          ),
        ],
      ),
    );
  }
}
