import '../auth/auth_controller.dart';

/// Компания в облаке: основной рабочий контур без LAN.
class CloudMode {
  static bool get enabled {
    final u = AuthController.instance.user;
    if (!AuthController.instance.isSignedIn || u == null) return false;
    if (u.isPlatformAdmin) return false;
    return u.companyId != null;
  }
}
