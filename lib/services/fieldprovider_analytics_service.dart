import 'package:flutter/foundation.dart';
import 'package:mediflow/supabase/supabase_config.dart';

class FieldProviderBreakdownEntry {
  final String label;
  final int totalCount;

  const FieldProviderBreakdownEntry({required this.label, required this.totalCount});

  factory FieldProviderBreakdownEntry.fromStateRow(Map<String, dynamic> json) => FieldProviderBreakdownEntry(
    label: (json['state'] ?? 'Unknown').toString(),
    totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
  );

  factory FieldProviderBreakdownEntry.fromTypeRow(Map<String, dynamic> json) => FieldProviderBreakdownEntry(
    label: (json['provider_type'] ?? 'Unknown').toString(),
    totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
  );
}

class FieldProviderAnalyticsRow {
  final String profileId;
  final String username;
  final String email;
  final String? contactEmail;
  final String state;
  final String providerType;
  final DateTime createdAt;

  const FieldProviderAnalyticsRow({
    required this.profileId,
    required this.username,
    required this.email,
    required this.contactEmail,
    required this.state,
    required this.providerType,
    required this.createdAt,
  });

  factory FieldProviderAnalyticsRow.fromJson(Map<String, dynamic> json) {
    final createdRaw = json['created_at'] ?? json['createdAt'];
    return FieldProviderAnalyticsRow(
      profileId: (json['profile_id'] ?? json['profileId'] ?? '').toString(),
      username: (json['username'] ?? '').toString().trim().isEmpty ? 'Unknown' : (json['username'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      contactEmail: (json['contact_email'] ?? json['contactEmail'])?.toString(),
      state: (json['state'] ?? 'Unknown').toString(),
      providerType: (json['provider_type'] ?? json['providerType'] ?? 'Unknown').toString(),
      createdAt: createdRaw == null ? DateTime.now() : (DateTime.tryParse(createdRaw.toString()) ?? DateTime.now()),
    );
  }
}

class FieldProviderAnalyticsSnapshot {
  final int total;
  final List<FieldProviderBreakdownEntry> byState;
  final List<FieldProviderBreakdownEntry> byType;
  final List<FieldProviderAnalyticsRow> rows;

  const FieldProviderAnalyticsSnapshot({required this.total, required this.byState, required this.byType, required this.rows});
}

class FieldProviderAnalyticsService extends ChangeNotifier {
  int? _cachedTotal;
  DateTime? _lastUpdated;
  Object? _lastError;

  int? get cachedTotal => _cachedTotal;
  DateTime? get lastUpdated => _lastUpdated;
  Object? get lastError => _lastError;

  void invalidate() {
    _cachedTotal = null;
    _lastUpdated = null;
    _lastError = null;
    notifyListeners();
  }

  Future<int> fetchTotal({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedTotal != null) return _cachedTotal!;
    try {
      final res = await SupabaseConfig.client.rpc('get_fieldprovider_total');
      final v = (res as num?)?.toInt() ?? 0;
      _cachedTotal = v;
      _lastUpdated = DateTime.now();
      _lastError = null;
      notifyListeners();
      return v;
    } catch (e) {
      debugPrint('get_fieldprovider_total failed: $e');
      // Production-safe behavior: keep the dashboard usable even if the backend
      // RPC/view wasn't deployed yet or RLS denies access.
      _lastError = e;
      _cachedTotal ??= 0;
      notifyListeners();
      return _cachedTotal!;
    }
  }

  Future<List<FieldProviderBreakdownEntry>> fetchBreakdownByState({String? selectedProviderType}) async {
    try {
      final res = await SupabaseConfig.client.rpc(
        'get_fieldprovider_breakdown_by_state',
        params: {'selected_provider_type': selectedProviderType},
      );
      final rows = (res as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      return rows.map(FieldProviderBreakdownEntry.fromStateRow).toList();
    } catch (e) {
      debugPrint('get_fieldprovider_breakdown_by_state failed: $e');
      rethrow;
    }
  }

  Future<List<FieldProviderBreakdownEntry>> fetchBreakdownByType({String? selectedState}) async {
    try {
      final res = await SupabaseConfig.client.rpc(
        'get_fieldprovider_breakdown_by_type',
        params: {'selected_state': selectedState},
      );
      final rows = (res as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      return rows.map(FieldProviderBreakdownEntry.fromTypeRow).toList();
    } catch (e) {
      debugPrint('get_fieldprovider_breakdown_by_type failed: $e');
      rethrow;
    }
  }

  Future<List<FieldProviderAnalyticsRow>> fetchFilteredList({String? selectedState, String? selectedProviderType}) async {
    try {
      final res = await SupabaseConfig.client.rpc(
        'get_fieldprovider_filtered_list',
        params: {
          'selected_state': selectedState,
          'selected_provider_type': selectedProviderType,
        },
      );
      final rows = (res as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      return rows.map(FieldProviderAnalyticsRow.fromJson).toList();
    } catch (e) {
      debugPrint('get_fieldprovider_filtered_list failed: $e');
      rethrow;
    }
  }

  Future<FieldProviderAnalyticsSnapshot> fetchSnapshot({String? selectedState, String? selectedProviderType}) async {
    final results = await Future.wait([
      fetchTotal(forceRefresh: true),
      fetchBreakdownByState(selectedProviderType: selectedProviderType),
      fetchBreakdownByType(selectedState: selectedState),
      fetchFilteredList(selectedState: selectedState, selectedProviderType: selectedProviderType),
    ]);

    return FieldProviderAnalyticsSnapshot(
      total: results[0] as int,
      byState: results[1] as List<FieldProviderBreakdownEntry>,
      byType: results[2] as List<FieldProviderBreakdownEntry>,
      rows: results[3] as List<FieldProviderAnalyticsRow>,
    );
  }
}
