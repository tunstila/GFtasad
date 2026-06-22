enum UserRole {
  fieldProvider,
  supplier,
  admin,
  stateMalaria,
  stateHIVTB,
  nationalMalaria,
  nationalHIVTB,
  /// SFH team members: global visibility (admin view), but read-only.
  sfhTeam,
  superAdmin
}

enum UserApprovalStatus { pending, approved, rejected }

/// Admin scope is independent of the base role a user signed up with.
///
/// - [none]: normal access based on [UserRole]
/// - [viewOnly]: global view-only (SFH-like)
/// - [full]: full super admin permissions
enum AdminScope { none, viewOnly, full }

extension UserRolePermissions on UserRole {
  bool get hasGlobalView => this == UserRole.admin || this == UserRole.sfhTeam || this == UserRole.superAdmin;

  /// Ability to create/update operational data (tests, stock, confirmations).
  /// SFH team is explicitly view-only.
  bool get canMutateOperationalData => this != UserRole.sfhTeam && this != UserRole.admin && this != UserRole.nationalMalaria && this != UserRole.nationalHIVTB;

  bool get canRecordTests => this == UserRole.fieldProvider || this == UserRole.superAdmin;
  bool get canAdjustStock => this == UserRole.fieldProvider || this == UserRole.superAdmin;
  bool get canConfirmDeliveries => this == UserRole.fieldProvider || this == UserRole.superAdmin;
}

enum ProviderType { chp, cp, ppmv }

class User {
  final String id;
  final String username;
  /// Human-friendly full name (when available). Separate from [username] which may be a login handle.
  final String? name;
  /// Auth email (may be synthetic for username-only accounts).
  final String email;

  /// Optional real contact email. For normal accounts this matches [email].
  final String? contactEmail;

  /// True when [email] is synthetic like <uuid>@auth.local.invalid.
  final bool isSyntheticAuthEmail;
  final UserRole role;
  final UserApprovalStatus approvalStatus;
  final DateTime? approvedAt;
  final String? approvedBy;
  final AdminScope adminScope;
  final String? facilityName;
  final ProviderType? providerType;
  final String? businessAddress;
  final String? ward;
  final String? lga;
  final String? state;
  /// State-scoped FieldProvider unique ID (e.g., ANB-0001). Only for field providers.
  final String? fieldProviderUniqueId;
  final double? latitude;
  final double? longitude;
  final bool forcePasswordChange;
  final DateTime? lastLogin;
  final DateTime createdAt;
  final DateTime updatedAt;

