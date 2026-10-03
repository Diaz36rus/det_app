import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'access_model.dart';
import 'app_datetime.dart';
import 'app_menu.dart';
import 'app_theme.dart';
import 'app_toast.dart';
import 'auth/auth_api.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_models.dart';
import 'auth/company_api.dart';
import 'backup_helper.dart';
import 'database.dart';
import 'owner_pin.dart';
import 'responsive.dart';
import 'showcase_seed.dart';
import 'studio_access_dialogs.dart';
import 'studio_prefs.dart';
import 'sync/sync_qr.dart';

/// Настройки студии: список секций с живым функционалом.
class StudioSettingsScreen extends StatefulWidget {
  const StudioSettingsScreen({super.key});

  @override
  State<StudioSettingsScreen> createState() => _StudioSettingsScreenState();
}

class _StudioSettingsScreenState extends State<StudioSettingsScreen> {
  final _api = CompanyApi();
  final _authApi = AuthApi();

  String? _openId;
  bool _loadingCloud = false;
  String? _cloudError;
  bool _showcaseBusy = false;

  String? _studioName;
  List<CompanyBranch> _branches = const [];
  List<AuthUser> _pending = const [];
  List<AuthUser> _users = const [];
  List<String> _cloudWorkshops = const [];

  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _waCtrl = TextEditingController();
  final _siteCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _tplBookingCtrl = TextEditingController();
  final _tplDebtCtrl = TextEditingController();
  final _tplReadyCtrl = TextEditingController();
  String _clientMsgChannel = 'ask';

  int _startHour = StudioPrefs.defaultStartHour;
  int _endHour = StudioPrefs.defaultEndHour;
  int? _defaultBranchId;
  int? _defaultCashId;
  List<Map<String, dynamic>> _cashRegisters = const [];
  bool _mobileFull = false;
  DateTime? _lastBackup;
  bool _savingContacts = false;
  bool _savingTemplates = false;
  bool _savingProfile = false;
  String? _logoPath;

  @override
  void initState() {
    super.initState();
    _loadLocal();
    _loadCloud();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _waCtrl.dispose();
    _siteCtrl.dispose();
    _nameCtrl.dispose();
    _tplBookingCtrl.dispose();
    _tplDebtCtrl.dispose();
    _tplReadyCtrl.dispose();
    super.dispose();
  }

  void _toggle(String id) => setState(() => _openId = _openId == id ? null : id);

  Future<void> _loadLocal() async {
    final contacts = await StudioPrefs.loadContacts();
    final hours = await StudioPrefs.loadCalendarHours();
    final branchId = await StudioPrefs.loadDefaultBranchId();
    final cashId = await StudioPrefs.loadDefaultCashRegisterId();
    final tpls = await StudioPrefs.loadMessageTemplates();
    final msgChannel = await StudioPrefs.loadClientMsgChannel();
    final menu = await DatabaseHelper().getAppSetting(AppMenuIds.settingKey);
    final regs = await DatabaseHelper().getCashRegisters();
    final backup = await BackupHelper.lastBackupAt();
    final logo = await StudioPrefs.loadLogoPath();
    if (!mounted) return;
    setState(() {
      _phoneCtrl.text = contacts['phone'] ?? '';
      _addressCtrl.text = contacts['address'] ?? '';
      _waCtrl.text = contacts['whatsapp'] ?? '';
      _siteCtrl.text = contacts['website'] ?? '';
      _startHour = hours.$1;
      _endHour = hours.$2;
      _defaultBranchId = branchId;
      _defaultCashId = cashId;
      _tplBookingCtrl.text = tpls['booking'] ?? '';
      _tplDebtCtrl.text = tpls['debt'] ?? '';
      _tplReadyCtrl.text = tpls['ready'] ?? '';
      _clientMsgChannel = msgChannel;
      _mobileFull = menu == AppMenuIds.modeFull;
      _cashRegisters = regs;
      _lastBackup = backup;
      _logoPath = logo;
    });
  }

