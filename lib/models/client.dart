class Client {
  final String id;
  final String providerUserId;
  final String fieldProviderId;
  final String clientId;
  final String name;
  final DateTime? dateOfBirth;
  final String sex;
  final String phoneNumber;
  final DateTime createdAt;
  final DateTime updatedAt;

  Client({
    required this.id,
    required this.providerUserId,
    required this.fieldProviderId,
    required this.clientId,
    required this.name,
    this.dateOfBirth,
    required this.sex,
    required this.phoneNumber,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'providerUserId': providerUserId,
    'fieldProviderId': fieldProviderId,
    'clientId': clientId,
    'name': name,
    'dateOfBirth': dateOfBirth?.toIso8601String(),
    'sex': sex,
    'phoneNumber': phoneNumber,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Client.fromJson(Map<String, dynamic> json) => Client(
    id: json['id'].toString(),
    providerUserId: (json['providerUserId'] ?? json['provider_user_id'] ?? json['provideruserid']).toString(),
    fieldProviderId: (json['fieldProviderId'] ?? json['field_provider_id'] ?? json['fieldproviderid']).toString(),
    clientId: (json['clientId'] ?? json['client_id'] ?? json['clientid']).toString(),
    name: (json['name'] ?? json['clientName'] ?? '').toString(),
    dateOfBirth: (() {
      final raw = json['dateOfBirth'] ?? json['date_of_birth'] ?? json['dob'];
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    })(),
    sex: (json['sex'] ?? '').toString(),
    phoneNumber: (json['phoneNumber'] ?? json['phone_number'] ?? json['phone'] ?? '').toString(),
    createdAt: DateTime.tryParse((json['createdAt'] ?? json['created_at'] ?? '').toString()) ?? DateTime.now(),
    updatedAt: DateTime.tryParse((json['updatedAt'] ?? json['updated_at'] ?? '').toString()) ?? DateTime.now(),
  );

  Client copyWith({
    String? id,
    String? providerUserId,
    String? fieldProviderId,
    String? clientId,
    String? name,
    DateTime? dateOfBirth,
    String? sex,
    String? phoneNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Client(
    id: id ?? this.id,
    providerUserId: providerUserId ?? this.providerUserId,
    fieldProviderId: fieldProviderId ?? this.fieldProviderId,
    clientId: clientId ?? this.clientId,
    name: name ?? this.name,
    dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    sex: sex ?? this.sex,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
