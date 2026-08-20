import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_theme.dart';
import 'auth_api.dart';
import 'auth_controller.dart';

enum _WelcomeMode { home, login, createStudio, invited }

/// Тестовый онбординг: вход / создать студию / меня пригласили.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  _WelcomeMode _mode = _WelcomeMode.home;
  bool _busy = false;
  bool _obscure = true;

  final _loginCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  final _studioNameCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  final _branchCtrl = TextEditingController(text: 'Основной филиал');
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _slugTouched = false;

  final _inviteSlugCtrl = TextEditingController();
  StudioLookup? _lookup;
  String? _lookupError;

  @override
  void dispose() {
    _loginCtrl.dispose();
    _passCtrl.dispose();
    _studioNameCtrl.dispose();
    _slugCtrl.dispose();
    _branchCtrl.dispose();
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _inviteSlugCtrl.dispose();
    super.dispose();
  }

  String _slugify(String raw) {
    const map = {
      'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e', 'ж': 'zh',
      'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o',
      'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f', 'х': 'h', 'ц': 'c',
      'ч': 'ch', 'ш': 'sh', 'щ': 'sch', 'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu',
      'я': 'ya',
    };
    final buf = StringBuffer();
    for (final ch in raw.toLowerCase().runes) {
      final s = String.fromCharCode(ch);
      if (map.containsKey(s)) {
        buf.write(map[s]);
      } else if (RegExp(r'[a-z0-9]').hasMatch(s)) {
        buf.write(s);
      } else if (s == ' ' || s == '-' || s == '_') {
        buf.write('-');
      }
    }
    return buf.toString().replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.manrope()),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.danger,
      ),
    );
  }

  Future<void> _doLogin() async {
    if (_busy) return;
    if (_loginCtrl.text.trim().length < 3 || _passCtrl.text.length < 6) {
      _toast('Укажите логин и пароль (от 6 символов)');
      return;
    }
    setState(() => _busy = true);
    final ok = await AuthController.instance.login(
      login: _loginCtrl.text,
      password: _passCtrl.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) _toast(AuthController.instance.lastError ?? 'Ошибка входа');
  }

  Future<void> _doCreateStudio() async {
    if (_busy) return;
    final name = _studioNameCtrl.text.trim();
    final slug = _slugCtrl.text.trim().toLowerCase();
    final branch = _branchCtrl.text.trim();
    final fullName = _fullNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (name.length < 2 || slug.length < 2 || branch.length < 2) {
      _toast('Заполните студию, код и филиал');
      return;
    }
    if (fullName.isEmpty || !email.contains('@') || pass.length < 6) {
      _toast('ФИО, email и пароль владельца обязательны');
      return;
    }
    setState(() => _busy = true);
    final ok = await AuthController.instance.registerStudio(
      studioName: name,
      slug: slug,
      branchName: branch,
      fullName: fullName,
      email: email,
      password: pass,
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) _toast(AuthController.instance.lastError ?? 'Не удалось создать студию');
  }

  Future<void> _lookupStudio() async {
    final slug = _inviteSlugCtrl.text.trim();
    if (slug.length < 2) {
      setState(() {
        _lookup = null;
        _lookupError = 'Укажите код студии';
      });
      return;
    }
    setState(() {
      _busy = true;
      _lookupError = null;
      _lookup = null;
    });
    try {
      final s = await AuthApi().studioLookup(slug);
      if (!mounted) return;
      setState(() {
        _lookup = s;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lookupError = e.toString();
      });
    }
  }

  Future<void> _doRequestAccess() async {
    if (_busy) return;
    if (_lookup == null) {
      _toast('Сначала найдите студию по коду');
      return;
    }
    final fullName = _fullNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (fullName.isEmpty || !email.contains('@') || pass.length < 6) {
      _toast('ФИО, email и пароль обязательны');
      return;
    }
    setState(() => _busy = true);
    final ok = await AuthController.instance.requestAccess(
      companySlug: _lookup!.slug,
      fullName: fullName,
      email: email,
      password: pass,
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      _toast(AuthController.instance.lastError ?? 'Не удалось отправить заявку');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: switch (_mode) {
                _WelcomeMode.home => _buildHome(),
                _WelcomeMode.login => _buildLogin(),
                _WelcomeMode.createStudio => _buildCreateStudio(),
                _WelcomeMode.invited => _buildInvited(),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _brand() {
    return Column(
      children: [
        Text(
          'Det App',
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            color: AppColors.text,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'CRM для детейлинг-студии',
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primarySoft.withOpacity(0.55),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            'Тестовый билд · испытания',
            style: GoogleFonts.manrope(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildHome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _brand(),
        const SizedBox(height: 36),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: () => setState(() => _mode = _WelcomeMode.login),
            child: Text('Войти', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: FilledButton.tonal(
            onPressed: () => setState(() => _mode = _WelcomeMode.createStudio),
            child: Text('Создать студию', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => setState(() => _mode = _WelcomeMode.invited),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Меня пригласили', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Создать студию — вы владелец своей CRM.\n'
          'Меня пригласили — заявка в чужую студию (без роли, пока не назначат).',
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

  Widget _backRow(String title) {
    return Row(
      children: [
        IconButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _mode = _WelcomeMode.home;
                    _lookup = null;
                    _lookupError = null;
                  }),
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textMuted),
        ),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.manrope(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 17),
          ),
        ),
      ],
    );
  }

  Widget _buildLogin() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backRow('Вход'),
        const SizedBox(height: 16),
        TextField(
          controller: _loginCtrl,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email или телефон'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passCtrl,
          enabled: !_busy,
          obscureText: _obscure,
          onSubmitted: (_) => _doLogin(),
          decoration: InputDecoration(
            labelText: 'Пароль',
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            ),
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _busy ? null : _doLogin,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Войти', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateStudio() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backRow('Новая студия'),
        const SizedBox(height: 8),
        Text(
          'Вы станете владельцем студии и сможете добавлять сотрудников.',
          style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13, height: 1.35),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _studioNameCtrl,
          enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Название студии'),
          onChanged: (v) {
            if (_slugTouched) return;
            setState(() => _slugCtrl.text = _slugify(v));
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _slugCtrl,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Код студии (латиница)',
            helperText: 'Для приглашений, например my-detailing',
          ),
          onChanged: (_) => _slugTouched = true,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _branchCtrl,
          enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Первый филиал'),
        ),
        const SizedBox(height: 18),
        Text('Владелец', style: GoogleFonts.manrope(color: AppColors.textDim, fontWeight: FontWeight.w800, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          controller: _fullNameCtrl,
          enabled: !_busy,
          decoration: const InputDecoration(labelText: 'ФИО'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _emailCtrl,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email (логин)'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phoneCtrl,
          enabled: !_busy,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Телефон (необязательно)'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _passCtrl,
          enabled: !_busy,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Пароль',
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            ),
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _busy ? null : _doCreateStudio,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Создать и войти', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  Widget _buildInvited() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backRow('Меня пригласили'),
        const SizedBox(height: 8),
        Text(
          'Укажите код студии. После входа вы будете ждать назначение роли администратором.',
          style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13, height: 1.35),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inviteSlugCtrl,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Код студии', hintText: 'demo'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _busy ? null : _lookupStudio,
              child: const Text('Найти'),
            ),
          ],
        ),
        if (_lookupError != null) ...[
          const SizedBox(height: 8),
          Text(_lookupError!, style: GoogleFonts.manrope(color: AppColors.danger, fontSize: 12)),
        ],
        if (_lookup != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderSoft),
            ),
            child: Text(
              'Студия: ${_lookup!.name}\nкод: ${_lookup!.slug}',
              style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13, height: 1.35, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _fullNameCtrl,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'ФИО'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _emailCtrl,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phoneCtrl,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Телефон (необязательно)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passCtrl,
            enabled: !_busy,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Пароль',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              ),
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _busy ? null : _doRequestAccess,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Отправить заявку и войти', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ],
    );
  }
}
