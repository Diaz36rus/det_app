import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app_version.dart';

/// GlitchTip/Sentry. DSN задаётся при сборке: `--dart-define=SENTRY_DSN=...`; без него всё выключено.
class CrashReporting {
  CrashReporting._();

  static const _dsn = String.fromEnvironment('SENTRY_DSN');

  static bool get enabled => _dsn.isNotEmpty;

  static Future<void> init() async {
    if (!enabled) return;
    await SentryFlutter.init((o) {
      o.dsn = _dsn;
      o.release = 'det_app@${AppVersion.label}';
      o.environment = kReleaseMode ? 'production' : 'debug';
      // Данные клиентов студий (телефоны, госномера) не должны уходить в отчёты.
      o.sendDefaultPii = false;
      o.attachScreenshot = false;
      o.tracesSampleRate = 0;
    });
  }

  static void capture(Object error, StackTrace? stack) {
    if (!enabled) return;
    unawaited(Sentry.captureException(error, stackTrace: stack));
  }
}
