import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Канал обновлений: URL манифеста `latest.json`.
class UpdateChannel {
  final String manifestUrl;

  const UpdateChannel({required this.manifestUrl});

  static const fileName = 'update_channel.json';

  /// Облачный канал по умолчанию (Selectel / api.det-app.ru).
  static const cloudManifestUrl = 'http://api.det-app.ru/updates/latest.json';

  /// Корень portable: `…/DetApp-portable` (родитель папки `app`). Только desktop.
  static String? portableRoot() {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return null;
    try {
      final exe = File(Platform.resolvedExecutable);
      final appDir = exe.parent; // …/app
      final root = appDir.parent; // …/DetApp-portable
      return root.path;
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> _candidatePaths() async {
    final out = <String>[];
    final root = portableRoot();
    if (root != null) out.add(p.join(root, fileName));

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final docs = await getApplicationDocumentsDirectory();
        out.add(p.join(docs.path, fileName));
      } catch (_) {}
    }

    out.add(p.join(Directory.current.path, fileName));
    out.add(p.join(Directory.current.path, 'tools', fileName));
    return out;
  }

  static Future<UpdateChannel?> load() async {
    for (final path in await _candidatePaths()) {
      final f = File(path);
      if (!await f.exists()) continue;
      try {
        final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final url = normalizeManifestUrl(map['manifest_url']?.toString() ?? '');
        if (url.isEmpty) continue;
        final raw = map['manifest_url']?.toString().trim() ?? '';
        if (raw != url) {
          try {
            await f.writeAsString(
              const JsonEncoder.withIndent('  ').convert({'manifest_url': url}),
              flush: true,
            );
          } catch (_) {}
        }
        return UpdateChannel(manifestUrl: url);
      } catch (_) {
        continue;
      }
    }
    // Нет локального файла — облако.
    return const UpdateChannel(manifestUrl: cloudManifestUrl);
  }

  static Future<void> save(String manifestUrl) async {
    final normalized = normalizeManifestUrl(manifestUrl);
    if (normalized.isEmpty) {
      throw StateError('Пустой URL манифеста');
    }
    late final File f;
    if (Platform.isAndroid || Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      f = File(p.join(docs.path, fileName));
    } else {
      final root = portableRoot();
      if (root == null) {
        throw StateError('Не удалось определить папку для update_channel.json');
      }
      f = File(p.join(root, fileName));
    }
    await f.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'manifest_url': normalized,
      }),
      flush: true,
    );
  }

  /// Нормализация URL манифеста.
  /// Облако: api.det-app.ru/updates/latest.json
  /// LAN: http://IP:8080/latest.json (sync :7878 → :8080)
  static String normalizeManifestUrl(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    try {
      final u = Uri.parse(s.startsWith('http') ? s : 'http://$s');
      if (u.host.isEmpty) return s;

      final host = u.host.toLowerCase();
      final isCloud = host == 'api.det-app.ru' ||
          host == 'det-app.ru' ||
          host.endsWith('.det-app.ru') ||
          u.path.contains('/updates');

      if (isCloud) {
        final path = u.path.contains('latest.json')
            ? u.path
            : '/updates/latest.json';
        return Uri(
          scheme: u.scheme.isEmpty ? 'http' : u.scheme,
          host: u.host,
          port: u.hasPort && u.port != 80 && u.port != 443 ? u.port : null,
          path: path,
        ).toString();
      }

      var port = u.hasPort ? u.port : 8080;
      if (port == 7878) port = 8080;
      return Uri(
        scheme: 'http',
        host: u.host,
        port: port,
        path: '/latest.json',
      ).toString();
    } catch (_) {
      return s;
    }
  }

  /// Подсказка URL с LAN-хоста sync: `:7878` → `:8080/latest.json`.
  static String? suggestFromSyncBaseUrl(String? syncBaseUrl) {
    final raw = (syncBaseUrl ?? '').trim();
    if (raw.isEmpty) return null;
    final n = normalizeManifestUrl(raw);
    return n.isEmpty ? null : n;
  }
}
