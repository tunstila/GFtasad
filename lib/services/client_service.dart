import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mediflow/models/client.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/supabase/supabase_config.dart';
import 'package:mediflow/utils/ng_locations.dart';
import 'package:uuid/uuid.dart';

class ClientService extends ChangeNotifier {
  static const _uuid = Uuid();

  static String _loc3(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return 'UNK';
    final cleaned = v.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    if (cleaned.isEmpty) return 'UNK';
    final first = cleaned.length >= 3 ? cleaned.substring(0, 3) : cleaned.padRight(3, 'X');
    return first;
  }

  static int _stable7DigitFromUuidV4() {
    // Not guaranteed unique (offline placeholder only), but always 7 digits.
    final hex = _uuid.v4().replaceAll('-', '');
    final n = int.tryParse(hex.substring(0, 7), radix: 16) ?? 0;
    return n % 10000000;
  }

  /// Location prefix for IDs: `SSS-LLL-WWW`.
  ///
  /// Normalization:
  /// - trim spaces
  /// - remove special characters
  /// - uppercase
  /// - ignore spaces and hyphens by stripping non-letters
  /// - fallback to UNK for missing
  static String buildLocationPrefix({required String? state, required String? lga, required String? ward}) =>
      '${_loc3(state)}-${_loc3(lga)}-${_loc3(ward)}';

  /// Generates a provisional code in the new format for offline-first flows.
  ///
  /// The backend edge function still guarantees uniqueness; this is only used
  /// so the user sees the correct prefix immediately while offline.
  /// Code format: `STATE-LGA-TYPE-0000001`.
  ///
  /// Offline-first placeholder: keeps the exact format, but the numeric part is a
  /// local-only placeholder until the backend allocates the real sequential code.
  static String generateLocalProvisionalClientId(User? user) {
    final stateCode = NgLocations.stateTo3LetterCode(user?.state) ?? _loc3(user?.state);
    final lgaCode = _loc3(user?.lga);
    final wardRaw = (user?.ward ?? '').trim();
    // Strict behavior: never default to ALL. If ward is missing, use UNK for a
    // clearly-non-canonical offline placeholder.
    final typeCode = wardRaw.isEmpty ? 'UNK' : _loc3(wardRaw);

    final seq = _stable7DigitFromUuidV4();
    final seqStr = seq.toString().padLeft(7, '0');
    return '${stateCode.toUpperCase()}-${lgaCode.toUpperCase()}-$typeCode-$seqStr';
  }

  /// Lookup a client by their public client ID.
  Future<Client?> fetchByClientId(String clientId) async {
    final id = clientId.trim();
    if (id.isEmpty) return null;
    try {
      try {
        final rows = await SupabaseService.select('clients', filters: {'clientid': id});
        if (rows.isNotEmpty) return Client.fromJson(rows.first);
      } catch (_) {
        // ignore
      }
      final rows = await SupabaseService.select('clients', filters: {'clientId': id});
      if (rows.isNotEmpty) return Client.fromJson(rows.first);
      return null;
    } catch (e) {
      debugPrint('Client lookup failed: $e');
      return null;
    }
  }

  /// Creates (or upserts) a client for the current field provider.
  ///
  /// If [desiredClientId] is empty, an ID is allocated atomically via the edge function.
  Future<Client?> createOrUpdateForCurrentProvider({
    required String name,
    required String sex,
    required String phoneNumber,
    DateTime? dateOfBirth,
    String? desiredClientId,
    String? ward,
  }) async {
    try {
      final wardNorm = (ward ?? '').trim();
      final res = await SupabaseConfig.client.functions.invoke(
        'id_management',
        body: {
          'action': 'upsert_client',
          'desiredClientId': (desiredClientId ?? '').trim(),
          'name': name.trim(),
          'sex': sex.trim(),
          'phoneNumber': phoneNumber.trim(),
          'dateOfBirth': dateOfBirth?.toIso8601String(),
          // Backwards-compatible: edge function defaults to ALL when missing.
          'typeSegment': wardNorm,
        },
      );

      final data = res.data;
      if (data is String) {
        final decoded = jsonDecode(data);
        return decoded is Map ? Client.fromJson(Map<String, dynamic>.from(decoded)) : null;
      }
      if (data is Map) return Client.fromJson(Map<String, dynamic>.from(data));
      return null;
    } catch (e) {
      debugPrint('Client upsert failed: $e');
      return null;
    }
  }
}
