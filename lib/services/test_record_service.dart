import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/supabase/supabase_config.dart';
import 'package:uuid/uuid.dart';

class TestRecordService extends ChangeNotifier {
  static const _uuid = Uuid();
  List<TestRecord> _records = [];
  bool _isLoading = false;

  bool _backgroundSyncRunning = false;

  TestRecord? _findLocalById(String id) {
    final idx = _records.indexWhere((r) => r.id == id);
    if (idx == -1) return null;
    return _records[idx];
  }

  DateTime? _lifetimeFetchedAt;
  int? _lifetimeCached;

  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSub;

  static bool _isSchemaColumnError(Object e) {
    final msg = e.toString();
    return msg.contains('schema cache') || msg.contains('does not exist') || msg.contains("Could not find the '");
  }

  static String? _extractMissingColumn(Object e) {
    final msg = e.toString();
    final m1 = RegExp(r"Could not find the '([^']+)' column").firstMatch(msg);
    if (m1 != null) return m1.group(1);
    // Example: PostgrestException(message: column test_records.testDate does not exist, ...)
    final m2 = RegExp(r'column\s+[\w\.]+\.(\w+)\s+does not exist').firstMatch(msg);
    if (m2 != null) return m2.group(1);
    return null;
  }

  static String? _ageBandFromAge(int? age) {
    if (age == null) return null;
    if (age < 0) return null;
    if (age <= 4) return '0-4 years';
    if (age <= 14) return '5-14 years';
    if (age <= 24) return '15-24 years';
    if (age <= 34) return '25-34 years';
    if (age <= 44) return '35-44 years';
    if (age <= 54) return '45-54 years';
    if (age <= 64) return '55-64 years';
    return '65+ years';
  }

  static Map<String, dynamic> _maybeBackfillLegacyAgeBand(Map<String, dynamic> payload, {required String ageBandKey, required String ageKey}) {
    // Some older schemas only have ageband/age_band and not age.
    if (payload[ageBandKey] == null) {
      final rawAge = payload[ageKey];
      final age = (rawAge is num) ? rawAge.toInt() : int.tryParse((rawAge ?? '').toString());
      final band = _ageBandFromAge(age);
      if (band != null) payload[ageBandKey] = band;
    }
    return payload;
  }

  Future<void> _upsertTestRecordRemote(TestRecord record) async {
    // Try multiple common schemas. For each payload, retry while stripping missing columns.
    final candidates = <Map<String, dynamic>>[
      Map<String, dynamic>.from(_toDbJson(record, snakeCase: false)),
      Map<String, dynamic>.from(_toDbJson(record, snakeCase: true)),
      Map<String, dynamic>.from(_toDbJsonLower(record)),
    ];

    Object? lastErr;
    for (final original in candidates) {
      final payload = _stripNulls(Map<String, dynamic>.from(original));

      // Ensure legacy age band is present in all payload variants (harmless if column exists).
      if (payload.containsKey('ageBand') && payload.containsKey('age')) {
        _maybeBackfillLegacyAgeBand(payload, ageBandKey: 'ageBand', ageKey: 'age');
      }
      if (payload.containsKey('age_band') && payload.containsKey('age')) {
        _maybeBackfillLegacyAgeBand(payload, ageBandKey: 'age_band', ageKey: 'age');
      }
      if (payload.containsKey('ageband') && payload.containsKey('age')) {
        _maybeBackfillLegacyAgeBand(payload, ageBandKey: 'ageband', ageKey: 'age');
      }

      // Prevent infinite retries if the backend schema is very different.
      for (var attempt = 0; attempt < 10; attempt++) {
        try {
          // Prefer idempotency on client_generated_id when the backend supports it.
          // If the column doesn't exist yet, fall back to id.
          final onConflictCandidates = <String?>[
            payload.containsKey('client_generated_id') ? 'client_generated_id' : null,
            payload.containsKey('clientGeneratedId') ? 'clientGeneratedId' : null,
            'id',
          ].whereType<String>().toList();

          List<Map<String, dynamic>> rows = const [];
          Object? upsertErr;
          for (final conflict in onConflictCandidates) {
            try {
              rows = await SupabaseService.upsert('test_records', payload, onConflict: conflict);
              upsertErr = null;
              break;
            } catch (e) {
              upsertErr = e;
              if (!_isSchemaColumnError(e)) rethrow;
            }
          }
          if (upsertErr != null) throw upsertErr;
          if (rows.isNotEmpty) {
            // Best-effort: keep remote id in local cache when the backend returns it.
            final row = rows.first;
            final remoteId = (row['id'] ?? row['remote_id'] ?? row['remoteId'])?.toString();
            if (remoteId != null && remoteId.trim().isNotEmpty) {
              _replaceLocal(record.copyWith(remoteId: remoteId, updatedAt: DateTime.now()));
            }
          }
          return;
        } catch (e) {
          lastErr = e;
          if (!_isSchemaColumnError(e)) rethrow;

          final missing = _extractMissingColumn(e);
          if (missing == null) break;

          // If backend doesn't have `age`, drop it and rely on age band.
          if (missing == 'age' && payload.containsKey('age')) {
            // Backfill the legacy age band before dropping age.
            if (payload.containsKey('ageBand') && payload.containsKey('age')) {
              _maybeBackfillLegacyAgeBand(payload, ageBandKey: 'ageBand', ageKey: 'age');
            }
            if (payload.containsKey('age_band') && payload.containsKey('age')) {
              _maybeBackfillLegacyAgeBand(payload, ageBandKey: 'age_band', ageKey: 'age');
            }
            if (payload.containsKey('ageband') && payload.containsKey('age')) {
              _maybeBackfillLegacyAgeBand(payload, ageBandKey: 'ageband', ageKey: 'age');
            }
            payload.remove('age');
            continue;
          }

          // Drop the missing column if it exists in our payload.
          if (payload.containsKey(missing)) {
            payload.remove(missing);
            continue;
          }

          // Also handle common case mismatches.
          final altKeys = <String>[
            missing,
            missing.replaceAll('_', ''),
            // Basic camelCase <-> snake_case conversions.
            missing.contains('_')
                ? missing.split('_').asMap().entries.map((e) => e.key == 0 ? e.value : '${e.value[0].toUpperCase()}${e.value.substring(1)}').join()
                : missing.replaceAllMapped(RegExp(r'([A-Z])'), (m) => '_${m.group(1)!.toLowerCase()}'),
          ];
          var removed = false;
          for (final k in altKeys) {
            if (payload.containsKey(k)) {
              payload.remove(k);
              removed = true;
              break;
            }
          }
          if (removed) continue;

          // Can't safely resolve, move to next schema candidate.
          break;
        }
      }
    }

    // If we reached here, none of the candidates worked.
    if (lastErr != null) throw lastErr;
    throw StateError('Unknown Supabase upsert failure for test_records');
  }

