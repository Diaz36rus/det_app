import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'access_model.dart';
import 'app_theme.dart';
import 'auth/auth_models.dart';
import 'auth/company_api.dart';

/// Диалог создания филиала. Возвращает имя или null.
class CreateBranchDialog extends StatefulWidget {
  const CreateBranchDialog({super.key});

  @override
  State<CreateBranchDialog> createState() => _CreateBranchDialogState();
}

class _CreateBranchDialogState extends State<CreateBranchDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Новый филиал', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16)),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Название филиала', isDense: true),
        onSubmitted: (v) {
          if (v.trim().length >= 2) Navigator.pop(context, v.trim());
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            final t = _ctrl.text.trim();
            if (t.length < 2) return;
            Navigator.pop(context, t);
          },
          child: const Text('Создать'),
        ),
      ],
    );
  }
}

/// Создание сотрудника студии.
class CreateStaffDialog extends StatefulWidget {
  const CreateStaffDialog({super.key, required this.accessToken});

  final String accessToken;

  @override
  State<CreateStaffDialog> createState() => _CreateStaffDialogState();
}

class _CreateStaffDialogState extends State<CreateStaffDialog> {
  final _api = CompanyApi();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  List<CompanyRole> _roles = const [];
  List<CompanyBranch> _branches = const [];
  List<String> _workshops = const [];
  final Set<String> _pickedRoles = {};
  final Set<String> _pickedWorkshops = {};
  int? _branchId;

  @override
  void initState() {
    super.initState();
    _pickedRoles.add(JobTitles.admin);
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final roles = await _api.listRoles(accessToken: widget.accessToken);
      final branches = await _api.listBranches(accessToken: widget.accessToken);
      final workshops = await _api.listWorkshops(accessToken: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _roles = roles
            .where((r) => JobTitles.all.contains(r.name) || r.name == JobTitles.legacyCompanyAdmin)
            .toList();
        if (_roles.isEmpty) _roles = roles;
        _branches = branches;
        _workshops = workshops;
        _branchId = branches.isNotEmpty ? branches.first.id : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (name.isEmpty) {
      setState(() => _error = 'Укажите ФИО');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Укажите корректный email');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Пароль не короче 6 символов');
      return;
    }
    if (_pickedRoles.isEmpty) {
      setState(() => _error = 'Выберите должность');
      return;
    }
    if (_branchId == null) {
      setState(() => _error = 'Выберите филиал');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await _api.createUser(
        accessToken: widget.accessToken,
        email: email,
        password: pass,
        fullName: name,
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        roleNames: _pickedRoles.toList(),
        branchIds: [_branchId!],
        workshops: _pickedWorkshops.toList(),
      );
      if (!mounted) return;
      Navigator.pop(context, created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Новый сотрудник',
        style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'ФИО', isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email (логин)', isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Телефон (необязательно)', isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Временный пароль',
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Должность',
                style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _roles.map((r) {
                  final on = _pickedRoles.contains(r.name);
                  return FilterChip(
                    label: Text(r.name),
                    selected: on,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _pickedRoles.add(r.name);
                      } else {
                        _pickedRoles.remove(r.name);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Text(
                'Филиал',
                style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if (_branches.isEmpty)
                Text(
                  'Филиалы не загружены',
                  style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                )
              else
                DropdownButtonFormField<int>(
                  initialValue: _branchId,
                  items: _branches
                      .map((b) => DropdownMenuItem(value: b.id, child: Text(b.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _branchId = v),
                ),
              const SizedBox(height: 14),
              Text(
                'Цех (для мастера, можно несколько)',
                style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _workshops.map((w) {
                  final on = _pickedWorkshops.contains(w);
                  return FilterChip(
                    label: Text(w),
                    selected: on,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _pickedWorkshops.add(w);
                      } else {
                        _pickedWorkshops.remove(w);
                      }
                    }),
                  );
                }).toList(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: GoogleFonts.manrope(color: Colors.redAccent, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Создать'),
        ),
      ],
    );
  }
}

/// Назначение роли / филиала / цехов пользователю.
class AssignUserDialog extends StatefulWidget {
  const AssignUserDialog({super.key, required this.user, required this.accessToken});

  final AuthUser user;
  final String accessToken;

  @override
  State<AssignUserDialog> createState() => _AssignUserDialogState();
}

class _AssignUserDialogState extends State<AssignUserDialog> {
  final _api = CompanyApi();
  bool _busy = false;
  String? _error;
  List<CompanyRole> _roles = const [];
  List<CompanyBranch> _branches = const [];
  List<String> _workshops = const [];
  final Set<String> _pickedRoles = {};
  final Set<String> _pickedWorkshops = {};
  int? _branchId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final roles = await _api.listRoles(accessToken: widget.accessToken);
      final branches = await _api.listBranches(accessToken: widget.accessToken);
      final workshops = await _api.listWorkshops(accessToken: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _roles = roles
            .where((r) => JobTitles.all.contains(r.name) || r.name == JobTitles.legacyCompanyAdmin)
            .toList();
        if (_roles.isEmpty) _roles = roles;
        _branches = branches;
        _workshops = workshops;
        _branchId = branches.isNotEmpty ? branches.first.id : null;
        _pickedRoles.add(JobTitles.master);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _save() async {
    if (_pickedRoles.isEmpty) {
      setState(() => _error = 'Выберите должность');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.assignUser(
        accessToken: widget.accessToken,
        userId: widget.user.id,
        roleNames: _pickedRoles.toList(),
        branchIds: _branchId != null ? [_branchId!] : const [],
        workshops: _pickedWorkshops.toList(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Назначить · ${widget.user.displayLabel}',
        style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 16),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Должность',
                style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _roles.map((r) {
                  final on = _pickedRoles.contains(r.name);
                  return FilterChip(
                    label: Text(r.name),
                    selected: on,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _pickedRoles.add(r.name);
                      } else {
                        _pickedRoles.remove(r.name);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Text(
                'Цех (можно несколько)',
                style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _workshops.map((w) {
                  final on = _pickedWorkshops.contains(w);
                  return FilterChip(
                    label: Text(w),
                    selected: on,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _pickedWorkshops.add(w);
                      } else {
                        _pickedWorkshops.remove(w);
                      }
                    }),
                  );
                }).toList(),
              ),
              if (_branches.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Филиал',
                  style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  initialValue: _branchId,
                  items: _branches
                      .map((b) => DropdownMenuItem(value: b.id, child: Text(b.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _branchId = v),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: GoogleFonts.manrope(color: Colors.redAccent, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}
