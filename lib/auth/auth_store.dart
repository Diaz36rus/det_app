import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'auth_models.dart';

/// Локальное хранение сессии. Windows: AppData (Documents часто синкается в OneDrive).
class AuthStore {
  static const _fileName = 'auth_session.json';

  Future<File> _legacyFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, _fileName));
  }

  Future<File> _file() async {
    if (!Platform.isWindows) return _legacyFile();
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Однократный перенос старой сессии из Documents (Windows).
  Future<void> _migrateLegacy(File target) async {
    if (!Platform.isWindows || await target.exists()) return;
    try {
      final old = await _legacyFile();
      if (!await old.exists()) return;
      await target.parent.create(recursive: true);
      await target.writeAsString(await old.readAsString(), flush: true);
      await old.delete();
    } catch (_) {}
  }

  Future<void> save(AuthTokens tokens, AuthUser user) async {
    final f = await _file();
    await f.parent.create(recursive: true);
    final map = {
      'tokens': tokens.toJson(),
      'user': {
        'id': user.id,
        'email': user.email,
        'phone': user.phone,
        'full_name': user.fullName,
        'is_platform_admin': user.isPlatformAdmin,
        'company_id': user.companyId,
        'company_slug': user.companySlug,
        'company_name': user.companyName,
        'roles': user.roles,
        'branch_ids': user.branchIds,
        'permissions': user.permissions,
        'pending_assignment': user.pendingAssignment,
        'master_id': user.masterId,
        'workshops': user.workshops,
      },
    };
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(map), flush: true);
  }

  Future<({AuthTokens tokens, AuthUser user})?> load() async {
    final f = await _file();
    await _migrateLegacy(f);
    if (!await f.exists()) return null;
    try {
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final tokens = AuthTokens.fromJson(map['tokens'] as Map<String, dynamic>? ?? {});
      final user = AuthUser.fromJson(map['user'] as Map<String, dynamic>? ?? {});
      if (!tokens.isValid || user.id <= 0) return null;
      return (tokens: tokens, user: user);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    for (final f in {await _file(), await _legacyFile()}) {
      if (await f.exists()) {
        await f.delete();
      }
    }
  }
}
