class AuthTokens {
  final String accessToken;
  final String refreshToken;

  const AuthTokens({required this.accessToken, required this.refreshToken});

  Map<String, Object?> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
      };

  factory AuthTokens.fromJson(Map<String, dynamic> j) => AuthTokens(
        accessToken: j['access_token']?.toString() ?? '',
        refreshToken: j['refresh_token']?.toString() ?? '',
      );

  bool get isValid => accessToken.isNotEmpty && refreshToken.isNotEmpty;
}

class AuthUser {
  final int id;
  final String email;
  final String? phone;
  final String fullName;
  final bool isPlatformAdmin;
  final int? companyId;
  final String? companySlug;
  final String? companyName;
  final List<String> roles;
  final List<int> branchIds;
  final List<String> permissions;
  final bool pendingAssignment;
  final int? masterId;
  final List<String> workshops;

  const AuthUser({
    required this.id,
    required this.email,
    this.phone,
    required this.fullName,
    required this.isPlatformAdmin,
    this.companyId,
    this.companySlug,
    this.companyName,
    this.roles = const [],
    this.branchIds = const [],
    this.permissions = const [],
    this.pendingAssignment = false,
    this.masterId,
    this.workshops = const [],
  });

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: (j['id'] as num?)?.toInt() ?? 0,
        email: j['email']?.toString() ?? '',
        phone: j['phone']?.toString(),
        fullName: j['full_name']?.toString() ?? '',
        isPlatformAdmin: j['is_platform_admin'] == true,
        companyId: (j['company_id'] as num?)?.toInt(),
        companySlug: j['company_slug']?.toString(),
        companyName: j['company_name']?.toString(),
        roles: (j['roles'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        branchIds: (j['branch_ids'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const [],
        permissions:
            (j['permissions'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        pendingAssignment: j['pending_assignment'] == true,
        masterId: (j['master_id'] as num?)?.toInt(),
        workshops:
            (j['workshops'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );

  String get displayLabel {
    if (fullName.trim().isNotEmpty) return fullName.trim();
    if (email.isNotEmpty) return email;
    return phone ?? 'Пользователь';
  }

  /// Название студии для UI: имя, иначе код.
  String get studioDisplayName {
    final n = companyName?.trim();
    if (n != null && n.isNotEmpty) return n;
    final s = companySlug?.trim();
    if (s != null && s.isNotEmpty) return s;
    return 'Без студии';
  }
}
