enum HealthProgram { malaria, hiv, tb }

enum VisitType { newVisit, returnVisit }

enum HIVTestType { kitDistributed, assisted, unassisted, reactive, nonReactive }

enum HIVResult { confirmedPositive, confirmedNegative }

enum HIVLinkage { referred, linked }

/// Expanded HIV recording model (new flow).
enum HIVPreviousTesting {
  notPreviouslyTested,
  previouslyTestedNegative,
  previouslyTestedPositive,
  previouslyTestedPositiveNotOnCare,
}

enum HTSType { hivst, determine }

enum HIVSTKitType { oral, bloodBased }

enum HIVSTServiceDeliveryModel { assisted, unassisted }

enum HIVTestResult { reactive, nonReactive }

enum TBScreening { tbScreened, tbPresumptive }

enum SyncStatus { pending, syncing, synced, failed }

class TestRecord {
  final String id;
  /// Stable idempotency key for offline/online sync.
  ///
  /// - Generated client-side the first time a record is saved locally.
  /// - Sent to Supabase during sync.
  /// - Backed by a unique constraint in the database.
  final String clientGeneratedId;
  final String userId;
  final HealthProgram program;
  final String clientName;
  final String clientId;
  /// Numeric age (0-100). New standard.
  final int? age;
  /// Legacy age band (kept for backwards compatibility with older records).
  final String? ageBand;
  final DateTime? dateOfBirth;
  final String? phoneNumber;
  final DateTime testDate;
  final String sex;
  final bool? pregnant;
  final VisitType visitType;

  // Malaria-specific (expanded form)
  final String? clientAddress;
  final List<String>? clientGroups;
  final bool? firstTimeVisit;
  final String? referredFrom;
  final String? otherReferralSource;
  final List<String>? symptomsPresented;
  /// Convenience string for malaria mRDT result: "Positive" | "Negative".
  /// (The legacy booleans `mRDTTested` + `mRDTPositive` are still preserved.)
  final String? mRDTResult;
  final bool? referralForDangerSigns;
  final String? dangerSignsReferralFacility;

  // Malaria specific (legacy)
  final bool? feverPresented;
  final bool? mRDTTested;
  final bool? mRDTPositive;
  final bool? actGiven;
  /// New malaria field: categorical ACT given value (TopMal | Others | None).
  ///
  /// Backwards compatibility: legacy [actGiven] boolean may still exist on older rows.
  final String? actGivenOption;
  
  // HIV specific
  final bool? hivCounselling;
  final HIVTestType? hivstType;
  final HIVResult? determineTest;
  final HIVLinkage? artLinkage;
  final String? referralFacility;

  // Expanded HIV flow fields
  final HIVPreviousTesting? hivPreviousTesting;
  final HTSType? htsType;
  final HIVSTKitType? hivstKitType;
  final HIVSTServiceDeliveryModel? hivstServiceDeliveryModel;
  final HIVTestResult? hivTestResult;
  final List<String>? tbSymptomsPresented;
  final List<String>? referralServices;
  final String? otherReferralService;

  final bool? prepAssessed;
  final bool? prepEligible;
  final bool? prepOffered;
  final bool? prepAccepted;
  final bool? prepStarted;
  final bool? prepContinued;
  final String? prepRefSource;
  
  // TB specific
  final TBScreening? tbScreening;
  final String? notes;

  /// Remote primary key (if the backend assigns a different id than local [id]).
  /// In many deployments, the client uses [id] as the primary key; this stays null.
  final String? remoteId;

