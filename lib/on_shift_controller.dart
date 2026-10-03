import 'package:flutter/foundation.dart';

import 'auth/auth_controller.dart';
import 'crm/cloud_db_bridge.dart';
import 'crm/crm_api.dart';
import 'database.dart';

/// Статус «На смене» для текущего мастера + список на смене в студии.
class OnShiftController extends ChangeNotifier {
  OnShiftController._();
  static final OnShiftController instance = OnShiftController._();

  bool _onShift = false;
  int? _masterId;
  List<Map<String, dynamic>> _onShiftMasters = const [];
  bool _loading = false;

  bool get onShift => _onShift;
  int? get masterId => _masterId;
  bool get canToggle => _masterId != null;
  List<Map<String, dynamic>> get onShiftMasters => _onShiftMasters;
  bool get loading => _loading;

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      final user = AuthController.instance.user;
      _masterId = user?.masterId;

      // Локально: если нет masterId в аккаунте — ищем мастера по имени пользователя.
      if (_masterId == null && user != null) {
        final all = await DatabaseHelper().getAllMastersFull();
        final name = user.fullName.trim().toLowerCase();
        for (final m in all) {
          if ((m['name']?.toString() ?? '').trim().toLowerCase() == name) {
            _masterId = (m['id'] as num?)?.toInt();
            break;
          }
        }
      }

      final onShiftList = await DatabaseHelper().getMastersOnShift();
      _onShiftMasters = onShiftList;

      if (_masterId != null) {
        final me = onShiftList.cast<Map<String, dynamic>?>().firstWhere(
              (m) => (m?['id'] as num?)?.toInt() == _masterId,
              orElse: () => null,
            );
        if (me != null) {
          _onShift = true;
        } else {
          // Может быть не в списке — читаем полный
          final all = await DatabaseHelper().getAllMastersFull();
          final row = all.cast<Map<String, dynamic>?>().firstWhere(
                (m) => (m?['id'] as num?)?.toInt() == _masterId,
                orElse: () => null,
              );
          _onShift = ((row?['on_shift'] as num?)?.toInt() ?? 0) == 1 ||
              row?['on_shift'] == true;
        }
      } else {
        _onShift = false;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String?> setOnShift(bool value) async {
    final mid = _masterId;
    if (mid == null) {
      return 'Аккаунт не привязан к мастеру';
    }
    try {
      if (CloudDbBridge.active && AuthController.instance.accessToken != null) {
        try {
          await CrmApi().setMyOnShift(value);
        } catch (_) {
          // fallback: patch master напрямую (админ / старый API)
          await DatabaseHelper().setMasterOnShift(mid, value);
        }
      } else {
        await DatabaseHelper().setMasterOnShift(mid, value);
      }
      _onShift = value;
      await refresh();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> setMasterOnShift(int masterId, bool value) async {
    try {
      await DatabaseHelper().setMasterOnShift(masterId, value);
      await refresh();
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}
