import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_version.dart';
import '../patch_notes.dart';
import 'update_channel.dart';
import 'update_manifest.dart';

enum UpdateCheckStatus { noChannel, upToDate, available, error }

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final UpdateManifest? manifest;
  final String? message;
  final String? channelUrl;

  const UpdateCheckResult({
    required this.status,
    this.manifest,
    this.message,
    this.channelUrl,
  });
}

/// Windows: скачан zip, распакован — ждёт перезапуска updater'ом.
class PreparedUpdate {
  final UpdateManifest manifest;
  final String appDir;
  final String newAppDir;
  final String updaterPs1;
  final String portableRoot;

  const PreparedUpdate({
    required this.manifest,
    required this.appDir,
    required this.newAppDir,
    required this.updaterPs1,
    required this.portableRoot,
  });
}

/// Android: APK скачан и проверен — открыть системный установщик.
class PreparedApkUpdate {
  final UpdateManifest manifest;
  final String apkPath;

  const PreparedApkUpdate({
    required this.manifest,
    required this.apkPath,
  });
}

typedef UpdateProgress = void Function(double progress, String phase);

class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  bool get isAndroid => Platform.isAndroid;
  bool get isWindowsDesktop => Platform.isWindows;

  Future<UpdateCheckResult> check() async {
    await AppVersion.ensureLoaded();
    final channel = await UpdateChannel.load();
    if (channel == null) {
      return const UpdateCheckResult(
        status: UpdateCheckStatus.noChannel,
        message: 'Не задан канал обновлений.\n'
            'По умолчанию: http://api.det-app.ru/updates/latest.json',
      );
    }

    final manifestUrl = UpdateChannel.normalizeManifestUrl(channel.manifestUrl);

    try {
      final resp = await http
          .get(Uri.parse(manifestUrl))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        final hint = resp.statusCode == 401
            ? '\nПохоже, указан порт синхронизации :7878.\n'
                'Нужен: http://IP:8080/latest.json'
            : '';
        return UpdateCheckResult(
          status: UpdateCheckStatus.error,
          channelUrl: manifestUrl,
          message: 'Сервер ответил ${resp.statusCode}$hint',
        );
      }
      final map = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final manifest = UpdateManifest.fromJson(map);

      if (manifest.build <= 0) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.error,
          channelUrl: manifestUrl,
          message: 'Некорректный latest.json (build)',
        );
      }

      if (Platform.isAndroid) {
        if (!manifest.hasAndroidPack) {
          return UpdateCheckResult(
            status: UpdateCheckStatus.error,
            channelUrl: manifestUrl,
            message:
                'В latest.json нет android_url / android_sha256.\n'
                'Опубликуйте APK через publish_update.ps1 после сборки apk.',
          );
        }
      } else {
        if (!manifest.hasWindowsPack) {
          return UpdateCheckResult(
            status: UpdateCheckStatus.error,
            channelUrl: manifestUrl,
            message: 'Некорректный latest.json (нет url/sha256 для Windows)',
          );
        }
      }

      if (!manifest.isNewerThan(AppVersion.build)) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.upToDate,
          manifest: manifest,
          channelUrl: manifestUrl,
          message: 'Установлена последняя версия: ${AppVersion.label}',
        );
      }
      return UpdateCheckResult(
        status: UpdateCheckStatus.available,
        manifest: manifest,
        channelUrl: manifestUrl,
      );
    } catch (e) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.error,
        channelUrl: manifestUrl,
        message: 'Не удалось проверить обновления.\n$e',
      );
    }
  }

  /// Android: скачать APK, проверить sha256.
  Future<PreparedApkUpdate> prepareAndroidUpdate(
    UpdateManifest manifest, {
    UpdateProgress? onProgress,
  }) async {
    await AppVersion.ensureLoaded();
    if (!Platform.isAndroid) {
      throw StateError('prepareAndroidUpdate только для Android');
    }
    if (!manifest.hasAndroidPack) {
      throw StateError('В манифесте нет пакета Android');
    }
    if (manifest.dbVersion < AppVersion.dbSchema) {
      throw StateError(
        'Пакет со схемой БД ${manifest.dbVersion}, '
        'приложение уже на ${AppVersion.dbSchema}.',
      );
    }

    final dir = await getTemporaryDirectory();
    final apkPath = p.join(
      dir.path,
      'DetApp-${manifest.version}+${manifest.build}.apk',
    );
    final file = File(apkPath);
    if (await file.exists()) await file.delete();

    await _downloadToFile(
      manifest.androidUrl,
      apkPath,
      onProgress: onProgress,
      expectedSize: manifest.androidSize,
    );
    onProgress?.call(1, 'Проверка файла…');
    final hash = await _sha256File(apkPath);
    if (hash != manifest.androidSha256.toLowerCase()) {
      throw StateError(
        'Контрольная сумма APK не совпала.\n'
        'Ожидали ${manifest.androidSha256}\nПолучили $hash',
      );
    }
    return PreparedApkUpdate(manifest: manifest, apkPath: apkPath);
  }

  /// Открыть системный установщик APK.
  Future<String> openAndroidInstaller(PreparedApkUpdate prepared) async {
    await markPatchNotesUpdateFrom();
    final r = await OpenFilex.open(prepared.apkPath);
    if (r.type != ResultType.done) {
      throw StateError(
        'Не удалось открыть установщик: ${r.message}\n'
        'Разрешите установку из этого источника в настройках Android.',
      );
    }
    return r.message;
  }

  /// Windows: скачать, проверить sha256, распаковать. Без закрытия приложения.
  Future<PreparedUpdate> prepareUpdate(
    UpdateManifest manifest, {
    UpdateProgress? onProgress,
  }) async {
    await AppVersion.ensureLoaded();

    if (manifest.dbVersion < AppVersion.dbSchema) {
      throw StateError(
        'Пакет обновления со схемой БД ${manifest.dbVersion}, '
        'а приложение уже на ${AppVersion.dbSchema}. Обновление отклонено.',
      );
    }

    final exeDir = File(Platform.resolvedExecutable).parent;
    final root = UpdateChannel.portableRoot();
    final updaterPs1 = root == null
        ? null
        : File(p.join(root, 'update', 'DetAppUpdate.ps1'));
    final appDir = root == null ? null : Directory(p.join(root, 'app'));
    final isPortable = root != null &&
        p.basename(exeDir.path).toLowerCase() == 'app' &&
        updaterPs1 != null &&
        await updaterPs1.exists() &&
        appDir != null &&
        await appDir.exists();

    if (!isPortable) {
      throw StateError(
        'Автообновление работает только из папки DetApp (portable), '
        'не из build\\…\\Release.\n\n'
        'Сейчас запуск:\n${exeDir.path}\n\n'
        'Закройте приложение и откройте:\n'
        'D:\\DetApp\\app\\det_app.exe\n\n'
        'Или скачайте zip вручную кнопкой ниже и распакуйте в DetApp\\app\\.',
      );
    }

    final tmp = await getTemporaryDirectory();
    final work = Directory(
      p.join(tmp.path, 'detapp-update-${manifest.build}-${DateTime.now().millisecondsSinceEpoch}'),
    );
    if (await work.exists()) await work.delete(recursive: true);
    await work.create(recursive: true);

    final zipPath = p.join(work.path, 'update.zip');
    final extractDir = Directory(p.join(work.path, 'new_app'));
    await extractDir.create(recursive: true);

    await _downloadToFile(
      manifest.url,
      zipPath,
      onProgress: onProgress,
      expectedSize: manifest.size,
    );

    onProgress?.call(1, 'Проверка файла…');
    final hash = await _sha256File(zipPath);
    if (hash != manifest.sha256.toLowerCase()) {
      throw StateError(
        'Контрольная сумма не совпала.\nОжидали ${manifest.sha256}\nПолучили $hash',
      );
    }

    onProgress?.call(1, 'Распаковка…');
    await _extractZip(zipPath, extractDir.path);
    final newAppDir = _resolveAppContentDir(extractDir);
    final exeProbe = File(p.join(newAppDir.path, 'det_app.exe'));
    if (!await exeProbe.exists()) {
      throw StateError('В архиве нет det_app.exe (после распаковки)');
    }

    // Обновить скрипт рядом с portable (из ассета этой сборки).
    await _refreshPortableUpdaterScript(updaterPs1.path);

    await _backupDbBeforeUpdate(manifest.version);
    onProgress?.call(1, 'Готово к установке');

    return PreparedUpdate(
      manifest: manifest,
      appDir: appDir.path,
      newAppDir: newAppDir.path,
      updaterPs1: updaterPs1.path,
      portableRoot: root,
    );
  }

  /// Закрыть приложение и подменить файлы через PowerShell (из TEMP-копии скрипта).
  Future<void> applyPreparedAndRestart(PreparedUpdate prepared) async {
    await markPatchNotesUpdateFrom();
    final myPid = pid;

    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final scriptPath = p.join(tmp.path, 'detapp-updater-$stamp.ps1');
    final readyPath = p.join(tmp.path, 'detapp-updater-$stamp.ready');

    // Всегда свежий скрипт из ассета (не зависим от старого update\ на диске).
    final scriptBody = await _loadUpdaterScript();
    await File(scriptPath).writeAsString(scriptBody, flush: true);
    // Зеркало в portable\update на будущее.
    try {
      await _refreshPortableUpdaterScript(prepared.updaterPs1, body: scriptBody);
    } catch (_) {}

    if (await File(readyPath).exists()) await File(readyPath).delete();

    final args = <String>[
      '-NoProfile',
      '-ExecutionPolicy', 'Bypass',
      '-WindowStyle', 'Hidden',
      '-File', scriptPath,
      '-AppDir', prepared.appDir,
      '-NewAppDir', prepared.newAppDir,
      '-WaitPid', '$myPid',
      '-ExeName', 'det_app.exe',
      '-ReadyFile', readyPath,
    ];

    final proc = await Process.start(
      'powershell.exe',
      args,
      mode: ProcessStartMode.detached,
      workingDirectory: prepared.portableRoot,
      runInShell: false,
    );
    if (proc.pid <= 0) {
      throw StateError('Не удалось запустить установщик обновления (PowerShell).');
    }

    // Дождаться сигнала, что скрипт реально стартовал (не молча упал).
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    var started = false;
    while (DateTime.now().isBefore(deadline)) {
      if (await File(readyPath).exists()) {
        final t = (await File(readyPath).readAsString()).trim();
        if (t.startsWith('error:')) {
          throw StateError('Установщик сразу сообщил об ошибке:\n${t.substring(6)}');
        }
        started = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (!started) {
      throw StateError(
        'Установщик обновления не подтвердил запуск.\n'
        'Лог: %TEMP%\\detapp-update-logs\\\n'
        'Попробуйте «Скачать zip вручную» и распаковать в DetApp\\app\\.',
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 400));
    exit(0);
  }

  Future<void> _downloadToFile(
    String url,
    String destPath, {
    UpdateProgress? onProgress,
    int? expectedSize,
  }) async {
    final client = http.Client();
    try {
      onProgress?.call(0, 'Подключение…');
      final req = http.Request('GET', Uri.parse(url));
      final resp = await client.send(req).timeout(const Duration(seconds: 45));
      if (resp.statusCode != 200) {
        throw StateError('Скачивание: HTTP ${resp.statusCode}\n$url');
      }
      final total = resp.contentLength ?? expectedSize ?? 0;
      final sink = File(destPath).openWrite();
      var received = 0;
      var lastUi = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final chunk in resp.stream.timeout(const Duration(seconds: 90))) {
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        if (onProgress != null && now.difference(lastUi).inMilliseconds >= 100) {
          lastUi = now;
          final pct = total > 0 ? (received / total).clamp(0.0, 0.99) : 0.0;
          final mb = (received / (1024 * 1024)).toStringAsFixed(1);
          final phase = total > 0
              ? 'Скачивание… $mb / ${(total / (1024 * 1024)).toStringAsFixed(1)} МБ'
              : 'Скачивание… $mb МБ';
          onProgress(pct, phase);
        }
      }
      await sink.close();
      if (received <= 0) {
        throw StateError('Скачан пустой файл.\n$url');
      }
      onProgress?.call(1, 'Скачивание завершено');
    } finally {
      client.close();
    }
  }

  Future<String> _sha256File(String path) async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString();
  }

  Future<void> _extractZip(String zipPath, String destDir) async {
    final r = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-Command',
        "Expand-Archive -LiteralPath '$zipPath' -DestinationPath '$destDir' -Force",
      ],
    );
    if (r.exitCode != 0) {
      throw StateError('Распаковка zip не удалась: ${r.stderr}');
    }
  }

  Directory _resolveAppContentDir(Directory extractRoot) {
    final exe = File(p.join(extractRoot.path, 'det_app.exe'));
    if (exe.existsSync()) return extractRoot;

    final kids = extractRoot.listSync().whereType<Directory>().toList();
    for (final d in kids) {
      if (File(p.join(d.path, 'det_app.exe')).existsSync()) return d;
      final nested = Directory(p.join(d.path, 'app'));
      if (File(p.join(nested.path, 'det_app.exe')).existsSync()) return nested;
    }
    return extractRoot;
  }

  Future<String> _loadUpdaterScript() async {
    try {
      return await rootBundle.loadString('assets/update/DetAppUpdate.ps1');
    } catch (_) {
      final root = UpdateChannel.portableRoot();
      if (root != null) {
        final f = File(p.join(root, 'update', 'DetAppUpdate.ps1'));
        if (await f.exists()) return await f.readAsString();
      }
      throw StateError('Не найден скрипт DetAppUpdate.ps1');
    }
  }

  Future<void> _refreshPortableUpdaterScript(String destPath, {String? body}) async {
    final text = body ?? await _loadUpdaterScript();
    final f = File(destPath);
    await f.parent.create(recursive: true);
    await f.writeAsString(text, flush: true);
  }

  Future<void> _backupDbBeforeUpdate(String version) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final db = File(p.join(docs.path, 'detailing.db'));
      if (!await db.exists()) return;
      final dir = Directory(p.join(docs.path, 'det_app_backups'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final dest = p.join(docs.path, 'det_app_backups', 'pre-update-${version}_$stamp.db');
      await db.copy(dest);
    } catch (_) {}
  }
}