  Map<String, dynamic> _stripNulls(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    for (final entry in input.entries) {
      final v = entry.value;
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      out[entry.key] = v;
    }
    return out;
  }

  Map<String, dynamic> _fromDbRow(Map<String, dynamic> row) {
    // Support both camelCase (older app schema) and snake_case (common Postgres style).
    if (row.containsKey('userId') || row.containsKey('testDate')) return _normalizeDates(row);
    final out = <String, dynamic>{};
    for (final entry in row.entries) {
      out[entry.key] = entry.value;
    }
    void mapKey(String snake, String camel) {
      if (out.containsKey(snake) && !out.containsKey(camel)) out[camel] = out[snake];
    }
    void mapKeyLower(String lower, String camel) {
      if (out.containsKey(lower) && !out.containsKey(camel)) out[camel] = out[lower];
    }
    // Program / intervention area aliases (different schema versions).
    mapKey('intervention_area', 'program');
    mapKey('health_program', 'program');
    mapKeyLower('interventionarea', 'program');
    mapKeyLower('healthprogram', 'program');

    mapKey('user_id', 'userId');
    mapKeyLower('userid', 'userId');
    mapKey('client_name', 'clientName');
    mapKeyLower('clientname', 'clientName');
    mapKey('client_id', 'clientId');
    mapKeyLower('clientid', 'clientId');
    mapKey('age_band', 'ageBand');
    mapKeyLower('ageband', 'ageBand');
    mapKey('age', 'age');
    mapKeyLower('age', 'age');
    mapKey('date_of_birth', 'dateOfBirth');
    mapKeyLower('dateofbirth', 'dateOfBirth');
    mapKey('dob', 'dateOfBirth');
    mapKey('phone_number', 'phoneNumber');
    mapKeyLower('phonenumber', 'phoneNumber');
    mapKey('phone', 'phoneNumber');
    mapKey('test_date', 'testDate');
    mapKeyLower('testdate', 'testDate');
    mapKey('visit_type', 'visitType');
    mapKeyLower('visittype', 'visitType');

    // Expanded malaria fields
    mapKey('client_address', 'clientAddress');
    mapKeyLower('clientaddress', 'clientAddress');
    mapKey('client_groups', 'clientGroups');
    mapKeyLower('clientgroups', 'clientGroups');
    mapKey('first_time_visit', 'firstTimeVisit');
    mapKeyLower('firsttimevisit', 'firstTimeVisit');
    mapKey('referred_from', 'referredFrom');
    mapKeyLower('referredfrom', 'referredFrom');
    mapKey('other_referral_source', 'otherReferralSource');
    mapKeyLower('otherreferralsource', 'otherReferralSource');
    mapKey('symptoms_presented', 'symptomsPresented');
    mapKeyLower('symptomspresented', 'symptomsPresented');
    mapKey('mrdt_result', 'mRDTResult');
    mapKeyLower('mrdtresult', 'mRDTResult');
    mapKey('referral_for_danger_signs', 'referralForDangerSigns');
    mapKeyLower('referralfordangersigns', 'referralForDangerSigns');
    mapKey('danger_signs_referral_facility', 'dangerSignsReferralFacility');
    mapKeyLower('dangersignsreferralfacility', 'dangerSignsReferralFacility');

    mapKey('fever_presented', 'feverPresented');
    mapKeyLower('feverpresented', 'feverPresented');
    mapKey('mrdt_tested', 'mRDTTested');
    mapKeyLower('mrdttested', 'mRDTTested');
    mapKey('mrdt_positive', 'mRDTPositive');
    mapKeyLower('mrdtpositive', 'mRDTPositive');
    mapKey('act_given', 'actGiven');
    mapKeyLower('actgiven', 'actGiven');
    mapKey('act_given_option', 'actGivenOption');
    mapKeyLower('actgivenoption', 'actGivenOption');
    mapKey('actGivenOption', 'actGivenOption');
    mapKeyLower('actgivenoption', 'actGivenOption');
    mapKey('hiv_counselling', 'hivCounselling');
    mapKeyLower('hivcounselling', 'hivCounselling');
    mapKey('hivst_type', 'hivstType');
    mapKeyLower('hivsttype', 'hivstType');
    mapKey('determine_test', 'determineTest');
    mapKeyLower('determinetest', 'determineTest');
    mapKey('art_linkage', 'artLinkage');
    mapKeyLower('artlinkage', 'artLinkage');
    mapKey('referral_facility', 'referralFacility');
    mapKeyLower('referralfacility', 'referralFacility');

    // Expanded HIV fields
    mapKey('hiv_previous_testing', 'hivPreviousTesting');
    mapKeyLower('hivprevioustesting', 'hivPreviousTesting');
    mapKey('hts_type', 'htsType');
    mapKeyLower('htstype', 'htsType');
    mapKey('hivst_kit_type', 'hivstKitType');
    mapKeyLower('hivstkittype', 'hivstKitType');
    mapKey('hivst_service_delivery_model', 'hivstServiceDeliveryModel');
    mapKeyLower('hivstservicedeliverymodel', 'hivstServiceDeliveryModel');
    mapKey('hiv_test_result', 'hivTestResult');
    mapKeyLower('hivtestresult', 'hivTestResult');
    mapKey('tb_symptoms_presented', 'tbSymptomsPresented');
    mapKeyLower('tbsymptomspresented', 'tbSymptomsPresented');
    mapKey('referral_services', 'referralServices');
    mapKeyLower('referralservices', 'referralServices');
    mapKey('other_referral_service', 'otherReferralService');
    mapKeyLower('otherreferralservice', 'otherReferralService');

    mapKey('prep_assessed', 'prepAssessed');
    mapKeyLower('prepassessed', 'prepAssessed');
    mapKey('prep_eligible', 'prepEligible');
    mapKeyLower('prepeligible', 'prepEligible');
    mapKey('prep_offered', 'prepOffered');
    mapKeyLower('prepoffered', 'prepOffered');
    mapKey('prep_accepted', 'prepAccepted');
    mapKeyLower('prepaccepted', 'prepAccepted');
    mapKey('prep_started', 'prepStarted');
    mapKeyLower('prepstarted', 'prepStarted');
    mapKey('prep_continued', 'prepContinued');
    mapKeyLower('prepcontinued', 'prepContinued');
    mapKey('prep_ref_source', 'prepRefSource');
    mapKeyLower('preprefsource', 'prepRefSource');
    mapKey('tb_screening', 'tbScreening');
    mapKeyLower('tbscreening', 'tbScreening');
    mapKey('sync_status', 'syncStatus');
    mapKeyLower('syncstatus', 'syncStatus');
    mapKey('created_at', 'createdAt');
    mapKeyLower('createdat', 'createdAt');
    mapKey('updated_at', 'updatedAt');
    mapKeyLower('updatedat', 'updatedAt');
    return _normalizeDates(out);
  }