  /// Sync diagnostics (kept locally; may be null on older records).
  final String? lastError;
  final int retryCount;
  final DateTime? lastAttemptedAt;
  
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  TestRecord({
    required this.id,
    required this.clientGeneratedId,
    required this.userId,
    required this.program,
    required this.clientName,
    required this.clientId,
    this.age,
    this.ageBand,
    this.dateOfBirth,
    this.phoneNumber,
    required this.testDate,
    required this.sex,
    this.pregnant,
    required this.visitType,
    this.clientAddress,
    this.clientGroups,
    this.firstTimeVisit,
    this.referredFrom,
    this.otherReferralSource,
    this.symptomsPresented,
    this.mRDTResult,
    this.referralForDangerSigns,
    this.dangerSignsReferralFacility,
    this.feverPresented,
    this.mRDTTested,
    this.mRDTPositive,
    this.actGiven,
    this.actGivenOption,
    this.hivCounselling,
    this.hivstType,
    this.determineTest,
    this.artLinkage,
    this.referralFacility,
    this.hivPreviousTesting,
    this.htsType,
    this.hivstKitType,
    this.hivstServiceDeliveryModel,
    this.hivTestResult,
    this.tbSymptomsPresented,
    this.referralServices,
    this.otherReferralService,
    this.prepAssessed,
    this.prepEligible,
    this.prepOffered,
    this.prepAccepted,
    this.prepStarted,
    this.prepContinued,
    this.prepRefSource,
    this.tbScreening,
    this.notes,
    this.remoteId,
    this.lastError,
    this.retryCount = 0,
    this.lastAttemptedAt,
    this.syncStatus = SyncStatus.pending,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'clientGeneratedId': clientGeneratedId,
    'userId': userId,
    'program': program.name,
    'clientName': clientName,
    'clientId': clientId,
    'age': age,
    'ageBand': ageBand,
    'dateOfBirth': dateOfBirth?.toIso8601String(),
    'phoneNumber': phoneNumber,
    'testDate': testDate.toIso8601String(),
    'sex': sex,
    'pregnant': pregnant,
    'visitType': visitType.name,
    'clientAddress': clientAddress,
    'clientGroups': clientGroups,
    'firstTimeVisit': firstTimeVisit,
    'referredFrom': referredFrom,
    'otherReferralSource': otherReferralSource,
    'symptomsPresented': symptomsPresented,
    'mRDTResult': mRDTResult,
    'referralForDangerSigns': referralForDangerSigns,
    'dangerSignsReferralFacility': dangerSignsReferralFacility,
    'feverPresented': feverPresented,
    'mRDTTested': mRDTTested,
    'mRDTPositive': mRDTPositive,
    'actGiven': actGiven,
    'actGivenOption': actGivenOption,
    'hivCounselling': hivCounselling,
    'hivstType': hivstType?.name,
    'determineTest': determineTest?.name,
    'artLinkage': artLinkage?.name,
    'referralFacility': referralFacility,
    'hivPreviousTesting': hivPreviousTesting?.name,
    'htsType': htsType?.name,
    'hivstKitType': hivstKitType?.name,
    'hivstServiceDeliveryModel': hivstServiceDeliveryModel?.name,
    'hivTestResult': hivTestResult?.name,
    'tbSymptomsPresented': tbSymptomsPresented,
    'referralServices': referralServices,
    'otherReferralService': otherReferralService,
    'prepAssessed': prepAssessed,
    'prepEligible': prepEligible,
    'prepOffered': prepOffered,
    'prepAccepted': prepAccepted,
    'prepStarted': prepStarted,
    'prepContinued': prepContinued,
    'prepRefSource': prepRefSource,
    'tbScreening': tbScreening?.name,
    'notes': notes,
    'remoteId': remoteId,
    'lastError': lastError,
    'retryCount': retryCount,
    'lastAttemptedAt': lastAttemptedAt?.toIso8601String(),
    'syncStatus': syncStatus.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory TestRecord.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    // Backwards compatibility: older local/offline payloads won't have this.
    final clientGeneratedId = (json['clientGeneratedId'] ?? json['client_generated_id'] ?? json['clientgeneratedid'] ?? id).toString();
    final rawTestDate = json['testDate'] ?? json['test_date'] ?? json['testdate'];
    final testDate = rawTestDate == null ? DateTime.now() : DateTime.parse(rawTestDate.toString());
    final rawCreated = json['createdAt'] ?? json['created_at'] ?? json['createdat'];
    final rawUpdated = json['updatedAt'] ?? json['updated_at'] ?? json['updatedat'];
    final createdAt = rawCreated == null ? testDate : DateTime.parse(rawCreated.toString());
    final updatedAt = rawUpdated == null ? createdAt : DateTime.parse(rawUpdated.toString());
    final rawSync = (json['syncStatus'] ?? json['sync_status'] ?? json['syncstatus'])?.toString();
    final syncStatus = SyncStatus.values.firstWhere((e) => e.name == rawSync, orElse: () => SyncStatus.pending);

    return TestRecord(
      id: id,
      clientGeneratedId: clientGeneratedId,
      userId: (json['userId'] ?? json['user_id'] ?? json['userid'] ?? '').toString(),
    program: (() {
      final raw = (json['program'] ?? json['interventionArea'] ?? json['intervention_area'] ?? json['healthProgram'] ?? json['health_program'])?.toString();
      final normalized = (raw ?? '').trim().toLowerCase();
      if (normalized.isEmpty) return HealthProgram.malaria;
      // Accept common variants like "HIV/TB", "hiv_tb", etc.
      final token = normalized.replaceAll(RegExp(r'[^a-z]'), '');
      if (token.contains('malaria')) return HealthProgram.malaria;
      if (token == 'tb' || token.contains('tuberculosis')) return HealthProgram.tb;
      if (token.contains('hiv')) return HealthProgram.hiv;
      return HealthProgram.values.firstWhere((e) => e.name == normalized, orElse: () => HealthProgram.malaria);
    })(),
    clientName: json['clientName'],
    clientId: json['clientId'],
    age: (json['age'] is num) ? (json['age'] as num).toInt() : int.tryParse((json['age'] ?? '').toString()),
    ageBand: json['ageBand'],
    dateOfBirth: (() {
      final raw = json['dateOfBirth'] ?? json['dob'] ?? json['date_of_birth'];
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    })(),
    phoneNumber: json['phoneNumber'] ?? json['phone_number'] ?? json['phone'],
    testDate: testDate,
    sex: (json['sex']?.toString() == 'Others') ? 'Other' : (json['sex']?.toString() ?? ''),
    pregnant: json['pregnant'],
    visitType: VisitType.values.firstWhere((e) => e.name == json['visitType']),
    clientAddress: json['clientAddress'] ?? json['client_address'] ?? json['clientaddress'],
    clientGroups: (() {
      final raw = json['clientGroups'] ?? json['client_groups'] ?? json['clientgroups'];
      if (raw == null) return null;
      if (raw is List) return raw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
      // Accept comma-separated legacy values if any.
      return raw.toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    })(),
    firstTimeVisit: json['firstTimeVisit'] ?? json['first_time_visit'] ?? json['firsttimevisit'],
    referredFrom: json['referredFrom'] ?? json['referred_from'] ?? json['referredfrom'],
    otherReferralSource: json['otherReferralSource'] ?? json['other_referral_source'] ?? json['otherreferralsource'],
    symptomsPresented: (() {
      final raw = json['symptomsPresented'] ?? json['symptoms_presented'] ?? json['symptomspresented'];
      if (raw == null) return null;
      if (raw is List) return raw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
      return raw.toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    })(),
    mRDTResult: json['mRDTResult'] ?? json['mrdt_result'] ?? json['mrdtresult'],
    referralForDangerSigns: json['referralForDangerSigns'] ?? json['referral_for_danger_signs'] ?? json['referralfordangersigns'],
    dangerSignsReferralFacility: json['dangerSignsReferralFacility'] ?? json['danger_signs_referral_facility'] ?? json['dangersignsreferralfacility'],
    feverPresented: json['feverPresented'],
    mRDTTested: json['mRDTTested'],
    mRDTPositive: json['mRDTPositive'],
    actGiven: json['actGiven'],
    actGivenOption: (json['actGivenOption'] ?? json['act_given_option'] ?? json['actgivenoption'])?.toString(),
    hivCounselling: json['hivCounselling'],
    hivstType: json['hivstType'] != null ? HIVTestType.values.firstWhere((e) => e.name == json['hivstType']) : null,
    determineTest: json['determineTest'] != null ? HIVResult.values.firstWhere((e) => e.name == json['determineTest']) : null,
    artLinkage: json['artLinkage'] != null ? HIVLinkage.values.firstWhere((e) => e.name == json['artLinkage']) : null,
    referralFacility: json['referralFacility'],
    hivPreviousTesting: (() {
      final raw = json['hivPreviousTesting'] ?? json['hiv_previous_testing'] ?? json['hivprevioustesting'];
      if (raw == null) return null;
      final token = raw.toString();
      for (final e in HIVPreviousTesting.values) {
        if (e.name == token) return e;
      }
      return null;
    })(),
    htsType: (() {
      final raw = json['htsType'] ?? json['hts_type'] ?? json['htstype'];
      if (raw == null) return null;
      final token = raw.toString();
      for (final e in HTSType.values) {
        if (e.name == token) return e;
      }
      return null;
    })(),
    hivstKitType: (() {
      final raw = json['hivstKitType'] ?? json['hivst_kit_type'] ?? json['hivstkittype'];
      if (raw == null) return null;
      final token = raw.toString();
      for (final e in HIVSTKitType.values) {
        if (e.name == token) return e;
      }
      return null;
    })(),
    hivstServiceDeliveryModel: (() {
      final raw = json['hivstServiceDeliveryModel'] ?? json['hivst_service_delivery_model'] ?? json['hivstservicedeliverymodel'];
      if (raw == null) return null;
      final token = raw.toString();
      for (final e in HIVSTServiceDeliveryModel.values) {
        if (e.name == token) return e;
      }
      return null;
    })(),
    hivTestResult: (() {
      final raw = json['hivTestResult'] ?? json['hiv_test_result'] ?? json['hivtestresult'];
      if (raw == null) return null;
      final token = raw.toString();
      for (final e in HIVTestResult.values) {
        if (e.name == token) return e;
      }
      return null;
    })(),
    tbSymptomsPresented: (() {
      final raw = json['tbSymptomsPresented'] ?? json['tb_symptoms_presented'] ?? json['tbsymptomspresented'];
      if (raw == null) return null;
      if (raw is List) return raw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
      return raw.toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    })(),
    referralServices: (() {
      final raw = json['referralServices'] ?? json['referral_services'] ?? json['referralservices'];
      if (raw == null) return null;
      if (raw is List) return raw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
      return raw.toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    })(),
    otherReferralService: json['otherReferralService'] ?? json['other_referral_service'] ?? json['otherreferralservice'],
    prepAssessed: json['prepAssessed'],
    prepEligible: json['prepEligible'],
    prepOffered: json['prepOffered'],
    prepAccepted: json['prepAccepted'],
    prepStarted: json['prepStarted'],
    prepContinued: json['prepContinued'],
    prepRefSource: json['prepRefSource'],
    tbScreening: json['tbScreening'] != null ? TBScreening.values.firstWhere((e) => e.name == json['tbScreening']) : null,
    notes: json['notes'],
    remoteId: (json['remoteId'] ?? json['remote_id'] ?? json['remoteid'])?.toString(),
    lastError: (json['lastError'] ?? json['last_error'] ?? json['lasterror'])?.toString(),
    retryCount: (json['retryCount'] is num) ? (json['retryCount'] as num).toInt() : int.tryParse((json['retryCount'] ?? '').toString()) ?? 0,
    lastAttemptedAt: (() {
      final raw = json['lastAttemptedAt'] ?? json['last_attempted_at'] ?? json['lastattemptedat'];
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    })(),
    syncStatus: syncStatus,
    createdAt: createdAt,
    updatedAt: updatedAt,
    );
  }

  TestRecord copyWith({
    String? id,
    String? clientGeneratedId,
    String? userId,
    HealthProgram? program,
    String? clientName,
    String? clientId,
    int? age,
    String? ageBand,
    DateTime? dateOfBirth,
    String? phoneNumber,
    DateTime? testDate,
    String? sex,
    bool? pregnant,
    VisitType? visitType,
    String? clientAddress,
    List<String>? clientGroups,
    bool? firstTimeVisit,
    String? referredFrom,
    String? otherReferralSource,
    List<String>? symptomsPresented,
    String? mRDTResult,
    bool? referralForDangerSigns,
    String? dangerSignsReferralFacility,
    bool? feverPresented,
    bool? mRDTTested,
    bool? mRDTPositive,
    bool? actGiven,
    String? actGivenOption,
    bool? hivCounselling,
    HIVTestType? hivstType,
    HIVResult? determineTest,
    HIVLinkage? artLinkage,
    String? referralFacility,
    HIVPreviousTesting? hivPreviousTesting,
    HTSType? htsType,
    HIVSTKitType? hivstKitType,
    HIVSTServiceDeliveryModel? hivstServiceDeliveryModel,
    HIVTestResult? hivTestResult,
    List<String>? tbSymptomsPresented,
    List<String>? referralServices,
    String? otherReferralService,
    bool? prepAssessed,
    bool? prepEligible,
    bool? prepOffered,
    bool? prepAccepted,
    bool? prepStarted,
    bool? prepContinued,
    String? prepRefSource,
    TBScreening? tbScreening,
    String? notes,
    String? remoteId,
    String? lastError,
    int? retryCount,
    DateTime? lastAttemptedAt,
    SyncStatus? syncStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => TestRecord(
    id: id ?? this.id,
    clientGeneratedId: clientGeneratedId ?? this.clientGeneratedId,
    userId: userId ?? this.userId,
    program: program ?? this.program,
    clientName: clientName ?? this.clientName,
    clientId: clientId ?? this.clientId,
    age: age ?? this.age,
    ageBand: ageBand ?? this.ageBand,
    dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    testDate: testDate ?? this.testDate,
    sex: sex ?? this.sex,
    pregnant: pregnant ?? this.pregnant,
    visitType: visitType ?? this.visitType,
    clientAddress: clientAddress ?? this.clientAddress,
    clientGroups: clientGroups ?? this.clientGroups,
    firstTimeVisit: firstTimeVisit ?? this.firstTimeVisit,
    referredFrom: referredFrom ?? this.referredFrom,
    otherReferralSource: otherReferralSource ?? this.otherReferralSource,
    symptomsPresented: symptomsPresented ?? this.symptomsPresented,
    mRDTResult: mRDTResult ?? this.mRDTResult,
    referralForDangerSigns: referralForDangerSigns ?? this.referralForDangerSigns,
    dangerSignsReferralFacility: dangerSignsReferralFacility ?? this.dangerSignsReferralFacility,
    feverPresented: feverPresented ?? this.feverPresented,
    mRDTTested: mRDTTested ?? this.mRDTTested,
    mRDTPositive: mRDTPositive ?? this.mRDTPositive,
    actGiven: actGiven ?? this.actGiven,
    actGivenOption: actGivenOption ?? this.actGivenOption,
    hivCounselling: hivCounselling ?? this.hivCounselling,
    hivstType: hivstType ?? this.hivstType,
    determineTest: determineTest ?? this.determineTest,
    artLinkage: artLinkage ?? this.artLinkage,
    referralFacility: referralFacility ?? this.referralFacility,
    hivPreviousTesting: hivPreviousTesting ?? this.hivPreviousTesting,
    htsType: htsType ?? this.htsType,
    hivstKitType: hivstKitType ?? this.hivstKitType,
    hivstServiceDeliveryModel: hivstServiceDeliveryModel ?? this.hivstServiceDeliveryModel,
    hivTestResult: hivTestResult ?? this.hivTestResult,
    tbSymptomsPresented: tbSymptomsPresented ?? this.tbSymptomsPresented,
    referralServices: referralServices ?? this.referralServices,
    otherReferralService: otherReferralService ?? this.otherReferralService,
    prepAssessed: prepAssessed ?? this.prepAssessed,
    prepEligible: prepEligible ?? this.prepEligible,
    prepOffered: prepOffered ?? this.prepOffered,
    prepAccepted: prepAccepted ?? this.prepAccepted,
    prepStarted: prepStarted ?? this.prepStarted,
    prepContinued: prepContinued ?? this.prepContinued,
    prepRefSource: prepRefSource ?? this.prepRefSource,
    tbScreening: tbScreening ?? this.tbScreening,
    notes: notes ?? this.notes,
    remoteId: remoteId ?? this.remoteId,
    lastError: lastError ?? this.lastError,
    retryCount: retryCount ?? this.retryCount,
    lastAttemptedAt: lastAttemptedAt ?? this.lastAttemptedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
