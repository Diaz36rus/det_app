/// Схема deep link внутри приложения.
const kSyncQrScheme = 'detapp';
const kSyncQrHost = 'connect';
const kSyncQrPrefix = 'DETAPP|'; // устаревший текстовый формат
const kAndroidPackage = 'com.example.det_app';

/// QR для камеры телефона: обычный http на хост `/join` —
/// системная камера всегда умеет открывать http, страница перекинет в Det App.
String encodeSyncQrPayload(String baseUrl) {
  final u = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  if (u.isEmpty) return '';
  final base = Uri.tryParse(u);
  if (base == null || !base.hasScheme) {
    return Uri(
      scheme: 'http',
      host: u,
      path: '/join',
      queryParameters: {'url': u.startsWith('http') ? u : 'http://$u'},
    ).toString();
  }
  return base.replace(
    path: '/join',
    queryParameters: {'url': u},
  ).toString();
}

/// Deep link / intent для HTML-страницы и in-app сканера.
String encodeSyncDeepLink(String baseUrl) {
  final u = baseUrl.trim();
  if (u.isEmpty) return '';
  return Uri(
    scheme: kSyncQrScheme,
    host: kSyncQrHost,
    queryParameters: {'url': u},
  ).toString();
}

String encodeSyncAndroidIntent(String baseUrl, {String? fallbackHttp}) {
  final u = baseUrl.trim();
  final deepPath = 'connect?url=${Uri.encodeComponent(u)}';
  final fb = fallbackHttp == null ? '' : ';S.browser_fallback_url=${Uri.encodeComponent(fallbackHttp)}';
  return 'intent://$deepPath#Intent;scheme=$kSyncQrScheme;package=$kAndroidPackage$fb;end';
}

/// Достаёт URL хоста из QR / deep link / страницы /join.
String? parseSyncQrPayload(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return null;

  if (t.startsWith(kSyncQrPrefix)) {
    t = t.substring(kSyncQrPrefix.length).trim();
  }

  // intent://connect?url=...#Intent;...
  if (t.startsWith('intent://')) {
    final hash = t.indexOf('#');
    final head = hash >= 0 ? t.substring(0, hash) : t;
    final asUri = Uri.tryParse(head.replaceFirst('intent://', 'https://'));
    final q = asUri?.queryParameters['url'] ?? asUri?.queryParameters['u'];
    if (q != null && q.trim().isNotEmpty) return q.trim();
  }

  final uri = Uri.tryParse(t);
  if (uri != null) {
    // http://host:7878/join?url=http://host:7878
    if (uri.path == '/join' || uri.path == '/open-client' || uri.path.endsWith('/join')) {
      final q = uri.queryParameters['url'] ?? uri.queryParameters['u'];
      if (q != null && q.trim().isNotEmpty) return q.trim();
      // Если url не передали — сам хост без /join
      return uri.replace(path: '', queryParameters: {}).toString().replaceAll(RegExp(r'/$'), '');
    }

    if (uri.scheme == kSyncQrScheme || uri.scheme == 'det-app') {
      final q = uri.queryParameters['url'] ?? uri.queryParameters['u'];
      if (q != null && q.trim().isNotEmpty) return q.trim();
    }

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      // Не принимаем сырой /health и т.п. как sync url — только если это «корень» хоста
      if (uri.path.isEmpty || uri.path == '/') {
        return uri.replace(path: '', queryParameters: {}).toString().replaceAll(RegExp(r'/$'), '');
      }
      // Прямой адрес API хоста без лишнего path
      if (uri.path == '/health') {
        return uri.replace(path: '', queryParameters: {}).toString().replaceAll(RegExp(r'/$'), '');
      }
    }
  }

  if (t.startsWith('http://') || t.startsWith('https://')) {
    return t;
  }

  if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}:\d{2,5}$').hasMatch(t)) {
    return 'http://$t';
  }

  return null;
}