  Map<String, dynamic> _toDbJson(TestRecord record, {required bool snakeCase}) {
    final json = _normalizeDates(record.toJson());
    if (!snakeCase) return json;
    // Only map keys that are known to be column names.
    return {
      'id': json['id'],
      'client_generated_id': json['clientGeneratedId'],
      'user_id': json['userId'],
      'program': json['program'],
      'client_name': json['clientName'],
      'client_id': json['clientId'],
      'age_band': json['ageBand'],
      'age': json['age'],
      'date_of_birth': json['dateOfBirth'],
      'phone_number': json['phoneNumber'],
      'test_date': json['testDate'],
      'sex': json['sex'],
      'pregnant': json['pregnant'],
      'visit_type': json['visitType'],
      'client_address': json['clientAddress'],
      'client_groups': json['clientGroups'],
      'first_time_visit': json['firstTimeVisit'],
      'referred_from': json['referredFrom'],
      'other_referral_source': json['otherReferralSource'],
      'symptoms_presented': json['symptomsPresented'],
      'mrdt_result': json['mRDTResult'],
      'referral_for_danger_signs': json['referralForDangerSigns'],
      'danger_signs_referral_facility': json['dangerSignsReferralFacility'],
      'fever_presented': json['feverPresented'],
      'mrdt_tested': json['mRDTTested'],
      'mrdt_positive': json['mRDTPositive'],
      'act_given': json['actGiven'],
      'hiv_counselling': json['hivCounselling'],
      'hivst_type': json['hivstType'],
      'determine_test': json['determineTest'],
      'art_linkage': json['artLinkage'],
      'referral_facility': json['referralFacility'],
      'hiv_previous_testing': json['hivPreviousTesting'],
      'hts_type': json['htsType'],
      'hivst_kit_type': json['hivstKitType'],
      'hivst_service_delivery_model': json['hivstServiceDeliveryModel'],
      'hiv_test_result': json['hivTestResult'],
      'tb_symptoms_presented': json['tbSymptomsPresented'],
      'referral_services': json['referralServices'],
      'other_referral_service': json['otherReferralService'],
      'prep_assessed': json['prepAssessed'],
      'prep_eligible': json['prepEligible'],
      'prep_offered': json['prepOffered'],
      'prep_accepted': json['prepAccepted'],
      'prep_started': json['prepStarted'],
      'prep_continued': json['prepContinued'],
      'prep_ref_source': json['prepRefSource'],
      'tb_screening': json['tbScreening'],
      'notes': json['notes'],
      'sync_status': json['syncStatus'],
      'created_at': json['createdAt'],
      'updated_at': json['updatedAt'],
    };
  }

