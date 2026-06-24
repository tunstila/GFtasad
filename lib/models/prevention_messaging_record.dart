import 'package:mediflow/models/test_record.dart';

/// Prevention Messaging record captured by a field provider.
///
/// Stored locally (SharedPreferences) for offline-first capture and then upserted
/// to Supabase (`prevention_messaging_records`).
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
  final String? otherReferredFrom;

  final bool educatedOnHivPrevention;
  final bool educatedOnHivTestingOptions;
  final bool educatedOnMalariaPrevention;

  final List<String> referralServices;
  final String? otherReferralService;
  final String? referralFacility;

  final SyncStatus syncStatus;
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
    this.otherReferredFrom,
    required this.educatedOnHivPrevention,
    required this.educatedOnHivTestingOptions,
    required this.educatedOnMalariaPrevention,
    required this.referralServices,
    this.otherReferralService,
    this.referralFacility,
    required this.syncStatus,
    required this.createdAt,
    required this.updatedAt,
  });

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
    String? otherReferredFrom,
    bool? educatedOnHivPrevention,
    bool? educatedOnHivTestingOptions,
    bool? educatedOnMalariaPrevention,
    List<String>? referralServices,
    String? otherReferralService,
    String? referralFacility,
    SyncStatus? syncStatus,
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
        otherReferredFrom: otherReferredFrom ?? this.otherReferredFrom,
        educatedOnHivPrevention: educatedOnHivPrevention ?? this.educatedOnHivPrevention,
        educatedOnHivTestingOptions: educatedOnHivTestingOptions ?? this.educatedOnHivTestingOptions,
        educatedOnMalariaPrevention: educatedOnMalariaPrevention ?? this.educatedOnMalariaPrevention,
        referralServices: referralServices ?? this.referralServices,
        otherReferralService: otherReferralService ?? this.otherReferralService,
        referralFacility: referralFacility ?? this.referralFacility,
        syncStatus: syncStatus ?? this.syncStatus,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

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
        'otherReferredFrom': otherReferredFrom,
        'educatedOnHivPrevention': educatedOnHivPrevention,
        'educatedOnHivTestingOptions': educatedOnHivTestingOptions,
        'educatedOnMalariaPrevention': educatedOnMalariaPrevention,
        'referralServices': referralServices,
        'otherReferralService': otherReferralService,
        'referralFacility': referralFacility,
        'syncStatus': syncStatus.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory PreventionMessagingRecord.fromJson(Map<String, dynamic> json) {
    final rawGroups = json['clientGroups'] ?? json['clientgroups'] ?? json['client_groups'];
    final rawServices = json['referralServices'] ?? json['referralservices'] ?? json['referral_services'];

    List<String> _toStringList(dynamic v) {
      if (v == null) return const [];
      if (v is List) return v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
      return v.toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }

    final statusRaw = (json['syncStatus'] ?? json['sync_status'] ?? 'pending').toString();
    final status = SyncStatus.values.where((s) => s.name == statusRaw).firstOrNull ?? SyncStatus.pending;

    return PreventionMessagingRecord(
      id: json['id'].toString(),
      userId: (json['userId'] ?? json['user_id'] ?? json['userid'] ?? '').toString(),
      clientName: (json['clientName'] ?? json['client_name'] ?? json['clientname'] ?? '').toString(),
      age: (json['age'] is num) ? (json['age'] as num).toInt() : int.tryParse((json['age'] ?? '').toString()) ?? 0,
      phoneNumber: (json['phoneNumber'] ?? json['phone_number'] ?? json['phonenumber'] ?? '').toString(),
      clientId: (json['clientId'] ?? json['client_id'] ?? json['clientid'] ?? '').toString(),
      sex: (json['sex'] ?? '').toString(),
      clientGroups: _toStringList(rawGroups),
      firstTimeVisit: (json['firstTimeVisit'] ?? json['first_time_visit'] ?? json['firsttimevisit'] ?? false) == true,
      referredFrom: (json['referredFrom'] ?? json['referred_from'] ?? json['referredfrom'] ?? '').toString(),
      otherReferredFrom: (json['otherReferredFrom'] ?? json['other_referred_from'] ?? json['otherreferredfrom'])?.toString(),
      educatedOnHivPrevention: (json['educatedOnHivPrevention'] ?? json['educated_on_hiv_prevention'] ?? json['educatedonhivprevention'] ?? false) == true,
      educatedOnHivTestingOptions: (json['educatedOnHivTestingOptions'] ?? json['educated_on_hiv_testing_options'] ?? json['educatedonhivtestingoptions'] ?? false) == true,
      educatedOnMalariaPrevention: (json['educatedOnMalariaPrevention'] ?? json['educated_on_malaria_prevention'] ?? json['educatedonmalariaprevention'] ?? false) == true,
      referralServices: _toStringList(rawServices),
      otherReferralService: (json['otherReferralService'] ?? json['other_referral_service'] ?? json['otherreferralservice'])?.toString(),
      referralFacility: (json['referralFacility'] ?? json['referral_facility'] ?? json['referralfacility'])?.toString(),
      syncStatus: status,
      createdAt: DateTime.tryParse((json['createdAt'] ?? json['created_at'] ?? json['createdat'] ?? '').toString()) ?? DateTime.now(),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? json['updated_at'] ?? json['updatedat'] ?? '').toString()) ?? DateTime.now(),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
