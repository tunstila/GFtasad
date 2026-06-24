import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:mediflow/models/prevention_messaging_record.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/supabase/supabase_config.dart';

class PreventionMessagingRecordService extends ChangeNotifier {
  static const _uuid = Uuid();
  static const _prefsKey = 'prevention_messaging_records_v1';

  static final Set<String> _remoteRejectedColumnsLower = <String>{};

  List<PreventionMessagingRecord> _records = [];
  bool _isLoading = false;
  bool _backgroundSyncRunning = false;

  DateTime? _todayFetchedAt;
  int? _todayCached;

  List<PreventionMessagingRecord> get records => _records;
  bool get isLoading => _isLoading;

  bool _isInLocalDay(DateTime dt, DateTime dayLocal) {
    final d = dt.toLocal();
    final start = DateTime(dayLocal.year, dayLocal.month, dayLocal.day);
    final end = start.add(const Duration(days: 1));
    return !d.isBefore(start) && d.isBefore(end);
  }

  List<PreventionMessagingRecord> getTodayRecords(String userId) {
    final today = DateTime.now();
    return _records.where((r) => r.userId == userId && _isInLocalDay(r.createdAt, today)).toList();
  }

  int localTodayCount(String userId) => getTodayRecords(userId).length;

  /// Canonical, RLS-respecting count of "today" prevention messaging records.
  ///
  /// - Scopes to the provided [userId]
  /// - Uses the same local-day boundary convention as the existing home tiles
  /// - Uses schema fallbacks for common column naming variants
  /// - Returns null on failure (offline/RLS), so UI can fall back to local cache
  Future<int?> fetchTodayTotalCount({required String userId}) async {
    try {
      final now = DateTime.now();
      if (_todayFetchedAt != null && _todayCached != null) {
        final age = now.difference(_todayFetchedAt!);
        if (age.inSeconds < 15) return _todayCached;
      }

      final startLocal = DateTime(now.year, now.month, now.day);
      final endLocal = startLocal.add(const Duration(days: 1));
      final startUtc = startLocal.toUtc().toIso8601String();
      final endUtc = endLocal.toUtc().toIso8601String();

      final userCols = <String>['userid', 'user_id', 'userId', 'created_by', 'createdBy', 'provider_id', 'providerId'];
      final dateCols = <String>['createdat', 'created_at', 'createdAt'];

      Object? lastErr;
      for (final userCol in userCols) {
        for (final dateCol in dateCols) {
          try {
            dynamic q = SupabaseConfig.client.from('prevention_messaging_records').select('id').eq(userCol, userId);
            q = q.gte(dateCol, startUtc).lt(dateCol, endUtc);
            final rows = await q;
            final count = (rows is List) ? rows.length : 0;
            _todayFetchedAt = now;
            _todayCached = count;
            return count;
          } catch (e) {
            lastErr = e;
            if (!_isSchemaColumnError(e)) {
              debugPrint('fetchTodayTotalCount failed: $e');
              return null;
            }
          }
        }
      }

      debugPrint('fetchTodayTotalCount schema fallback exhausted: $lastErr');
      return null;
    } catch (e) {
      debugPrint('fetchTodayTotalCount failed (offline ok): $e');
      return null;
    }
  }

  PreventionMessagingRecord? _findLocalById(String id) {
    final idx = _records.indexWhere((r) => r.id == id);
    if (idx == -1) return null;
    return _records[idx];
  }

  void _replaceLocal(PreventionMessagingRecord r) {
    final idx = _records.indexWhere((e) => e.id == r.id);
    if (idx == -1) {
      _records.add(r);
    } else {
      _records[idx] = r;
    }
  }

  static bool _looksLikeUuid(String? v) {
    if (v == null) return false;
    final s = v.trim();
    if (s.isEmpty) return false;
    return RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(s);
  }

  static bool _isSchemaColumnError(Object e) {
    final msg = e.toString();
    return msg.contains('schema cache') || msg.contains('does not exist') || msg.contains("Could not find the '");
  }

  static bool _isNotNullViolation(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('violates not-null constraint') || msg.contains('null value in column');
  }

  static String? _extractMissingColumn(Object e) {
    final msg = e.toString();
    final m1 = RegExp(r"Could not find the '([^']+)' column").firstMatch(msg);
    if (m1 != null) return m1.group(1);
    final m1b = RegExp(r'Could not find the `([^`]+)` column').firstMatch(msg);
    if (m1b != null) return m1b.group(1);
    final m2 = RegExp(r'column\s+[\w\.]+\.(\w+)\s+does not exist').firstMatch(msg);
    if (m2 != null) return m2.group(1);
    return null;
  }