  Map<String, dynamic> _toDbJsonLower(TestRecord record) {
    final json = _normalizeDates(record.toJson());
    return {
      'id': json['id'],
      'clientgeneratedid': json['clientGeneratedId'],
      'userid': json['userId'],
      'program': json['program'],
      'clientname': json['clientName'],
      'clientid': json['clientId'],
      'ageband': json['ageBand'],
      'age': json['age'],
      'dateofbirth': json['dateOfBirth'],
      'phonenumber': json['phoneNumber'],
      'testdate': json['testDate'],
      'sex': json['sex'],
      'pregnant': json['pregnant'],
      'visittype': json['visitType'],
      'clientaddress': json['clientAddress'],
      'clientgroups': json['clientGroups'],
      'firsttimevisit': json['firstTimeVisit'],
      'referredfrom': json['referredFrom'],
      'otherreferralsource': json['otherReferralSource'],
      'symptomspresented': json['symptomsPresented'],
      'mrdtresult': json['mRDTResult'],
      'referralfordangersigns': json['referralForDangerSigns'],
      'dangersignsreferralfacility': json['dangerSignsReferralFacility'],
      'feverpresented': json['feverPresented'],
      'mrdttested': json['mRDTTested'],
      'mrdtpositive': json['mRDTPositive'],
      'actgiven': json['actGiven'],
      'hivcounselling': json['hivCounselling'],
      'hivsttype': json['hivstType'],
      'determinetest': json['determineTest'],
      'artlinkage': json['artLinkage'],
      'referralfacility': json['referralFacility'],
      'hivprevioustesting': json['hivPreviousTesting'],
      'htstype': json['htsType'],
      'hivstkittype': json['hivstKitType'],
      'hivstservicedeliverymodel': json['hivstServiceDeliveryModel'],
      'hivtestresult': json['hivTestResult'],
      'tbsymptomspresented': json['tbSymptomsPresented'],
      'referralservices': json['referralServices'],
      'otherreferralservice': json['otherReferralService'],
      'prepassessed': json['prepAssessed'],
      'prepeligible': json['prepEligible'],
      'prepoffered': json['prepOffered'],
      'prepaccepted': json['prepAccepted'],
      'prepstarted': json['prepStarted'],
      'prepcontinued': json['prepContinued'],
      'preprefsource': json['prepRefSource'],
      'tbscreening': json['tbScreening'],
      'notes': json['notes'],
      'syncstatus': json['syncStatus'],
      'createdat': json['createdAt'],
      'updatedat': json['updatedAt'],
    };
  }

  List<TestRecord> get records => _records;
  bool get isLoading => _isLoading;

  int localLifetimeCount({required String userId, required bool hasGlobalView}) {
    if (hasGlobalView) return _records.length;
    if (userId.isEmpty) return 0;
    return _records.where((r) => r.userId == userId).length;
  }

  /// Starts a realtime subscription against Supabase for either:
  /// - a provider (only their `userId` rows)
  /// - admin view (all rows)
  ///
  /// This updates the local cache and notifies listeners whenever the backend changes.
  Future<void> startRealtime({required bool forAdmin, required String userId}) async {
    await stopRealtime();
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) return;

