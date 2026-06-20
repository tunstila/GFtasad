import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mediflow/models/business_address.dart';
import 'package:mediflow/supabase/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BusinessAddressService {
  static const String tableName = 'user_business_addresses';

  static String _prefsKey(String userId) => 'businessAddress:$userId';

  static Future<BusinessAddress?> fetch({required String userId}) async {
    final id = userId.trim();
    if (id.isEmpty) return null;

    // 1) Try remote (source of truth)
    try {
      final row = await SupabaseService.selectSingle(tableName, filters: {'user_id': id});
      if (row != null) {
        final addr = BusinessAddress.fromJson(row);
        await _cacheLocal(addr);
        return addr;
      }
    } catch (e) {
      debugPrint('BusinessAddress fetch remote failed (falling back to local): $e');

      // Fallback: older deployments stored businessAddress on public.users.
      try {
        final userRow = await SupabaseService.selectSingle('users', filters: {'id': id});
        if (userRow != null) {
          final fromUsers = BusinessAddress.fromJson({
            'user_id': id,
            'business_address': userRow['businessAddress'] ?? userRow['business_address'] ?? '',
            'ward': userRow['ward'] ?? userRow['business_ward'],
            'state': userRow['state'] ?? '',
            'lga': userRow['lga'] ?? '',
            'latitude': userRow['latitude'] ?? userRow['lat'],
            'longitude': userRow['longitude'] ?? userRow['lng'],
            'created_at': userRow['createdAt'] ?? userRow['created_at'],
            'updated_at': userRow['updatedAt'] ?? userRow['updated_at'],
          });
          if (fromUsers.businessAddress.trim().isNotEmpty) {
            await _cacheLocal(fromUsers);
            return fromUsers;
          }
        }
      } catch (e2) {
        debugPrint('BusinessAddress fetch users fallback failed: $e2');
      }
    }

    // 2) Fall back to local cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey(id));
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return BusinessAddress.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      debugPrint('BusinessAddress fetch local failed: $e');
      return null;
    }
  }

  static Future<bool> upsert(BusinessAddress address) async {
    final id = address.userId.trim();
    if (id.isEmpty) return false;

    await _cacheLocal(address);

    // Best-effort remote upsert.
    try {
      await SupabaseService.upsert(
        tableName,
        {
          'user_id': id,
          'business_address': address.businessAddress,
          'ward': address.ward,
          'state': address.state,
          'lga': address.lga,
          'latitude': address.latitude,
          'longitude': address.longitude,
          'created_at': address.createdAt.toIso8601String(),
          'updated_at': address.updatedAt.toIso8601String(),
        },
        onConflict: 'user_id',
      );
      return true;
    } catch (e) {
      debugPrint('BusinessAddress upsert remote failed (saved locally): $e');
      return false;
    }
  }

  static Future<void> _cacheLocal(BusinessAddress address) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey(address.userId), jsonEncode(address.toJson()));
    } catch (e) {
      debugPrint('BusinessAddress cache failed: $e');
    }
  }
}
