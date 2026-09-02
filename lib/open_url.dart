import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Публичный сайт продукта (лендинг + политика).
const kWebsiteUrl = 'https://det-app.ru';

/// Открыть внешний URL в браузере системы.
Future<bool> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e, st) {
    debugPrint('openExternalUrl failed: $e\n$st');
    return false;
  }
}

Future<bool> openWebsite() => openExternalUrl(kWebsiteUrl);