    try {
      // Prefer lowercase column style first (what Supabase type generation often produces).
      final base = SupabaseConfig.client.from('test_records').stream(primaryKey: ['id']);
      final query = base.order('testdate', ascending: false);

      _realtimeSub = query.listen((rows) async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final filtered = forAdmin
              ? rows
              : rows.where((r) => (r['userid'] ?? r['user_id'] ?? r['userId'])?.toString() == userId).toList();
          _records = filtered
              .map((row) => TestRecord.fromJson(_fromDbRow(row)).copyWith(syncStatus: SyncStatus.synced))
              .toList();
          await _saveRecords(prefs);
          notifyListeners();
        } catch (e) {
          debugPrint('TestRecord realtime apply failed: $e');
        }
      });
    } catch (e) {
      // Retry other common schemas.
      if (!_isSchemaColumnError(e)) {
        debugPrint('Failed to start test record realtime: $e');
        return;
      }
      try {
        final query = SupabaseConfig.client.from('test_records').stream(primaryKey: ['id']).order('test_date', ascending: false);
        _realtimeSub = query.listen((rows) async {
          try {
            final prefs = await SharedPreferences.getInstance();
            final filtered = forAdmin
                ? rows
                : rows.where((r) => (r['userid'] ?? r['user_id'] ?? r['userId'])?.toString() == userId).toList();
            _records = filtered
                .map((row) => TestRecord.fromJson(_fromDbRow(row)).copyWith(syncStatus: SyncStatus.synced))
                .toList();
            await _saveRecords(prefs);
            notifyListeners();
          } catch (e) {
            debugPrint('TestRecord realtime apply failed (snake_case): $e');
          }
        });
      } catch (e) {
        if (!_isSchemaColumnError(e)) {
          debugPrint('Failed to start test record realtime: $e');
          return;
        }
        try {
          final query = SupabaseConfig.client.from('test_records').stream(primaryKey: ['id']).order('testDate', ascending: false);
          _realtimeSub = query.listen((rows) async {
            try {
              final prefs = await SharedPreferences.getInstance();
              final filtered = forAdmin
                  ? rows
                  : rows.where((r) => (r['userid'] ?? r['user_id'] ?? r['userId'])?.toString() == userId).toList();
              _records = filtered
                  .map((row) => TestRecord.fromJson(_fromDbRow(row)).copyWith(syncStatus: SyncStatus.synced))
                  .toList();
              await _saveRecords(prefs);
              notifyListeners();
            } catch (e) {
              debugPrint('TestRecord realtime apply failed (lowercase): $e');
            }
          });
        } catch (e) {
          debugPrint('Failed to start test record realtime: $e');
        }
      }
    }
  }

  Future<void> stopRealtime() async {
    await _realtimeSub?.cancel();
    _realtimeSub = null;
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1) Load local cache first (fast startup, offline support)
      final prefs = await SharedPreferences.getInstance();
      final recordsJson = prefs.getString('testRecords');
      if (recordsJson != null) {
        final decoded = jsonDecode(recordsJson) as List;
        _records = decoded.map((e) {
          try {
            return TestRecord.fromJson(e);
          } catch (err) {
            debugPrint('Skipping corrupted test record: $err');
            return null;
          }
        }).whereType<TestRecord>().toList();

        // One-time repair/migration for older local queue payloads.
        final repaired = _repairLocalQueue(_records);
        if (repaired.didChange) {
          _records = repaired.records;
          await _saveRecords(prefs);
        }

        if (_records.length != decoded.length) {
          await _saveRecords(prefs);
        }
      } else {
        // Only create sample data when no Supabase auth session exists.
        if (SupabaseConfig.auth.currentUser == null) {
          await _createSampleData(prefs);
        } else {
          _records = [];
        }
      }

      // 2) Best-effort sync from Supabase (shared across devices)
      await _syncWithSupabase(prefs);
    } catch (e) {
      debugPrint('Failed to load test records: $e');
      _records = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  ({List<TestRecord> records, bool didChange}) _repairLocalQueue(List<TestRecord> input) {
    var changed = false;
    final out = <TestRecord>[];
    for (final r in input) {
      var next = r;

      // Ensure idempotency key exists.
      if (next.clientGeneratedId.trim().isEmpty) {
        next = next.copyWith(clientGeneratedId: next.id);
        changed = true;
      }

      // Malaria no longer supports Client Groups for NEW submissions.
      // Keep historical server-synced rows intact; only normalize unsynced local queue items.
      if (next.program == HealthProgram.malaria && next.syncStatus != SyncStatus.synced && (next.clientGroups?.isNotEmpty ?? false)) {
        next = next.copyWith(clientGroups: null);
        changed = true;
      }

      // Reset recoverable failures back to pending so auto-sync can pick them up.
      if (next.syncStatus == SyncStatus.failed) {
        final err = (next.lastError ?? '').toLowerCase();
        final recoverable = err.contains('timeout') || err.contains('failed to fetch') || err.contains('network') || err.contains('socket') || err.contains('temporary');
        if (recoverable) {
          next = next.copyWith(syncStatus: SyncStatus.pending);
          changed = true;
        }
      }

      out.add(next);
    }
    return (records: out, didChange: changed);
  }

  /// Performs a real sync:
  /// - pushes pending/failed rows
  /// - pulls latest server rows
  ///
  /// Safe to call repeatedly. No-ops if not authenticated.
  Future<void> syncNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _syncWithSupabase(prefs);
      // Lifetime count may change after a sync.
      _lifetimeFetchedAt = null;
    } catch (e) {
      debugPrint('TestRecord syncNow failed: $e');
      rethrow;
    }
  }

  Future<void> _syncWithSupabase(SharedPreferences prefs) async {
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) return;

    // Best-effort: refresh session before attempting queued writes.
    try {
      await SupabaseConfig.auth.refreshSession();
    } catch (e) {
      debugPrint('Supabase refreshSession failed (non-fatal): $e');
    }

    // Push any pending local records first (idempotent upsert).
    final pending = _records.where((r) => r.syncStatus == SyncStatus.pending || r.syncStatus == SyncStatus.failed).toList();
    if (pending.isNotEmpty) {
      for (final record in pending) {
        try {
          final syncing = record.copyWith(syncStatus: SyncStatus.syncing, lastAttemptedAt: DateTime.now(), retryCount: record.retryCount + 1, lastError: null, updatedAt: DateTime.now());
          _replaceLocal(syncing);
          await _saveRecords(prefs);

          await _upsertTestRecordRemote(syncing);
          _replaceLocal(syncing.copyWith(syncStatus: SyncStatus.synced, updatedAt: DateTime.now()));
        } catch (e) {
          final msg = e.toString();
          debugPrint('Failed to push pending test record ${record.id}: $msg');
          _replaceLocal(record.copyWith(syncStatus: SyncStatus.failed, lastError: msg, lastAttemptedAt: DateTime.now(), retryCount: record.retryCount + 1, updatedAt: DateTime.now()));
        }
      }
      await _saveRecords(prefs);
    }

    // Pull latest records from server.
    try {
      List<Map<String, dynamic>> remote;
      try {
        remote = await SupabaseService.select('test_records', filters: {'userid': authUser.id}, orderBy: 'testdate', ascending: false);
      } catch (e) {
        if (!_isSchemaColumnError(e)) rethrow;
        try {
          remote = await SupabaseService.select('test_records', filters: {'user_id': authUser.id}, orderBy: 'test_date', ascending: false);
        } catch (e) {
          if (!_isSchemaColumnError(e)) rethrow;
          remote = await SupabaseService.select('test_records', filters: {'userId': authUser.id}, orderBy: 'testDate', ascending: false);
        }
      }

      final localById = {for (final r in _records) r.id: r};
      var changed = false;

      for (final row in remote) {
        final remoteRecord = TestRecord.fromJson(_fromDbRow(row));
        final local = localById[remoteRecord.id];

        if (local == null || remoteRecord.updatedAt.isAfter(local.updatedAt)) {
          localById[remoteRecord.id] = remoteRecord.copyWith(syncStatus: SyncStatus.synced);
          changed = true;
        }
      }

      if (changed) {
        _records = localById.values.toList()
          ..sort((a, b) => b.testDate.compareTo(a.testDate));
        await _saveRecords(prefs);
        notifyListeners();
      }
    } catch (e) {
      // Network/RLS errors should not block offline usage.
      debugPrint('Test record Supabase pull failed (offline ok): $e');
    }
  }

  /// Fast local commit (Phase 1).
  ///
  /// Inserts (or replaces) a record locally, persists to SharedPreferences, and
  /// returns immediately without doing any network I/O.
  Future<void> addRecordLocal(TestRecord record) async {
    // Never mark a record as synced until the remote write actually succeeds.
    final local = record.copyWith(syncStatus: SyncStatus.pending, updatedAt: DateTime.now());
    _replaceLocal(local);
    _records.sort((a, b) => b.testDate.compareTo(a.testDate));
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await _saveRecords(prefs);
    } catch (e) {
      debugPrint('Failed to locally persist test record: $e');
      // We intentionally do not rethrow; the in-memory record still exists.
    }
  }

  /// Background sync of a single record (Phase 2).
  ///
  /// - Marks record as syncing
  /// - Attempts an idempotent upsert using the record's stable UUID `id`
  /// - On success marks as synced, on failure marks as failed (kept locally)
  Future<void> syncRecordInBackground(String recordId, {Duration timeout = const Duration(seconds: 10)}) async {
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) return;

    try {
      await SupabaseConfig.auth.refreshSession();
    } catch (e) {
      debugPrint('Supabase refreshSession failed before single-record sync (non-fatal): $e');
    }

    final local = _findLocalById(recordId);
    if (local == null) return;

    // Avoid flipping synced records back into syncing.
    if (local.syncStatus == SyncStatus.synced) return;

    final syncing = local.copyWith(syncStatus: SyncStatus.syncing, lastAttemptedAt: DateTime.now(), retryCount: local.retryCount + 1, lastError: null, updatedAt: DateTime.now());
    _replaceLocal(syncing);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await _saveRecords(prefs);
    } catch (e) {
      debugPrint('Failed to persist syncing status for $recordId: $e');
    }

    try {
      await _upsertTestRecordRemote(syncing).timeout(timeout);
      final synced = syncing.copyWith(syncStatus: SyncStatus.synced, updatedAt: DateTime.now());
      _replaceLocal(synced);
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        await _saveRecords(prefs);
      } catch (e) {
        debugPrint('Failed to persist synced status for $recordId: $e');
      }
      _lifetimeFetchedAt = null;
    } catch (e) {
      final msg = e.toString();
      debugPrint('Background test record sync failed ($recordId): $msg');
      final failed = syncing.copyWith(syncStatus: SyncStatus.failed, lastError: msg, updatedAt: DateTime.now());
      _replaceLocal(failed);
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        await _saveRecords(prefs);
      } catch (err) {
        debugPrint('Failed to persist failed status for $recordId: $err');
      }
    }
  }

  /// Best-effort: sync all pending/failed records in the background.
  ///
  /// Safe to call multiple times; it will serialize concurrent runs.
  void syncPendingInBackground() {
    if (_backgroundSyncRunning) return;
    _backgroundSyncRunning = true;
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await _syncWithSupabase(prefs);
        _lifetimeFetchedAt = null;
      } catch (e) {
        debugPrint('syncPendingInBackground failed: $e');
      } finally {
        _backgroundSyncRunning = false;
      }
    }());
  }

  /// Admin-only: pull all records (no userId filter). Requires permissive RLS for admin roles.
  Future<void> syncAllForAdmin() async {
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      List<Map<String, dynamic>> remote;
      try {
        remote = await SupabaseService.select('test_records', orderBy: 'testdate', ascending: false);
      } catch (e) {
        if (!_isSchemaColumnError(e)) rethrow;
        try {
          remote = await SupabaseService.select('test_records', orderBy: 'test_date', ascending: false);
        } catch (e) {
          if (!_isSchemaColumnError(e)) rethrow;
          remote = await SupabaseService.select('test_records', orderBy: 'testDate', ascending: false);
        }
      }
      _records = remote.map((row) => TestRecord.fromJson(_fromDbRow(row)).copyWith(syncStatus: SyncStatus.synced)).toList();
      await _saveRecords(prefs);
      notifyListeners();
    } catch (e) {
      debugPrint('Admin test record sync failed: $e');
      rethrow;
    }
  }

  void _replaceLocal(TestRecord record) {
    final idx = _records.indexWhere((r) => r.id == record.id);
    if (idx == -1) {
      _records.insert(0, record);
    } else {
      _records[idx] = record;
    }
  }

  Map<String, dynamic> _normalizeDates(Map<String, dynamic> json) {
    // Supabase may return timestamps as String or DateTime depending on platform.
    final out = Map<String, dynamic>.from(json);
    for (final key in ['testDate', 'createdAt', 'updatedAt']) {
      final v = out[key];
      if (v is DateTime) out[key] = v.toIso8601String();
    }
    return out;
  }

  Future<void> _createSampleData(SharedPreferences prefs) async {
    final now = DateTime.now();
    _records = [
      TestRecord(
        id: _uuid.v4(),
        clientGeneratedId: _uuid.v4(),
        userId: 'provider1',
        program: HealthProgram.malaria,
        clientName: 'Amina Mohammed',
        clientId: 'MAL-001',
        ageBand: '5-14 years',
        testDate: now.subtract(const Duration(days: 1)),
        sex: 'Female',
        pregnant: false,
        visitType: VisitType.newVisit,
        feverPresented: true,
        mRDTTested: true,
        mRDTPositive: true,
        actGiven: true,
        actGivenOption: 'TopMal',
        syncStatus: SyncStatus.synced,
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(days: 1)),
      ),
      TestRecord(
        id: _uuid.v4(),
        clientGeneratedId: _uuid.v4(),
        userId: 'provider1',
        program: HealthProgram.hiv,
        clientName: 'Chinedu Okafor',
        clientId: 'HIV-001',
        ageBand: '25-34 years',
        testDate: now,
        sex: 'Male',
        visitType: VisitType.newVisit,
        hivCounselling: true,
        hivstType: HIVTestType.assisted,
        determineTest: HIVResult.confirmedNegative,
        syncStatus: SyncStatus.pending,
        createdAt: now,
        updatedAt: now,
      ),
    ];
    await _saveRecords(prefs);
  }

  Future<void> _saveRecords(SharedPreferences prefs) async {
    await prefs.setString('testRecords', jsonEncode(_records.map((r) => r.toJson()).toList()));
  }

  /// Adds a record locally, then optionally attempts an immediate remote sync.
  ///
  /// Returns true if the record is confirmed synced to Supabase.
  Future<bool> addRecord(TestRecord record, {bool syncNow = false}) async {
    // Backwards-compatible API, but optimized:
    // Phase 1: local commit (fast)
    await addRecordLocal(record);

    // Phase 2: background sync (non-blocking)
    if (syncNow) {
      syncRecordInBackground(record.id);
      return false;
    }
    return false;
  }

  Future<void> updateRecord(TestRecord record) async {
    final index = _records.indexWhere((r) => r.id == record.id);
    if (index != -1) {
      _records[index] = record;
      notifyListeners();

      try {
        final prefs = await SharedPreferences.getInstance();
        await _saveRecords(prefs);

        // Avoid blocking UI flows on implicit remote writes.
        // If authenticated, kick off a background sync for this record.
        if (SupabaseConfig.auth.currentUser != null) {
          // If user changed a record, ensure it's eligible for re-sync.
          if (record.syncStatus == SyncStatus.synced) {
            _records[index] = record.copyWith(syncStatus: SyncStatus.pending, updatedAt: DateTime.now());
            notifyListeners();
            await _saveRecords(prefs);
          }
          unawaited(syncRecordInBackground(record.id));
        }
      } catch (e) {
        debugPrint('Failed to update test record: $e');
      }
    }
  }

  Future<void> deleteRecord(String id) async {
    _records.removeWhere((r) => r.id == id);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await _saveRecords(prefs);

      if (SupabaseConfig.auth.currentUser != null) {
        try {
          await SupabaseService.delete('test_records', filters: {'id': id});
        } catch (e) {
          debugPrint('Supabase delete test record failed (local removed): $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to delete test record: $e');
    }
  }

  List<TestRecord> getRecordsByProgram(HealthProgram program) =>
      _records.where((r) => r.program == program).toList();

  bool _isInLocalDay(DateTime dt, DateTime dayLocal) {
    final d = dt.toLocal();
    final start = DateTime(dayLocal.year, dayLocal.month, dayLocal.day);
    final end = start.add(const Duration(days: 1));
    return !d.isBefore(start) && d.isBefore(end);
  }

  List<TestRecord> getTodayRecords(String userId) {
    final today = DateTime.now();
    return _records.where((r) => r.userId == userId && _isInLocalDay(r.testDate, today)).toList();
  }

  List<TestRecord> getTodayRecordsAll() {
    final today = DateTime.now();
    return _records.where((r) => _isInLocalDay(r.testDate, today)).toList();
  }

  Map<HealthProgram, int> getTodayCountsByProgram(String userId) {
    final todayRecords = getTodayRecords(userId);
    return {
      HealthProgram.malaria: todayRecords.where((r) => r.program == HealthProgram.malaria).length,
      HealthProgram.hiv: todayRecords.where((r) => r.program == HealthProgram.hiv).length,
    };
  }

  Map<HealthProgram, int> getTodayCountsByProgramAll() {
    final todayRecords = getTodayRecordsAll();
    return {
      HealthProgram.malaria: todayRecords.where((r) => r.program == HealthProgram.malaria).length,
      HealthProgram.hiv: todayRecords.where((r) => r.program == HealthProgram.hiv).length,
    };
  }

  int getPendingSyncCount() =>
      _records.where((r) => r.syncStatus != SyncStatus.synced).length;

  /// Canonical, RLS-respecting lifetime total count.
  ///
  /// IMPORTANT: This intentionally uses the same underlying table visibility as
  /// the History screen (`fetchAllVisibleRecordsRemote`) so the Lifetime tile
  /// cannot drift from what the user sees in History across devices.
  ///
  /// If [userId] is provided, the count is scoped to records created by that
  /// user. This is required because some deployments allow fieldproviders to
  /// *see* other fieldproviders' records via RLS, but the provider dashboard
  /// should still show "my" lifetime total.
  Future<int?> fetchLifetimeTotalCount({String? userId}) async {
    try {
      final now = DateTime.now();
      if (_lifetimeFetchedAt != null && _lifetimeCached != null) {
        final age = now.difference(_lifetimeFetchedAt!);
        if (age.inSeconds < 15) return _lifetimeCached;
      }

      if (userId != null && userId.isNotEmpty) {
        // Try common schema variants.
        final candidates = <String>['userid', 'user_id', 'userId', 'created_by', 'createdBy', 'provider_id', 'providerId'];
        Object? lastErr;
        for (final col in candidates) {
          try {
            final List<dynamic> rows = await SupabaseConfig.client.from('test_records').select('id').eq(col, userId);
            final count = rows.length;
            _lifetimeFetchedAt = now;
            _lifetimeCached = count;
            return count;
          } catch (e) {
            lastErr = e;
            if (!_isSchemaColumnError(e)) rethrow;
          }
        }

        // Last resort: if the backend schema uses an unknown column name for the
        // provider/user id, fall back to RLS-scoped select and filter client-side.
        // This is safe because RLS should already prevent cross-user leakage.
        try {
          final rows = await SupabaseConfig.client.from('test_records').select('*');
          final parsed = rows
              .map((e) => TestRecord.fromJson(_fromDbRow(Map<String, dynamic>.from(e as Map))))
              .where((r) => r.userId == userId)
              .toList();
          _lifetimeFetchedAt = now;
          _lifetimeCached = parsed.length;
          return parsed.length;
        } catch (e) {
          lastErr = e;
          debugPrint('fetchLifetimeTotalCount user scope schema fallback exhausted: $lastErr');
          return null;
        }
      }

      dynamic q = SupabaseConfig.client.from('test_records').select('id');

      // Count rows visible to the current caller (RLS-scoped).
      // We select only `id` to keep payload small.
      final rows = await q;
      final count = (rows is List) ? rows.length : 0;

      _lifetimeFetchedAt = now;
      _lifetimeCached = count;
      return count;
    } catch (e) {
      debugPrint('fetchLifetimeTotalCount failed (offline ok): $e');
      return null;
    }
  }

  /// Canonical all-time list that matches the lifetime total count.
  ///
  /// - No client-side scope filters are applied here unless [userId] is
  ///   provided. When set, the query is scoped to that user.
  /// - Used by the non-"today" history screen so list and lifetime count match.
  Future<List<TestRecord>> fetchAllVisibleRecordsRemote({HealthProgram? program, String? userId, DateTimeRange? dateRange}) async {
    try {
      DateTime? start;
      DateTime? endInclusive;
      if (dateRange != null) {
        start = DateTime(dateRange.start.year, dateRange.start.month, dateRange.start.day);
        endInclusive = DateTime(dateRange.end.year, dateRange.end.month, dateRange.end.day, 23, 59, 59, 999);
      }

      Future<List<TestRecord>> runQuery({String? filterColumn, String? orderColumn, String? userColumn, String? dateColumn}) async {
        dynamic q = SupabaseConfig.client.from('test_records').select('*');
        if (userId != null && userId.isNotEmpty && userColumn != null) q = q.eq(userColumn, userId);
        if (program != null && filterColumn != null) q = q.eq(filterColumn, program.name);
        if (start != null && endInclusive != null && dateColumn != null) {
          // Use UTC boundaries so local-day filters include both boundary dates correctly.
          q = q.gte(dateColumn, start.toUtc().toIso8601String()).lte(dateColumn, endInclusive.toUtc().toIso8601String());
        }
        if (orderColumn != null) q = q.order(orderColumn, ascending: false);
        final rows = await q;
        if (rows is! List) return const <TestRecord>[];
        return rows.map((e) => TestRecord.fromJson(_fromDbRow(Map<String, dynamic>.from(e as Map))).copyWith(syncStatus: SyncStatus.synced)).toList();
      }

      // Prefer canonical schema; fall back to common variants. If filtering fails due to
      // column naming differences, we fall back to unfiltered + client-side filter.
      final orderColumns = <String?>['testDate', 'testdate', 'test_date'];
      final dateColumns = start == null ? <String?>[null] : <String?>['testDate', 'testdate', 'test_date'];
      final filterColumns = <String?>['program', 'intervention_area', 'health_program', null];
      final userColumns = userId == null || userId.isEmpty
          ? <String?>[null]
          : <String?>['userid', 'user_id', 'userId', 'created_by', 'createdBy', 'provider_id', 'providerId'];

      Object? lastErr;
      for (final orderCol in orderColumns) {
        for (final userCol in userColumns) {
          for (final dateCol in dateColumns) {
            for (final filterCol in (program == null ? <String?>[null] : filterColumns)) {
              try {
                final res = await runQuery(filterColumn: filterCol, orderColumn: orderCol, userColumn: userCol, dateColumn: dateCol);
                Iterable<TestRecord> out = res;
                if (program != null && filterCol == null) out = out.where((r) => r.program == program);
                if (start != null && endInclusive != null && dateCol == null) {
                  out = out.where((r) => !r.testDate.isBefore(start!) && !r.testDate.isAfter(endInclusive!));
                }
                return out.toList();
              } catch (e) {
                lastErr = e;
                if (!_isSchemaColumnError(e)) rethrow;
              }
            }
          }
        }
      }

      // Last resort: pull rows (still RLS-scoped) and filter in Dart.
      try {
        final res = await runQuery(filterColumn: null, orderColumn: orderColumns.last, userColumn: null, dateColumn: dateColumns.first);
        Iterable<TestRecord> out = res;
        if (userId != null && userId.isNotEmpty) out = out.where((r) => r.userId == userId);
        if (program != null) out = out.where((r) => r.program == program);
        if (start != null && endInclusive != null) out = out.where((r) => !r.testDate.isBefore(start!) && !r.testDate.isAfter(endInclusive!));
        return out.toList();
      } catch (e) {
        lastErr = e;
      }

      debugPrint('fetchAllVisibleRecordsRemote schema fallback exhausted: $lastErr');
      return const <TestRecord>[];
    } catch (e) {
      debugPrint('fetchAllVisibleRecordsRemote failed (offline ok): $e');
      return const <TestRecord>[];
    }
  }

  Future<void> markAllPendingAsSynced() async {
    if (_records.isEmpty) return;

    _records = _records
        .map((r) => r.syncStatus == SyncStatus.synced
            ? r
            : r.copyWith(syncStatus: SyncStatus.synced, updatedAt: DateTime.now()))
        .toList();
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await _saveRecords(prefs);
    } catch (e) {
      debugPrint('Failed to mark test records synced: $e');
    }
  }
}
