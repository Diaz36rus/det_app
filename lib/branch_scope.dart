import 'package:flutter/foundation.dart';

import 'auth/auth_controller.dart';
import 'auth/company_api.dart';
import 'crm/cloud_mode.dart';
import 'studio_prefs.dart';

/// Выбранный филиал для операционки (доска / касса / статы).
/// `null` = все филиалы (где поддерживается).
class BranchScope extends ChangeNotifier {
  BranchScope._();
  static final BranchScope instance = BranchScope._();

  final _api = CompanyApi();
  List<CompanyBranch> _branches = const [];
  int? _selectedId;
  bool _loaded = false;

  List<CompanyBranch> get branches =>
      _branches.where((b) => b.isActive).toList(growable: false);

  /// null = «Все».
  int? get selectedId => _selectedId;

  bool get hasMultiple => branches.length > 1;

  bool get loaded => _loaded;

  String labelFor(int? id) {
    if (id == null) return 'Все филиалы';
    for (final b in branches) {
      if (b.id == id) return b.name;
    }
    return 'Филиал #$id';
  }

  Future<void> ensureLoaded() async {
    if (!CloudMode.enabled || !AuthController.instance.isSignedIn) {
      _branches = const [];
      _selectedId = null;
      _loaded = true;
      notifyListeners();
      return;
    }
    try {
      final token = AuthController.instance.accessToken ?? '';
      final rows = await _api.listBranches(accessToken: token);
      _branches = rows;
      final saved = await StudioPrefs.loadOpsBranchFilterId();
      if (saved == null) {
        _selectedId = null;
      } else if (rows.any((b) => b.id == saved && b.isActive)) {
        _selectedId = saved;
      } else {
        _selectedId = null;
        await StudioPrefs.saveOpsBranchFilterId(null);
      }
    } catch (_) {
      _branches = const [];
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> select(int? id) async {
    if (_selectedId == id) return;
    _selectedId = id;
    await StudioPrefs.saveOpsBranchFilterId(id);
    notifyListeners();
  }

  bool matchesOrderBranch(dynamic branchId) {
    if (_selectedId == null) return true;
    final id = branchId is num ? branchId.toInt() : int.tryParse('$branchId');
    return id == _selectedId;
  }
}
