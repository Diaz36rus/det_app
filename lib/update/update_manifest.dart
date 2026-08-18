class UpdateManifest {
  final String version;
  final int build;
  final int minBuild;
  /// Windows portable zip.
  final String url;
  final String sha256;
  final int? size;
  /// Android APK (LAN / тот же latest.json).
  final String androidUrl;
  final String androidSha256;
  final int? androidSize;
  final String notes;
  final int dbVersion;
  final bool critical;

  const UpdateManifest({
    required this.version,
    required this.build,
    this.minBuild = 1,
    required this.url,
    required this.sha256,
    this.size,
    this.androidUrl = '',
    this.androidSha256 = '',
    this.androidSize,
    this.notes = '',
    required this.dbVersion,
    this.critical = false,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final version = json['version']?.toString() ?? '';
    final build = (json['build'] as num?)?.toInt() ?? 0;
    var notes = json['notes']?.toString() ?? '';
    // Mojibake с Windows-публикации: «Сборка» → «РЎР±РѕСЂРєР°».
    if (notes.contains('РЎР±') || notes.contains('РсР') || notes.contains('РЎР')) {
      notes = (version.isNotEmpty && build > 0) ? 'Сборка $version+$build' : '';
    }
    return UpdateManifest(
      version: version,
      build: build,
      minBuild: (json['min_build'] as num?)?.toInt() ?? 1,
      url: json['url']?.toString() ?? '',
      sha256: (json['sha256']?.toString() ?? '').toLowerCase(),
      size: (json['size'] as num?)?.toInt(),
      androidUrl: json['android_url']?.toString() ?? '',
      androidSha256: (json['android_sha256']?.toString() ?? '').toLowerCase(),
      androidSize: (json['android_size'] as num?)?.toInt(),
      notes: notes,
      dbVersion: (json['db_version'] as num?)?.toInt() ?? 0,
      critical: json['critical'] == true,
    );
  }

  bool isNewerThan(int localBuild) => build > localBuild;

  bool get hasWindowsPack => url.isNotEmpty && sha256.isNotEmpty;
  bool get hasAndroidPack => androidUrl.isNotEmpty && androidSha256.isNotEmpty;
}
