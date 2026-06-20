class PreventionMessagingRecord {
  final String id;
  final String userId;

  final String clientName;
  final int age;
  final String phoneNumber;
  final String clientId;

  final String sex;
  final List<String> clientGroups;
  final bool firstTimeVisit;
  final String referredFrom;

  final bool educatedOnHivPrevention;
  final bool educatedOnHivTestingOptions;
  final bool educatedOnMalariaPreventionTreatment;

  final DateTime createdAt;
  final DateTime updatedAt;

  const PreventionMessagingRecord({
    required this.id,
    required this.userId,
    required this.clientName,
    required this.age,
    required this.phoneNumber,
    required this.clientId,
    required this.sex,
    required this.clientGroups,
    required this.firstTimeVisit,
    required this.referredFrom,
    required this.educatedOnHivPrevention,
    required this.educatedOnHivTestingOptions,
    required this.educatedOnMalariaPreventionTreatment,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'clientName': clientName,
    'age': age,
    'phoneNumber': phoneNumber,
    'clientId': clientId,
    'sex': sex,
    'clientGroups': clientGroups,
    'firstTimeVisit': firstTimeVisit,
    'referredFrom': referredFrom,
    'educatedOnHivPrevention': educatedOnHivPrevention,
    'educatedOnHivTestingOptions': educatedOnHivTestingOptions,
    'educatedOnMalariaPreventionTreatment': educatedOnMalariaPreventionTreatment,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory PreventionMessagingRecord.fromJson(Map<String, dynamic> json) {
    final groupsRaw = json['clientGroups'] ?? json['client_groups'];
    final groups = (groupsRaw is List) ? groupsRaw.map((e) => e.toString()).toList() : <String>[];
    return PreventionMessagingRecord(
      id: json['id'].toString(),
      userId: (json['userId'] ?? json['user_id'] ?? '').toString(),
      clientName: (json['clientName'] ?? '').toString(),
      age: (json['age'] is num) ? (json['age'] as num).toInt() : int.parse(json['age'].toString()),
      phoneNumber: (json['phoneNumber'] ?? json['phone_number'] ?? '').toString(),
      clientId: (json['clientId'] ?? json['client_id'] ?? '').toString(),
      sex: (json['sex'] ?? '').toString(),
      clientGroups: groups,
      firstTimeVisit: json['firstTimeVisit'] == true,
      referredFrom: (json['referredFrom'] ?? '').toString(),
      educatedOnHivPrevention: json['educatedOnHivPrevention'] == true,
      educatedOnHivTestingOptions: json['educatedOnHivTestingOptions'] == true,
      educatedOnMalariaPreventionTreatment: json['educatedOnMalariaPreventionTreatment'] == true,
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
    );
  }

  PreventionMessagingRecord copyWith({
    String? id,
    String? userId,
    String? clientName,
    int? age,
    String? phoneNumber,
    String? clientId,
    String? sex,
    List<String>? clientGroups,
    bool? firstTimeVisit,
    String? referredFrom,
    bool? educatedOnHivPrevention,
    bool? educatedOnHivTestingOptions,
    bool? educatedOnMalariaPreventionTreatment,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      PreventionMessagingRecord(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        clientName: clientName ?? this.clientName,
        age: age ?? this.age,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        clientId: clientId ?? this.clientId,
        sex: sex ?? this.sex,
        clientGroups: clientGroups ?? this.clientGroups,
        firstTimeVisit: firstTimeVisit ?? this.firstTimeVisit,
        referredFrom: referredFrom ?? this.referredFrom,
        educatedOnHivPrevention: educatedOnHivPrevention ?? this.educatedOnHivPrevention,
        educatedOnHivTestingOptions: educatedOnHivTestingOptions ?? this.educatedOnHivTestingOptions,
        educatedOnMalariaPreventionTreatment: educatedOnMalariaPreventionTreatment ?? this.educatedOnMalariaPreventionTreatment,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