  User({
    required this.id,
    required this.username,
    this.name,
    required this.email,
    this.contactEmail,
    this.isSyntheticAuthEmail = false,
    required this.role,
    this.approvalStatus = UserApprovalStatus.pending,
    this.approvedAt,
    this.approvedBy,
    this.adminScope = AdminScope.none,
    this.facilityName,
    this.providerType,
    this.businessAddress,
    this.ward,
    this.lga,
    this.state,
    this.fieldProviderUniqueId,
    this.latitude,
    this.longitude,
    this.forcePasswordChange = false,
    this.lastLogin,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isApproved => approvalStatus == UserApprovalStatus.approved;

  /// Effective role after applying [adminScope] overrides.
  UserRole get effectiveRole {
    switch (adminScope) {
      case AdminScope.full:
        return UserRole.superAdmin;
      case AdminScope.viewOnly:
        return UserRole.sfhTeam;
      case AdminScope.none:
        return role;
    }
  }

  bool get hasSuperAdminFull => effectiveRole == UserRole.superAdmin;
  bool get hasGlobalView => effectiveRole.hasGlobalView;
  bool get canMutateOperationalData => effectiveRole.canMutateOperationalData;

  /// Email that is safe to show in UI.
  ///
  /// For username-only accounts we intentionally hide the synthetic auth email.
  String get displayEmail {
    final c = (contactEmail ?? '').trim();
    if (isSyntheticAuthEmail) return c;
    return c.isNotEmpty ? c : email;
  }

  /// Name that is safe to show in UI.
  ///
  /// Prefers [name] (full name) and falls back to [username].
  String get displayName {
    final n = (name ?? '').trim();
    if (n.isNotEmpty) return n;
    return username.trim().isNotEmpty ? username.trim() : 'User';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'name': name,
    'email': email,
    'contactEmail': contactEmail,
    'isSyntheticAuthEmail': isSyntheticAuthEmail,
    'role': role.name,
    'approvalStatus': approvalStatus.name,
    'approvedAt': approvedAt?.toIso8601String(),
    'approvedBy': approvedBy,
    'adminScope': adminScope.name,
    'facilityName': facilityName,
    'providerType': providerType?.name,
    'businessAddress': businessAddress,
    'ward': ward,
    'lga': lga,
    'state': state,
    'fieldProviderUniqueId': fieldProviderUniqueId,
    'latitude': latitude,
    'longitude': longitude,
    'forcePasswordChange': forcePasswordChange,
    'lastLogin': lastLogin?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'],
    name: (json['name'] ?? json['full_name'] ?? json['fullName'])?.toString(),
    username: (json['username'] ?? json['full_name'] ?? json['fullName'] ?? '').toString().isNotEmpty
        ? (json['username'] ?? json['full_name'] ?? json['fullName']).toString()
        : 'Unknown',
    email: (json['email'] ?? '').toString(),
    contactEmail: (json['contactEmail'] ?? json['contact_email'])?.toString(),
    isSyntheticAuthEmail: (json['isSyntheticAuthEmail'] ?? json['is_synthetic_auth_email'] ?? false) == true,
    role: (() {
      final raw = json['role']?.toString();
      if (raw == null) return UserRole.fieldProvider;
      return UserRole.values.firstWhere((e) => e.name == raw, orElse: () => UserRole.fieldProvider);
    })(),
    approvalStatus: (() {
      final raw = json['approvalstatus']?.toString() ?? json['approvalStatus']?.toString() ?? json['approval_status']?.toString();
      if (raw == null) return (json['isApproved'] == true ? UserApprovalStatus.approved : UserApprovalStatus.approved);
      return UserApprovalStatus.values.firstWhere((e) => e.name == raw, orElse: () => UserApprovalStatus.approved);
    })(),
    approvedAt: (() {
      final raw = json['approvedAt'] ?? json['approved_at'];
      return raw == null ? null : DateTime.tryParse(raw.toString());
    })(),
    approvedBy: json['approvedBy'],
    adminScope: (() {
      final raw = json['adminScope']?.toString() ?? json['admin_scope']?.toString();
      if (raw == null) return AdminScope.none;
      return AdminScope.values.firstWhere((e) => e.name == raw, orElse: () => AdminScope.none);
    })(),
    facilityName: json['facilityName'],
    providerType: (() {
      final raw = json['providerType']?.toString() ?? json['provider_type']?.toString();
      if (raw == null) return null;
      return ProviderType.values.firstWhere((e) => e.name == raw, orElse: () => ProviderType.ppmv);
    })(),
    businessAddress: json['businessAddress'] ?? json['business_address'],
    ward: json['ward'] ?? json['business_ward'],
    lga: json['lga'],
    state: json['state'],
    fieldProviderUniqueId: json['fieldProviderUniqueId'] ?? json['fieldprovideruniqueid'] ?? json['field_provider_unique_id'] ?? json['fieldproviderid'] ?? json['field_provider_id'],
    latitude: (json['latitude'] as num?)?.toDouble() ?? (json['lat'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble() ?? (json['lng'] as num?)?.toDouble(),
    forcePasswordChange: json['forcePasswordChange'] ?? false,
    lastLogin: (() {
      final raw = json['lastLogin'] ?? json['last_login'];
      return raw == null ? null : DateTime.tryParse(raw.toString());
    })(),
    createdAt: (() {
      final raw = json['createdAt'] ?? json['created_at'];
      return raw == null ? DateTime.now() : (DateTime.tryParse(raw.toString()) ?? DateTime.now());
    })(),
    updatedAt: (() {
      final raw = json['updatedAt'] ?? json['updated_at'];
      return raw == null ? DateTime.now() : (DateTime.tryParse(raw.toString()) ?? DateTime.now());
    })(),
  );

  User copyWith({
    String? id,
    String? username,
    String? name,
    String? email,
    String? contactEmail,
    bool? isSyntheticAuthEmail,
    UserRole? role,
    UserApprovalStatus? approvalStatus,
    DateTime? approvedAt,
    String? approvedBy,
    AdminScope? adminScope,
    String? facilityName,
    ProviderType? providerType,
    String? businessAddress,
    String? ward,
    String? lga,
    String? state,
    String? fieldProviderUniqueId,
    double? latitude,
    double? longitude,
    bool? forcePasswordChange,
    DateTime? lastLogin,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => User(
    id: id ?? this.id,
    username: username ?? this.username,
    name: name ?? this.name,
    email: email ?? this.email,
    contactEmail: contactEmail ?? this.contactEmail,
    isSyntheticAuthEmail: isSyntheticAuthEmail ?? this.isSyntheticAuthEmail,
    role: role ?? this.role,
    approvalStatus: approvalStatus ?? this.approvalStatus,
    approvedAt: approvedAt ?? this.approvedAt,
    approvedBy: approvedBy ?? this.approvedBy,
    adminScope: adminScope ?? this.adminScope,
    facilityName: facilityName ?? this.facilityName,
    providerType: providerType ?? this.providerType,
    businessAddress: businessAddress ?? this.businessAddress,
    ward: ward ?? this.ward,
    lga: lga ?? this.lga,
    state: state ?? this.state,
    fieldProviderUniqueId: fieldProviderUniqueId ?? this.fieldProviderUniqueId,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    forcePasswordChange: forcePasswordChange ?? this.forcePasswordChange,
    lastLogin: lastLogin ?? this.lastLogin,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