  static bool _isEmptyString(Object? v) => v is String && v.trim().isEmpty;

  static void _ensurePresent(Map<String, dynamic> payload, String key, Object? value) {
    if (!payload.containsKey(key) || payload[key] == null || _isEmptyString(payload[key])) payload[key] = value;
  }

  Future<void> initialize() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await _loadFromPrefs(prefs);
      // Best-effort sync, but never block offline UI.
      unawaited(syncPendingInBackground());
    } catch (e) {
      debugPrint('PreventionMessagingRecordService initialize failed (offline ok): $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadFromPrefs(SharedPreferences prefs) async {
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      _records = [];
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _records = [];
        return;
      }

      final loaded = <PreventionMessagingRecord>[];
      for (final item in decoded) {
        if (item is Map) {
          try {
            loaded.add(PreventionMessagingRecord.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {
            // Skip corrupted rows.
          }
        }
      }

      _records = loaded..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Sanitize storage if we skipped any corrupted rows.
      await _saveToPrefs(prefs);
    } catch (e) {
      debugPrint('Failed to decode prevention messaging cache: $e');
      _records = [];
      await _saveToPrefs(prefs);
    }
  }

  Future<void> _saveToPrefs(SharedPreferences prefs) async {
    try {
      final encoded = jsonEncode(_records.map((e) => e.toJson()).toList());
      await prefs.setString(_prefsKey, encoded);
    } catch (e) {
      debugPrint('Failed to persist prevention messaging cache: $e');
    }
  }

  int getPendingSyncCount() => _records.where((r) => r.syncStatus == SyncStatus.pending || r.syncStatus == SyncStatus.failed).length;

  static String newLocalId() => _uuid.v4();

  Future<void> addRecordLocal(PreventionMessagingRecord record) async {
    final local = record.copyWith(syncStatus: SyncStatus.pending, updatedAt: DateTime.now());
    _replaceLocal(local);
    _records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await _saveToPrefs(prefs);
    } catch (e) {
      debugPrint('Failed to locally persist prevention messaging record: $e');
    }
  }

  Future<void> updateRecordLocal(PreventionMessagingRecord record) async {
    _replaceLocal(record.copyWith(syncStatus: SyncStatus.pending, updatedAt: DateTime.now()));
    _records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await _saveToPrefs(prefs);
    } catch (e) {
      debugPrint('Failed to persist prevention messaging update: $e');
    }
  }

  Future<void> syncNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _syncWithSupabase(prefs);
    } catch (e) {
      debugPrint('PreventionMessagingRecord syncNow failed: $e');
      rethrow;
    }
  }

  Future<void> syncRecordInBackground(String id, {Duration timeout = const Duration(seconds: 10)}) async {
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) return;

    final local = _findLocalById(id);
    if (local == null) return;
    if (local.syncStatus == SyncStatus.synced) return;

    final syncing = local.copyWith(syncStatus: SyncStatus.syncing, updatedAt: DateTime.now(), userId: _looksLikeUuid(local.userId) ? local.userId : authUser.id);
    _replaceLocal(syncing);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await _saveToPrefs(prefs);
    } catch (e) {
      debugPrint('Failed to persist syncing status for prevention record $id: $e');
    }

    try {
      await _upsertRemote(syncing).timeout(timeout);
      final synced = syncing.copyWith(syncStatus: SyncStatus.synced, updatedAt: DateTime.now());
      _replaceLocal(synced);
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        await _saveToPrefs(prefs);
      } catch (e) {
        debugPrint('Failed to persist synced status for prevention record $id: $e');
      }
    } catch (e) {
      debugPrint('Background prevention messaging sync failed ($id): $e');
      final failed = syncing.copyWith(syncStatus: SyncStatus.failed, updatedAt: DateTime.now());
      _replaceLocal(failed);
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        await _saveToPrefs(prefs);
      } catch (err) {
        debugPrint('Failed to persist failed status for prevention record $id: $err');
      }
    }
  }

  Future<void> syncPendingInBackground() async {
    if (_backgroundSyncRunning) return;
    _backgroundSyncRunning = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await _syncWithSupabase(prefs);
    } catch (e) {
      debugPrint('PreventionMessagingRecord background sync failed (offline ok): $e');
    } finally {
      _backgroundSyncRunning = false;
    }
  }

  Future<void> _syncWithSupabase(SharedPreferences prefs) async {
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) return;

    // Repair legacy placeholder user ids.
    var repairedAny = false;
    final repaired = <PreventionMessagingRecord>[];
    for (final r in _records) {
      if (_looksLikeUuid(r.userId)) {
        repaired.add(r);
      } else {
        repairedAny = true;
        repaired.add(r.copyWith(userId: authUser.id, syncStatus: SyncStatus.pending, updatedAt: DateTime.now()));
      }
    }
    if (repairedAny) {
      _records = repaired;
      await _saveToPrefs(prefs);
      notifyListeners();
    }

    final pending = _records.where((r) => r.syncStatus == SyncStatus.pending || r.syncStatus == SyncStatus.failed).toList();
    if (pending.isNotEmpty) {
      for (final r in pending) {
        try {
          await _upsertRemote(r);
          _replaceLocal(r.copyWith(syncStatus: SyncStatus.synced, updatedAt: DateTime.now()));
        } catch (e) {
          debugPrint('Failed to push pending prevention messaging record ${r.id}: $e');
          _replaceLocal(r.copyWith(syncStatus: SyncStatus.failed, updatedAt: DateTime.now()));
        }
      }
      await _saveToPrefs(prefs);
      notifyListeners();
    }

    // Pull latest records (best-effort). We only pull current user's records.
    try {
      List<Map<String, dynamic>> remote;
      try {
        remote = await SupabaseService.select('prevention_messaging_records', filters: {'userid': authUser.id}, orderBy: 'createdat', ascending: false);
      } catch (e) {
        if (!_isSchemaColumnError(e)) rethrow;
        remote = await SupabaseService.select('prevention_messaging_records', filters: {'user_id': authUser.id}, orderBy: 'created_at', ascending: false);
      }

      final localById = {for (final r in _records) r.id: r};
      var changed = false;
      for (final row in remote) {
        final rec = PreventionMessagingRecord.fromJson(_fromDbRow(row)).copyWith(syncStatus: SyncStatus.synced);
        final local = localById[rec.id];
        if (local == null || rec.updatedAt.isAfter(local.updatedAt)) {
          localById[rec.id] = rec;
          changed = true;
        }
      }

      if (changed) {
        _records = localById.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await _saveToPrefs(prefs);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Prevention messaging Supabase pull failed (offline ok): $e');
    }
  }

  Map<String, dynamic> _fromDbRow(Map<String, dynamic> row) {
    // Normalize minimal common variants.
    final out = Map<String, dynamic>.from(row);
    if (!out.containsKey('userId') && out['userid'] != null) out['userId'] = out['userid'];
    if (!out.containsKey('clientName') && out['clientname'] != null) out['clientName'] = out['clientname'];
    if (!out.containsKey('clientId') && out['clientid'] != null) out['clientId'] = out['clientid'];
    if (!out.containsKey('phoneNumber') && out['phonenumber'] != null) out['phoneNumber'] = out['phonenumber'];
    if (!out.containsKey('createdAt') && out['createdat'] != null) out['createdAt'] = out['createdat'];
    if (!out.containsKey('updatedAt') && out['updatedat'] != null) out['updatedAt'] = out['updatedat'];
    return out;
  }

  Map<String, dynamic> _toDbJsonLower(PreventionMessagingRecord r) => {
        'id': r.id,
        'userid': r.userId,
        'clientname': r.clientName,
        'age': r.age,
        'phonenumber': r.phoneNumber,
        'clientid': r.clientId,
        'sex': r.sex,
        'clientgroups': r.clientGroups,
        'firsttimevisit': r.firstTimeVisit,
        'referredfrom': r.referredFrom,
        'otherreferredfrom': r.otherReferredFrom,
        'educatedonhivprevention': r.educatedOnHivPrevention,
        'educatedonhivtestingoptions': r.educatedOnHivTestingOptions,
        'educatedonmalariaprevention': r.educatedOnMalariaPrevention,
        // Some backends use this legacy NOT NULL column name.
        'educatedonmalariapreventiontreatment': r.educatedOnMalariaPrevention,
        'referralservices': r.referralServices,
        'otherreferralservice': r.otherReferralService,
        'referralfacility': r.referralFacility,
        'syncstatus': r.syncStatus.name,
        'createdat': r.createdAt.toIso8601String(),
        'updatedat': r.updatedAt.toIso8601String(),
      };

  Map<String, dynamic> _toDbJsonSnake(PreventionMessagingRecord r) => {
        'id': r.id,
        'user_id': r.userId,
        'client_name': r.clientName,
        'age': r.age,
        'phone_number': r.phoneNumber,
        'client_id': r.clientId,
        'sex': r.sex,
        'client_groups': r.clientGroups,
        'first_time_visit': r.firstTimeVisit,
        'referred_from': r.referredFrom,
        'other_referred_from': r.otherReferredFrom,
        'educated_on_hiv_prevention': r.educatedOnHivPrevention,
        'educated_on_hiv_testing_options': r.educatedOnHivTestingOptions,
        'educated_on_malaria_prevention': r.educatedOnMalariaPrevention,
        // Some backends use this legacy NOT NULL column name.
        'educated_on_malaria_prevention_treatment': r.educatedOnMalariaPrevention,
        'referral_services': r.referralServices,
        'other_referral_service': r.otherReferralService,
        'referral_facility': r.referralFacility,
        'sync_status': r.syncStatus.name,
        'created_at': r.createdAt.toIso8601String(),
        'updated_at': r.updatedAt.toIso8601String(),
      };

  Future<void> _upsertRemote(PreventionMessagingRecord record) async {
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) throw StateError('Not authenticated');

    // Always ensure remote row is owned by authenticated user.
    final repaired = _looksLikeUuid(record.userId) ? record : record.copyWith(userId: authUser.id, syncStatus: SyncStatus.pending, updatedAt: DateTime.now());

    final candidates = <Map<String, dynamic>>[
      Map<String, dynamic>.from(_toDbJsonLower(repaired)),
      Map<String, dynamic>.from(_toDbJsonSnake(repaired)),
    ];

    Object? lastErr;
    for (final original in candidates) {
      final payload = Map<String, dynamic>.from(original);

      payload.removeWhere((k, _) => _remoteRejectedColumnsLower.contains(k.toLowerCase()));

      // Defensive: avoid camelCase leaks.
      payload.remove('userId');
      payload.remove('clientId');
      payload.remove('clientName');
      payload.remove('phoneNumber');
      payload.remove('createdAt');
      payload.remove('updatedAt');
      payload.remove('syncStatus');

      // Force auth uid into either schema key if present.
      if (payload.containsKey('userid')) payload['userid'] = authUser.id;
      if (payload.containsKey('user_id')) payload['user_id'] = authUser.id;

      // IMPORTANT: do not drop either `userid` or `user_id`.
      // Different deployments use different RLS policies, and dropping the wrong one
      // can cause: "new row violates row-level security policy".

      if (payload.containsKey('clientname') || payload.containsKey('referredfrom')) {
        _ensurePresent(payload, 'clientname', repaired.clientName);
        _ensurePresent(payload, 'clientid', repaired.clientId);
        _ensurePresent(payload, 'userid', authUser.id);
      }
      if (payload.containsKey('client_name') || payload.containsKey('referred_from')) {
        _ensurePresent(payload, 'client_name', repaired.clientName);
        _ensurePresent(payload, 'client_id', repaired.clientId);
        _ensurePresent(payload, 'user_id', authUser.id);
      }

      final maxAttempts = payload.keys.length.clamp(8, 40);
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        try {
          await SupabaseService.upsert('prevention_messaging_records', payload, onConflict: 'id');
          return;
        } catch (e) {
          lastErr = e;

          if (_isNotNullViolation(e)) {
            debugPrint('PreventionMessaging upsert not-null violation; trying next schema candidate: $e');
            break;
          }

          if (!_isSchemaColumnError(e)) rethrow;

          final missingRaw = _extractMissingColumn(e);
          final missing = missingRaw?.trim();
          debugPrint(
            'PreventionMessaging upsert schema mismatch (attempt ${attempt + 1}/$maxAttempts) - missing=$missing; payloadKeys=${payload.keys.toList()}',
          );
          if (missing == null) break;

          _remoteRejectedColumnsLower.add(missing.toLowerCase());

          final keyToRemove = payload.keys.cast<String?>().firstWhere(
                (k) => k != null && k.toLowerCase() == missing.toLowerCase(),
                orElse: () => null,
              );
          if (keyToRemove != null) {
            payload.remove(keyToRemove);
            continue;
          }

          break;
        }
      }
    }

    throw lastErr ?? Exception('Failed to upsert prevention messaging record');
  }
}
