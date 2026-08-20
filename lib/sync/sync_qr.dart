/// Схема deep link внутри приложения.
const kSyncQrScheme = 'detapp';
const kSyncQrHost = 'connect';
const kInviteQrHost = 'invite';
const kSyncQrPrefix = 'DETAPP|'; // устаревший текстовый формат
const kAndroidPackage = 'com.example.det_app';

/// Облачный QR приглашения: http://api…/join?slug=… → страница → detapp://invite?slug=
String encodeInviteQrPayload({
  required String slug,
  String apiBase = 'http://api.det-app.ru',
}) {
  final s = slug.trim().toLowerCase();
  if (s.isEmpty) return '';
  final base = apiBase.trim().replaceAll(RegExp(r'/+$'), '');
  return Uri.parse(base).replace(
    path: '/join',
    queryParameters: {'slug': s},
  ).toString();
}

String encodeInviteDeepLink(String slug) {
  final s = slug.trim().toLowerCase();
  if (s.isEmpty) return '';
  return Uri(
    scheme: kSyncQrScheme,
    host: kInviteQrHost,
    queryParameters: {'slug': s},
  ).toString();
}

/// Достаёт код студии из QR / deep link / /join?slug=
String? parseInviteSlug(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return null;

  if (t.startsWith('intent://')) {
    final hash = t.indexOf('#');
    final head = hash >= 0 ? t.substring(0, hash) : t;
    final asUri = Uri.tryParse(head.replaceFirst('intent://', 'https://'));
    final slug = asUri?.queryParameters['slug'] ?? asUri?.queryParameters['s'];
    if (slug != null && slug.trim().length >= 2) return slug.trim().toLowerCase();
  }

  final uri = Uri.tryParse(t);
  if (uri == null) return null;

  // LAN sync: /join?url=… — не приглашение
  if (uri.queryParameters.containsKey('url') || uri.queryParameters.containsKey('u')) {
    return null;
  }

  final slug = uri.queryParameters['slug'] ?? uri.queryParameters['s'];
  if (slug == null || slug.trim().length < 2) return null;
  final s = slug.trim().toLowerCase();

  final path = uri.path;
  final host = uri.host.toLowerCase();
  final isInvitePath = path == '/join' || path.endsWith('/join');
  final isInviteDeep = (uri.scheme == kSyncQrScheme || uri.scheme == 'det-app') &&
      (host == kInviteQrHost || uri.pathSegments.contains('invite'));
  if (isInvitePath || isInviteDeep || uri.queryParameters.containsKey('slug')) {
    return s;
  }
  return null;
}

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

  // Облачное приглашение — не LAN sync.
  if (parseInviteSlug(t) != null) return null;

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
      // Облачный /join?slug= без url — не sync
      if (uri.queryParameters.containsKey('slug')) return null;
      // Если url не передали — сам хост без /join
      return uri.replace(path: '', queryParameters: {}).toString().replaceAll(RegExp(r'/$'), '');
    }

    if (uri.scheme == kSyncQrScheme || uri.scheme == 'det-app') {
      if (uri.host == kInviteQrHost) return null;
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
