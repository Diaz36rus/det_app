import 'dart:io';

import 'package:flutter/services.dart';

/// Откуда установлено Android-приложение (RuStore / Play / sideload).
class InstallSource {
  InstallSource._();

  static const _channel = MethodChannel('ru.detapp.app/install');

  /// Пакеты магазинов: для них облачный APK не предлагаем (подпись).
  static const storePackages = <String>{
    'ru.vk.store', // RuStore
    'ru.vk.store.beta',
    'com.android.vending', // Google Play
    'com.huawei.appmarket',
    'com.xiaomi.mipicks',
    'com.samsung.android.voc',
  };

  static Future<String?> installerPackage() async {
    if (!Platform.isAndroid) return null;
    try {
      final v = await _channel.invokeMethod<dynamic>('installerPackage');
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isFromAppStore() async {
    final pkg = await installerPackage();
    if (pkg == null) return false;
    return storePackages.contains(pkg);
  }
}
