import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mediflow/supabase/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Location reference lookups (State -> LGA -> Ward).
///
/// Backend source-of-truth: `public.ng_wards`.
///
/// This service is intentionally defensive:
/// - If the table doesn't exist yet (migration not applied), it returns an empty list.
/// - It caches results locally for snappy UX and offline resilience.
class LocationReferenceService {
  static const String wardsTable = 'ng_wards';

  static String _normalizeState(String state) {
    final s = state.trim();
    if (s == 'FCT') return 'Abuja FCT';
    return s;
  }

  static String _wardsPrefsKey({required String state, required String lga}) => 'wards:${state.trim()}:${lga.trim()}';

  static Future<List<String>> fetchWards({required String state, required String lga}) async {
    final s = _normalizeState(state);
    final l = lga.trim();
    if (s.isEmpty || l.isEmpty) return const [];

    // 1) Remote (source-of-truth)
    try {
      final rows = await SupabaseService.select(
        wardsTable,
        select: 'ward_name',
        filters: {'state': s, 'lga': l},
        orderBy: 'ward_name',
        ascending: true,
      );

      final wards = rows
          .map((r) => (r['ward_name'] ?? '').toString().trim())
          .where((w) => w.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      await _cacheWards(state: s, lga: l, wards: wards);
      return wards;
    } catch (e) {
      // If the reference table isn't deployed yet, treat as “no wards available”
      // (UI will show empty state and ward remains optional).
      final msg = e.toString();
      if (msg.contains('42P01') || msg.contains('relation') && msg.contains('does not exist')) {
        return const [];
      }
      debugPrint('fetchWards remote failed (falling back to local): $e');
    }

    // 2) Local cache fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_wardsPrefsKey(state: s, lga: l));
      if (raw == null) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final wards = decoded.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toSet().toList(growable: false)
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      // Auto-sanitize cache.
      await _cacheWards(state: s, lga: l, wards: wards);
      return wards;
    } catch (e) {
      debugPrint('fetchWards local cache failed: $e');
      return const [];
    }
  }

  static Future<void> _cacheWards({required String state, required String lga, required List<String> wards}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_wardsPrefsKey(state: state, lga: lga), jsonEncode(wards));
    } catch (e) {
      debugPrint('cacheWards failed: $e');
    }
  }
}