  Future<void> _loadCloud() async {
    final user = AuthController.instance.user;
    final token = AuthController.instance.accessToken;
    if (user == null || token == null || token.isEmpty) {
      setState(() {
        _studioName = null;
        _branches = const [];
        _pending = const [];
        _users = const [];
        _cloudError = 'Войдите в аккаунт, чтобы управлять филиалами и доступом';
      });
      return;
    }

    setState(() {
      _loadingCloud = true;
      _cloudError = null;
      _studioName = user.companyName?.trim().isNotEmpty == true
          ? user.companyName!.trim()
          : user.companySlug;
      if ((_studioName ?? '').isNotEmpty) {
        _nameCtrl.text = _studioName!;
      }
    });

    try {
      try {
        final profile = await _api.getProfile(accessToken: token);
        if (mounted && profile.name.trim().isNotEmpty) {
          setState(() {
            _studioName = profile.name.trim();
            _nameCtrl.text = profile.name.trim();
          });
        }
      } catch (_) {
        if ((user.companyName ?? '').trim().isEmpty && (user.companySlug ?? '').isNotEmpty) {
          try {
            final look = await _authApi.studioLookup(user.companySlug!);
            if (mounted && look.name.trim().isNotEmpty) {
              setState(() {
                _studioName = look.name.trim();
                _nameCtrl.text = look.name.trim();
              });
            }
          } catch (_) {}
        }
      }

      final branches = await _api.listBranches(accessToken: token);
      List<AuthUser> pending = const [];
      List<AuthUser> users = const [];
      List<String> workshops = const [];
      final rank = accessRankOf(user);
      if (canManageAssignments(rank)) {
        pending = await _api.listUsers(accessToken: token, pending: true);
        users = await _api.listUsers(accessToken: token, pending: false);
        workshops = await _api.listWorkshops(accessToken: token);
      }
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _pending = pending;
        _users = users;
        _cloudWorkshops = workshops;
        _loadingCloud = false;
        if (_defaultBranchId != null &&
            !_branches.any((b) => b.id == _defaultBranchId)) {
          _defaultBranchId = branches.isNotEmpty ? branches.first.id : null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCloud = false;
        _cloudError = e.toString();
      });
    }
  }

  String? get _inviteUrl {
    final slug = AuthController.instance.user?.companySlug?.trim().toLowerCase();
    if (slug == null || slug.length < 2) return null;
    return encodeInviteQrPayload(slug: slug, apiBase: AuthApi.defaultBaseUrl);
  }

  Future<void> _saveContacts() async {
    setState(() => _savingContacts = true);
    await StudioPrefs.saveContacts(
      phoneValue: _phoneCtrl.text,
      addressValue: _addressCtrl.text,
      whatsappValue: _waCtrl.text,
      websiteValue: _siteCtrl.text,
    );
    if (!mounted) return;
    setState(() => _savingContacts = false);
    showAppToast(context, 'Контакты сохранены');
  }

  Future<void> _saveProfile() async {
    final token = AuthController.instance.accessToken;
    if (token == null) {
      showAppToast(context, 'Нужен вход в аккаунт');
      return;
    }
    final name = _nameCtrl.text.trim();
    if (name.length < 2) {
      showAppToast(context, 'Название слишком короткое');
      return;
    }
    setState(() => _savingProfile = true);
    try {
      final profile = await _api.updateProfile(accessToken: token, name: name);
      await AuthController.instance.refreshMe();
      if (!mounted) return;
      setState(() {
        _studioName = profile.name.trim();
        _nameCtrl.text = profile.name.trim();
        _savingProfile = false;
      });
      showAppToast(context, 'Название студии обновлено');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingProfile = false);
      showAppToast(context, '$e');
    }
  }

  Future<void> _pickLogo() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 90,
      );
      if (file == null) return;
      final saved = await StudioPrefs.saveLogoFromFile(file.path);
      if (!mounted) return;
      if (saved == null) {
        showAppToast(context, 'Не удалось сохранить логотип');
        return;
      }
      setState(() => _logoPath = saved);
      showAppToast(context, 'Логотип сохранён');
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Не удалось выбрать файл: $e');
    }
  }

  Future<void> _clearLogo() async {
    await StudioPrefs.clearLogo();
    if (!mounted) return;
    setState(() => _logoPath = null);
    showAppToast(context, 'Логотип удалён');
  }

  Future<void> _saveHours() async {
    await StudioPrefs.saveCalendarHours(_startHour, _endHour);
    if (!mounted) return;
    showAppToast(context, 'График сохранён · календарь подхватит при открытии');
  }

  Future<void> _saveTemplates() async {
    setState(() => _savingTemplates = true);
    await StudioPrefs.saveMessageTemplates(
      booking: _tplBookingCtrl.text,
      debt: _tplDebtCtrl.text,
      ready: _tplReadyCtrl.text,
    );
    await StudioPrefs.saveClientMsgChannel(_clientMsgChannel);
    if (!mounted) return;
    setState(() => _savingTemplates = false);
    showAppToast(context, 'Шаблоны и канал сохранены');
  }

  Future<void> _setMobileFull(bool full) async {
    setState(() => _mobileFull = full);
    await DatabaseHelper().setAppSetting(
      AppMenuIds.settingKey,
      full ? AppMenuIds.modeFull : AppMenuIds.modeLight,
    );
    AppMenuIds.notifyMobileMenuChanged();
    if (!mounted) return;
    showAppToast(context, full ? 'Полное меню на телефоне' : 'Компактное меню на телефоне');
  }

  Future<void> _createBranch() async {
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const CreateBranchDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final b = await _api.createBranch(accessToken: token, name: name.trim());
      if (!mounted) return;
      showAppToast(context, 'Филиал создан: ${b.name}');
      await _loadCloud();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '$e');
    }
  }

  Future<void> _createStaff() async {
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    final created = await showDialog<AuthUser>(
      context: context,
      builder: (ctx) => CreateStaffDialog(accessToken: token),
    );
    if (created != null && mounted) {
      showAppToast(context, 'Создан: ${created.displayLabel}');
      await _loadCloud();
    }
  }

  Future<void> _assign(AuthUser u) async {
    final token = AuthController.instance.accessToken;
    if (token == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AssignUserDialog(user: u, accessToken: token),
    );
    if (ok == true && mounted) {
      showAppToast(context, 'Назначено: ${u.displayLabel}');
      await _loadCloud();
    }
  }

  Future<void> _backupNow() async {
    final path = await BackupHelper.forceBackupNow();
    final at = await BackupHelper.lastBackupAt();
    if (!mounted) return;
    setState(() => _lastBackup = at);
    showAppToast(context, path == null ? 'Не удалось создать бэкап' : 'Бэкап создан');
  }

  Future<void> _wipeDb() async {
    final okPin = await confirmOwnerDestructivePin(context, actionTitle: 'очистка базы');
    if (!okPin || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Очистить базу?',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: AppColors.danger),
        ),
        content: Text(
          'Заказы, клиенты, оплаты и касса будут удалены. Перед очисткой создастся бэкап.',
          style: GoogleFonts.manrope(color: AppColors.textMuted, height: 1.35),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Очистить', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await BackupHelper.forceBackupNow();
    await DatabaseHelper().resetDatabase();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        final exe = Platform.resolvedExecutable;
        await Process.start(exe, const [], mode: ProcessStartMode.detached);
        exit(0);
      } catch (_) {}
    }
    if (mounted) showAppToast(context, 'База очищена — перезапустите приложение');
  }

  @override
  Widget build(BuildContext context) {
    final mobile = AppResponsive.isMobile(context);
    final user = AuthController.instance.user;
    final studio = _studioName ?? user?.studioDisplayName ?? 'Без студии';
    final hPad = AppResponsive.pagePadH(context);
    final rank = accessRankOf(user);
    final canManage = canManageAssignments(rank);
    final isOwner = user?.isPlatformAdmin == true;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, mobile ? 14 : 20, hPad, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Студия', style: AppTheme.pageTitle),
                      const SizedBox(height: 4),
                      Text(
                        'Профиль, филиалы, доступ и рабочие настройки · $studio',
                        style: AppTheme.pageSubtitle,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Обновить',
                  onPressed: _loadingCloud ? null : () {
                    _loadLocal();
                    _loadCloud();
                  },
                  icon: _loadingCloud
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        )
                      : const Icon(Icons.refresh_rounded, color: AppColors.textDim),
                ),
              ],
            ),
          ),
          if (_cloudError != null)
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
              child: Text(
                _cloudError!,
                style: GoogleFonts.manrope(color: const Color(0xFFE8A838), fontSize: 12.5, height: 1.35),
              ),
            ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 28),
              children: [
                _groupLabel('Организация'),
                const SizedBox(height: 10),
                _section(
                  id: 'profile',
                  icon: Icons.storefront_outlined,
                  title: 'Профиль студии',
                  subtitle: 'Название, логотип, код, приглашение',
                  hint: studio,
                  body: _profileBody(user, canManage: canManage),
                ),
                const SizedBox(height: 12),
                _section(
                  id: 'contacts',
                  icon: Icons.contact_phone_outlined,
                  title: 'Контакты',
                  subtitle: 'Телефон, адрес, мессенджер, сайт',
                  hint: (_phoneCtrl.text.trim().isNotEmpty)
                      ? _phoneCtrl.text.trim()
                      : 'не заданы',
                  body: _contactsBody(),
                ),
                const SizedBox(height: 12),
                _section(
                  id: 'branches',
                  icon: Icons.apartment_outlined,
                  title: 'Филиалы',
                  subtitle: 'Список и филиал по умолчанию',
                  hint: _branches.isEmpty ? 'нет данных' : '${_branches.length}',
                  body: _branchesBody(canManage: canManage),
                ),
                const SizedBox(height: 22),
                _groupLabel('Доступ'),
                const SizedBox(height: 10),
                _section(
                  id: 'roles',
                  icon: Icons.shield_outlined,
                  title: 'Роли и права',
                  subtitle: 'Что может каждая должность',
                  hint: JobTitles.all.length.toString(),
                  body: _rolesBody(),
                ),
                const SizedBox(height: 12),
                _section(
                  id: 'people',
                  icon: Icons.group_outlined,
                  title: 'Люди и доступ',
                  subtitle: 'Заявки, пользователи, приглашения',
                  hint: canManage
                      ? '${_pending.length} заявок · ${_users.length} чел.'
                      : 'только просмотр',
                  body: _peopleBody(canManage: canManage),
                ),
                const SizedBox(height: 22),
                _groupLabel('Работа'),
                const SizedBox(height: 10),
                _section(
                  id: 'hours',
                  icon: Icons.schedule_outlined,
                  title: 'График работы',
                  subtitle: 'Часы дня для календаря',
                  hint: '${_pad(_startHour)}:00–${_pad(_endHour)}:00',
                  body: _hoursBody(),
                ),
                const SizedBox(height: 12),
                _section(
                  id: 'workshops',
                  icon: Icons.handyman_outlined,
                  title: 'Цеха',
                  subtitle: 'Рабочие зоны студии',
                  hint: '${(_cloudWorkshops.isNotEmpty ? _cloudWorkshops : WORKSHOPS).length}',
                  body: _workshopsBody(),
                ),
                const SizedBox(height: 12),
                _section(
                  id: 'templates',
                  icon: Icons.chat_outlined,
                  title: 'Шаблоны сообщений',
                  subtitle: 'Запись, долг, «готово к выдаче»',
                  hint: 'Telegram / WhatsApp / SMS',
                  body: _templatesBody(),
                ),
                const SizedBox(height: 12),
                _section(
                  id: 'payroll_rules',
                  icon: Icons.calculate_outlined,
                  title: 'Правила ЗП',
                  subtitle: 'Для кнопки «Рассчитать» в заказе',
                  hint: 'цех / %',
                  body: _payrollRulesBody(),
                ),
                const SizedBox(height: 12),
                _section(
                  id: 'booking',
                  icon: Icons.link_outlined,
                  title: 'Онлайн-запись и API',
                  subtitle: 'Публичная ссылка и webhooks',
                  hint: 'R3 / R7',
                  body: _bookingApiBody(),
                ),
                const SizedBox(height: 12),
                _section(
                  id: 'pdf',
                  icon: Icons.picture_as_pdf_outlined,
                  title: 'Печать / PDF',
                  subtitle: 'Шапка бланка берётся из профиля и контактов',
                  hint: studio,
                  body: _pdfBody(studio),
                ),
                const SizedBox(height: 12),
                _section(
                  id: 'cash',
                  icon: Icons.point_of_sale_outlined,
                  title: 'Касса по умолчанию',
                  subtitle: 'Какая касса при оплате',
                  hint: _cashHint(),
                  body: _cashBody(),
                ),
                const SizedBox(height: 22),
                _groupLabel('Приложение'),
                const SizedBox(height: 10),
                _section(
                  id: 'mobile',
                  icon: Icons.phone_android_outlined,
                  title: 'Мобильное меню',
                  subtitle: 'Компактное или полное меню на телефоне',
                  hint: _mobileFull ? 'полное' : 'компактное',
                  body: _mobileBody(),
                ),
                const SizedBox(height: 12),
                _section(
                  id: 'backup',
                  icon: Icons.backup_outlined,
                  title: 'Бэкап',
                  subtitle: 'Копия базы на этом устройстве',
                  hint: _lastBackup == null ? 'нет' : AppDateTime.format(_lastBackup),
                  body: _backupBody(),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 12),
                  _section(
                    id: 'showcase',
                    icon: Icons.photo_library_outlined,
                    title: 'Витрина для скринов',
                    subtitle: 'Фейковые заказы без реальных данных',
                    hint: 'debug',
                    body: _showcaseBody(),
                  ),
                ],
                const SizedBox(height: 12),
                _section(
                  id: 'danger',
                  icon: Icons.warning_amber_rounded,
                  title: 'Опасная зона',
                  subtitle: 'Очистка БД — только владелец приложения',
                  hint: isOwner ? 'доступно' : 'закрыто',
                  danger: true,
                  body: _dangerBody(isOwner: isOwner),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _pad(int h) => h.toString().padLeft(2, '0');

  String _cashHint() {
    if (_defaultCashId == null) return 'не выбрана';
    for (final r in _cashRegisters) {
      if ((r['id'] as num?)?.toInt() == _defaultCashId) {
        return r['name']?.toString() ?? '#$_defaultCashId';
      }
    }
    return '#$_defaultCashId';
  }

  Widget _groupLabel(String text) => Text(text.toUpperCase(), style: AppTheme.sectionLabel);

  Widget _section({
    required String id,
    required IconData icon,
    required String title,
    required String subtitle,
    required String hint,
    required Widget body,
    bool danger = false,
  }) {
    final open = _openId == id;
    final mobile = AppResponsive.isMobile(context);
    final accent = danger ? AppColors.danger : AppColors.primary;
    return Container(
      decoration: AppTheme.panelDecoration.copyWith(
        border: Border.all(
          color: danger ? AppColors.danger.withOpacity(0.35) : AppColors.borderSoft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              onTap: () => _toggle(id),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: mobile ? AppResponsive.minTap + 8 : 0),
                child: Padding(
                padding: EdgeInsets.fromLTRB(16, mobile ? 14 : 14, 12, mobile ? 14 : 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 20, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppTheme.sectionTitle),
                          const SizedBox(height: 2),
                          Text(subtitle, style: AppTheme.pageSubtitle),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: mobile ? 72 : 120),
                      child: Text(
                        hint,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          color: AppColors.textDim,
                          fontSize: mobile ? 11 : 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: AppColors.textDim,
                    ),
                  ],
                ),
                ),
              ),
            ),
          ),
          if (open) ...[
            Divider(height: 1, color: AppColors.borderSoft.withOpacity(0.9)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: body,
            ),
          ],
        ],
      ),
    );
  }

  Widget _profileBody(AuthUser? user, {required bool canManage}) {
    final slug = user?.companySlug?.trim() ?? '';
    final invite = _inviteUrl;
    final logoFile = (_logoPath != null && File(_logoPath!).existsSync()) ? File(_logoPath!) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.bg.withOpacity(0.55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderSoft),
              ),
              clipBehavior: Clip.antiAlias,
              child: logoFile != null
                  ? Image.file(logoFile, fit: BoxFit.cover)
                  : const Icon(Icons.storefront_outlined, color: AppColors.textDim, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Логотип студии',
                    style: GoogleFonts.manrope(
                      color: AppColors.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Локально на этом устройстве · для печати и PDF позже',
                    style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11.5, height: 1.3),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickLogo,
                        icon: const Icon(Icons.image_outlined, size: 16),
                        label: Text(
                          logoFile == null ? 'Выбрать' : 'Заменить',
                          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (logoFile != null)
                        TextButton(
                          onPressed: _clearLogo,
                          child: Text('Удалить', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (canManage) ...[
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Название студии',
              isDense: true,
              helperText: 'Сохраняется на сервере для всех устройств студии',
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _savingProfile ? null : _saveProfile,
              child: _savingProfile
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Сохранить название', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
            ),
          ),
        ] else ...[
          _kv('Название', _studioName ?? user?.studioDisplayName ?? '—'),
          const SizedBox(height: 6),
          Text(
            'Сменить название может владелец или админ студии.',
            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, height: 1.35),
          ),
        ],
        const SizedBox(height: 14),
        _kv('Код / slug', slug.isEmpty ? '—' : slug),
        if (slug.isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: slug));
              if (mounted) showAppToast(context, 'Код скопирован');
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: Text('Копировать код', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ],
        if (invite != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: invite));
              if (mounted) showAppToast(context, 'Ссылка-приглашение скопирована');
            },
            icon: const Icon(Icons.link_rounded, size: 16),
            label: Text('Копировать invite', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ],
      ],
    );
  }

  Widget _contactsBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Телефон', isDense: true),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _addressCtrl,
          decoration: const InputDecoration(labelText: 'Адрес', isDense: true),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _waCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Публичный мессенджер студии',
            hintText: 'Номер для клиентов (WA / MAX / …)',
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _siteCtrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Сайт', isDense: true),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _savingContacts ? null : _saveContacts,
            child: _savingContacts
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Сохранить', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _branchesBody({required bool canManage}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_branches.isEmpty)
          Text(
            'Филиалы не загружены. Проверьте вход в аккаунт.',
            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13, height: 1.35),
          )
        else ...[
          Text(
            'По умолчанию для новых заказов',
            style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            value: _defaultBranchId != null && _branches.any((b) => b.id == _defaultBranchId)
                ? _defaultBranchId
                : (_branches.isNotEmpty ? _branches.first.id : null),
            items: _branches
                .map((b) => DropdownMenuItem(value: b.id, child: Text(b.name)))
                .toList(),
            onChanged: (v) async {
              setState(() => _defaultBranchId = v);
              await StudioPrefs.saveDefaultBranchId(v);
              if (mounted) showAppToast(context, 'Филиал по умолчанию сохранён');
            },
          ),
          const SizedBox(height: 12),
          ..._branches.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    size: 16,
                    color: b.id == _defaultBranchId ? AppColors.primary : AppColors.textDim,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      b.name,
                      style: GoogleFonts.manrope(
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  if (b.id == _defaultBranchId)
                    Text(
                      'по умолчанию',
                      style: GoogleFonts.manrope(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (canManage) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _createBranch,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text('Добавить филиал', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ],
      ],
    );
  }

  Widget _rolesBody() {
    const rows = <(String, String)>[
      (JobTitles.owner, 'Полный доступ к студии, люди, касса, настройки'),
      (JobTitles.manager, 'Управление студией и персоналом, как владелец'),
      (JobTitles.admin, 'Операции CRM, касса, назначения'),
      (JobTitles.master, 'Доска, календарь, свои цеха; без кассы и базы клиентов'),
    ];
    return Column(
      children: rows
          .map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      r.$1,
                      style: GoogleFonts.manrope(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.$2,
                      style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12.5, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _peopleBody({required bool canManage}) {
    if (!canManage) {
      final me = AuthController.instance.user;
      return Text(
        me == null
            ? 'Войдите, чтобы видеть доступ.'
            : 'Ваша должность: ${me.roles.isEmpty ? '—' : me.roles.join(', ')}. '
                'Назначение ролей — у администратора.',
        style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13, height: 1.4),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Заявки',
                style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: _createStaff,
              icon: const Icon(Icons.person_add_alt_1, size: 16),
              label: Text('Сотрудник', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ],
        ),
        if (_pending.isEmpty)
          Text(
            'Пусто. Заявка появится, когда человек войдёт через «Меня пригласили».',
            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12.5, height: 1.35),
          )
        else
          ..._pending.map(
            (p) => _personTile(
              title: p.displayLabel,
              subtitle: p.email,
              action: 'Назначить',
              accent: const Color(0xFFE8A838),
              onTap: () => _assign(p),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Пользователи',
          style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        if (_users.isEmpty)
          Text('Пока нет', style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12.5))
        else
          ..._users.take(40).map(
                (u) => _personTile(
                  title: u.displayLabel,
                  subtitle: [
                    if (u.roles.isNotEmpty) u.roles.join(', '),
                    u.email,
                  ].where((e) => e.trim().isNotEmpty).join(' · '),
                  action: 'Изменить',
                  onTap: () => _assign(u),
                ),
              ),
      ],
    );
  }

  Widget _personTile({
    required String title,
    required String subtitle,
    required String action,
    required VoidCallback onTap,
    Color accent = AppColors.primary,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.bg.withOpacity(0.45),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: [
                Icon(Icons.person_outline, size: 18, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.manrope(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Text(
                  action,
                  style: GoogleFonts.manrope(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hoursBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _startHour,
                decoration: const InputDecoration(labelText: 'Начало', isDense: true),
                items: [
                  for (var h = 0; h <= 22; h++)
                    DropdownMenuItem(value: h, child: Text('${_pad(h)}:00')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _startHour = v;
                    if (_endHour < _startHour) _endHour = _startHour;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _endHour,
                decoration: const InputDecoration(labelText: 'Конец', isDense: true),
                items: [
                  for (var h = _startHour; h <= 23; h++)
                    DropdownMenuItem(value: h, child: Text('${_pad(h)}:00')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _endHour = v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _saveHours,
            child: Text('Сохранить', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _workshopsBody() {
    final list = _cloudWorkshops.isNotEmpty ? _cloudWorkshops : WORKSHOPS;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _cloudWorkshops.isNotEmpty
              ? 'Цеха студии с сервера'
              : 'Локальный список цехов (как в CRM)',
          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12.5, height: 1.35),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: list
              .map(
                (w) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderSoft),
                  ),
                  child: Text(
                    w,
                    style: GoogleFonts.manrope(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 12.5),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _templatesBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Схема для РФ: сначала облачный Telegram-бот (клиент жмёт Start по ссылке), '
          'если нет — SMS (если настроен на сервере), иначе ручной канал. '
          'Ниже — канал для ручной отправки и шаблоны текста.',
          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _clientMsgChannel,
          decoration: const InputDecoration(labelText: 'Канал клиенту', isDense: true),
          dropdownColor: AppColors.surface2,
          items: const [
            DropdownMenuItem(value: 'ask', child: Text('Спрашивать каждый раз')),
            DropdownMenuItem(value: 'telegram', child: Text('Telegram')),
            DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp')),
            DropdownMenuItem(value: 'sms', child: Text('SMS')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _clientMsgChannel = v);
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Плейсхолдеры: {name} {order} {debt} {car}. Пустое поле = встроенный текст.',
          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _tplBookingCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Запись / напоминание', isDense: true),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _tplDebtCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Долг', isDense: true),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _tplReadyCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Готово к выдаче', isDense: true),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _savingTemplates ? null : _saveTemplates,
            child: _savingTemplates
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Сохранить', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _payrollRulesBody() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper().getPayrollRules(),
      builder: (ctx, snap) {
        final rules = snap.data ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Режим percent = % от суммы работ цеха, fixed = фикс ₽. Кнопка «Рассчитать» в ЗП заказа.',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 10),
            if (rules.isEmpty)
              Text('Правил пока нет', style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 13))
            else
              ...rules.map(
                (r) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${r['workshop']?.toString().isNotEmpty == true ? r['workshop'] : 'Любой цех'}'
                    ' · ${r['mode'] == 'fixed' ? '${r['value']} ₽' : '${r['value']} %'}',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  subtitle: (r['label']?.toString() ?? '').isEmpty
                      ? null
                      : Text(r['label'].toString(), style: GoogleFonts.manrope(fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () async {
                      final id = (r['id'] as num?)?.toInt();
                      if (id == null) return;
                      await DatabaseHelper().deletePayrollRule(id);
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final wsCtrl = TextEditingController();
                final valCtrl = TextEditingController(text: '30');
                var mode = 'percent';
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dctx) => StatefulBuilder(
                    builder: (dctx, setLocal) => AlertDialog(
                      backgroundColor: AppColors.surface,
                      title: Text('Правило ЗП', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: wsCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Цех (пусто = любой)',
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: mode,
                            decoration: const InputDecoration(labelText: 'Режим', isDense: true),
                            items: const [
                              DropdownMenuItem(value: 'percent', child: Text('% от цеха')),
                              DropdownMenuItem(value: 'fixed', child: Text('Фикс ₽')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setLocal(() => mode = v);
                            },
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: valCtrl,
                            decoration: const InputDecoration(labelText: 'Значение', isDense: true),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Отмена')),
                        ElevatedButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Добавить')),
                      ],
                    ),
                  ),
                );
                if (ok != true) return;
                final v = double.tryParse(valCtrl.text.replaceAll(',', '.')) ?? 0;
                await DatabaseHelper().addPayrollRule(
                  workshop: wsCtrl.text,
                  mode: mode,
                  value: v,
                );
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Добавить правило'),
            ),
          ],
        );
      },
    );
  }

  Widget _bookingApiBody() {
    final slug = AuthController.instance.user?.companySlug?.trim() ?? '';
    final bookUrl = slug.isEmpty
        ? 'Войдите в облако — ссылка появится по slug студии'
        : '${AuthApi.defaultBaseUrl}/book/$slug';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Публичная мини-запись создаёт лид (источник «Сайт»). API лида: POST /public/v1/leads с X-Api-Key.',
          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 10),
        SelectableText(
          bookUrl,
          style: GoogleFonts.manrope(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: slug.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: bookUrl));
                    if (mounted) showAppToast(context, 'Ссылка скопирована');
                  },
            icon: const Icon(Icons.copy, size: 16),
            label: Text('Копировать', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _pdfBody(String studio) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kv('Студия', studio),
        const SizedBox(height: 6),
        _kv('Телефон', _phoneCtrl.text.trim().isEmpty ? 'из контактов' : _phoneCtrl.text.trim()),
        const SizedBox(height: 6),
        _kv('Адрес', _addressCtrl.text.trim().isEmpty ? 'из контактов' : _addressCtrl.text.trim()),
        const SizedBox(height: 10),
        Text(
          'Экспорт и бланки подхватят эти поля автоматически.',
          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12.5, height: 1.35),
        ),
      ],
    );
  }

  Widget _cashBody() {
    if (_cashRegisters.isEmpty) {
      return Text(
        'Касс пока нет — создайте в разделе «Касса».',
        style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13, height: 1.35),
      );
    }
    return DropdownButtonFormField<int>(
      value: _defaultCashId != null && _cashRegisters.any((r) => (r['id'] as num?)?.toInt() == _defaultCashId)
          ? _defaultCashId
          : (_cashRegisters.first['id'] as num?)?.toInt(),
      decoration: const InputDecoration(labelText: 'Касса', isDense: true),
      items: _cashRegisters
          .map(
            (r) => DropdownMenuItem(
              value: (r['id'] as num).toInt(),
              child: Text(r['name']?.toString() ?? 'Касса #${r['id']}'),
            ),
          )
          .toList(),
      onChanged: (v) async {
        setState(() => _defaultCashId = v);
        await StudioPrefs.saveDefaultCashRegisterId(v);
        if (mounted) showAppToast(context, 'Касса по умолчанию сохранена');
      },
    );
  }

  Widget _mobileBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Полное меню на телефоне',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          subtitle: Text(
            'Выкл = компактный режим (ПК + телефон)',
            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
          ),
          value: _mobileFull,
          activeColor: AppColors.primary,
          onChanged: _setMobileFull,
        ),
      ],
    );
  }

  Widget _backupBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kv(
          'Последний',
          _lastBackup == null ? 'ещё не создавался' : AppDateTime.format(_lastBackup),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _backupNow,
          icon: const Icon(Icons.backup_outlined, size: 18),
          label: Text('Сделать бэкап сейчас', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _showcaseBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Добавит выдуманных клиентов, заказы на доску, пару движений по кассе и склад. '
          'Для боевой студии лучше не жать.',
          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12.5, height: 1.35),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _showcaseBusy
              ? null
              : () async {
                  setState(() => _showcaseBusy = true);
                  try {
                    final msg = await ShowcaseSeed.resetAndFill();
                    if (!mounted) return;
                    showAppToast(context, msg);
                  } catch (e) {
                    if (!mounted) return;
                    showAppToast(context, 'Не вышло: $e');
                  } finally {
                    if (mounted) setState(() => _showcaseBusy = false);
                  }
                },
          icon: _showcaseBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.auto_awesome_outlined, size: 18),
          label: Text(
            _showcaseBusy ? 'Подождите…' : 'Сбросить и заполнить',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _dangerBody({required bool isOwner}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isOwner
              ? 'Очистка удалит локальные данные. Нужен PIN владельца приложения.'
              : 'Очистка БД доступна только владельцу приложения.',
          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12.5, height: 1.35),
        ),
        if (isOwner) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _wipeDb,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: BorderSide(color: AppColors.danger.withOpacity(0.5)),
            ),
            icon: const Icon(Icons.delete_forever_outlined, size: 18),
            label: Text('Очистить базу…', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ],
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            k,
            style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: GoogleFonts.manrope(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
