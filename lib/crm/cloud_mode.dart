import '../auth/auth_controller.dart';

/// Компания в облаке: основной рабочий контур без LAN.
class CloudMode {
  /// Вошёл в аккаунт — UI панели связи облако-first (включая владельца приложения).
  static bool get sessionActive {
    final u = AuthController.instance.user;
    return AuthController.instance.isSignedIn && u != null;
  }

  /// CRM-данные через API компании (не platform-only и не локальный LAN).
  static bool get enabled {
    final u = AuthController.instance.user;
    if (!sessionActive || u == null) return false;
    if (u.isPlatformAdmin) return false;
    return u.companyId != null;
  }
}
