class BusinessAddress {
  final String userId;
  final String businessAddress;
  final String? ward;
  final String state;
  final String lga;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BusinessAddress({
    required this.userId,
    required this.businessAddress,
    required this.state,
    required this.lga,
    this.ward,
    this.latitude,
    this.longitude,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'businessAddress': businessAddress,
    'ward': ward,
    'state': state,
    'lga': lga,
    'latitude': latitude,
    'longitude': longitude,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory BusinessAddress.fromJson(Map<String, dynamic> json) {
    final createdRaw = json['createdAt'] ?? json['created_at'];
    final updatedRaw = json['updatedAt'] ?? json['updated_at'];
    return BusinessAddress(
      userId: (json['userId'] ?? json['user_id'] ?? '').toString(),
      businessAddress: (json['businessAddress'] ?? json['business_address'] ?? '').toString(),
      ward: (json['ward'] ?? json['business_ward'])?.toString(),
      state: (json['state'] ?? '').toString(),
      lga: (json['lga'] ?? '').toString(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? (json['lat'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble() ?? (json['lng'] as num?)?.toDouble(),
      createdAt: createdRaw == null ? DateTime.now() : (DateTime.tryParse(createdRaw.toString()) ?? DateTime.now()),
      updatedAt: updatedRaw == null ? DateTime.now() : (DateTime.tryParse(updatedRaw.toString()) ?? DateTime.now()),
    );
  }

  BusinessAddress copyWith({
    String? userId,
    String? businessAddress,
    String? ward,
    String? state,
    String? lga,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      BusinessAddress(
        userId: userId ?? this.userId,
        businessAddress: businessAddress ?? this.businessAddress,
        ward: ward ?? this.ward,
        state: state ?? this.state,
        lga: lga ?? this.lga,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
