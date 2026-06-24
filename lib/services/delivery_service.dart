import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediflow/models/delivery.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/supabase/supabase_config.dart';
import 'package:uuid/uuid.dart';

class DeliveryService extends ChangeNotifier {
  static const _uuid = Uuid();
  List<Delivery> _deliveries = [];
  bool _isLoading = false;

  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSub;

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

  static String? _extractMissingColumn(Object e) {
    final msg = e.toString();
    final m1 = RegExp(r"Could not find the '([^']+)' column").firstMatch(msg);
    if (m1 != null) return m1.group(1);
    final m2 = RegExp(r'column\s+[\w\.]+\.(\w+)\s+does not exist').firstMatch(msg);
    if (m2 != null) return m2.group(1);
    return null;
  }

  Delivery _repairDeliveryForAuth(Delivery d, {required String authUserId}) {
    // Older local sample data uses providerId like "provider1" which will fail
    // when the remote schema expects a UUID.
    var out = d;
    if (!_looksLikeUuid(out.providerId)) {
      out = out.copyWith(providerId: authUserId, syncStatus: SyncStatus.pending, updatedAt: DateTime.now());
    }

    // Some older local/sample deliveries also used placeholder supplier ids like "supplier1".
    // In production schemas, supplier_id is typically a UUID FK; sending a placeholder causes:
    // "invalid input syntax for type uuid: \"supplier1\"".
    // We can't reliably infer the real supplier UUID offline, so we repair to the authenticated
    // user id (only for clearly-placeholder values) to unblock sync.
    if (!_looksLikeUuid(out.supplierId)) {
      final s = out.supplierId.trim().toLowerCase();
      final looksPlaceholder = s.isEmpty || s == 'supplier1' || s == 'supplier' || s.startsWith('supplier');
      if (looksPlaceholder) {
        out = out.copyWith(supplierId: authUserId, syncStatus: SyncStatus.pending, updatedAt: DateTime.now());
      }
    }
    return out;
  }

  Future<void> _upsertDeliveryRemote(Delivery delivery, {required String authUserId}) async {
    final repaired = _repairDeliveryForAuth(delivery, authUserId: authUserId);
    final candidates = <Map<String, dynamic>>[
      // Prefer snake_case first (most common in production Supabase schemas).
      {
        'id': repaired.id,
        'supplier_id': repaired.supplierId,
        'supplier_name': repaired.supplierName,
        'provider_id': authUserId,
        'delivery_date': repaired.deliveryDate.toIso8601String(),
        'reference': repaired.reference,
        'items': repaired.items.map((e) => e.toJson()).toList(),
        'status': repaired.status.name,
        'sync_status': repaired.syncStatus.name,
        'created_at': repaired.createdAt.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      // Lowercased unquoted-camelCase identifiers: createdAt -> createdat, providerId -> providerid.
      Map<String, dynamic>.from(_deliveryToDbJsonLower(repaired))..['providerid'] = authUserId,
      // Legacy camelCase (least likely).
      Map<String, dynamic>.from(_normalizeDates(_deliveryToSupabaseJson(repaired)))..['providerId'] = authUserId,
    ];

    Object? lastErr;
    for (final original in candidates) {
      final payload = Map<String, dynamic>.from(original);

      // Always enforce provider id on every schema variant.
      if (payload.containsKey('providerid')) payload['providerid'] = authUserId;
      if (payload.containsKey('provider_id')) payload['provider_id'] = authUserId;
      if (payload.containsKey('providerId')) payload['providerId'] = authUserId;

      for (var attempt = 0; attempt < 6; attempt++) {
        try {
          await SupabaseService.upsert('deliveries', payload, onConflict: 'id');
          return;
        } catch (e) {
          lastErr = e;
          if (!_isSchemaColumnError(e)) rethrow;
          final missing = _extractMissingColumn(e);
          if (missing == null) break;
          if (payload.containsKey(missing)) {
            payload.remove(missing);
            continue;
          }
          break;
        }
      }
    }

    throw lastErr ?? Exception('Failed to upsert delivery');
  }

  List<Delivery> get deliveries => _deliveries;
  bool get isLoading => _isLoading;

  Future<void> startRealtime({required bool forAdmin, required String providerId}) async {
    await stopRealtime();
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) return;

    try {
      final query = SupabaseConfig.client.from('deliveries').stream(primaryKey: ['id']).order('deliverydate', ascending: false);

      _realtimeSub = query.listen((rows) async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final filtered = forAdmin
              ? rows
              : rows.where((r) => (r['providerid'] ?? r['provider_id'] ?? r['providerId'])?.toString() == providerId).toList();
          _deliveries = filtered.map((row) {
            return Delivery.fromJson(_fromDbRow(row)).copyWith(syncStatus: SyncStatus.synced);
          }).toList();
          await _saveDeliveries(prefs);
          notifyListeners();
        } catch (e) {
          debugPrint('Delivery realtime apply failed: $e');
        }
      });
    } catch (e) {
      debugPrint('Failed to start deliveries realtime: $e');
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
      final prefs = await SharedPreferences.getInstance();
      final deliveriesJson = prefs.getString('deliveries');

      if (deliveriesJson != null) {
        final decoded = jsonDecode(deliveriesJson) as List;
        _deliveries = decoded.map((e) {
          try {
            return Delivery.fromJson(e);
          } catch (err) {
            debugPrint('Skipping corrupted delivery: $err');
            return null;
          }
        }).whereType<Delivery>().toList();
        
        if (_deliveries.length != decoded.length) {
          await _saveDeliveries(prefs);
        }
      } else {
        if (SupabaseConfig.auth.currentUser == null) {
          await _createSampleData(prefs);
        } else {
          _deliveries = [];
        }
      }

      await _syncWithSupabase(prefs);
    } catch (e) {
      debugPrint('Failed to load deliveries: $e');
      _deliveries = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _syncWithSupabase(SharedPreferences prefs) async {
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) return;

    // Auto-repair legacy local ids (e.g. providerId="provider1") so existing failed
    // pending deliveries can sync successfully.
    var repairedAny = false;
    final repaired = <Delivery>[];
    for (final d in _deliveries) {
      final fixed = _repairDeliveryForAuth(d, authUserId: authUser.id);
      repaired.add(fixed);
      if (!identical(fixed, d) && (fixed.providerId != d.providerId || fixed.syncStatus != d.syncStatus)) {
        repairedAny = true;
      }
    }
    if (repairedAny) {
      _deliveries = repaired;
      await _saveDeliveries(prefs);
      notifyListeners();
    }

    // Push pending local deliveries.
    final pending = _deliveries.where((d) => d.syncStatus == SyncStatus.pending || d.syncStatus == SyncStatus.failed).toList();
    if (pending.isNotEmpty) {
      for (final d in pending) {
        try {
          await _upsertDeliveryRemote(d, authUserId: authUser.id);
          _replaceLocal(d.copyWith(syncStatus: SyncStatus.synced, updatedAt: DateTime.now()));
        } catch (e) {
          debugPrint('Failed to push pending delivery ${d.id}: $e');
          _replaceLocal(d.copyWith(syncStatus: SyncStatus.failed, updatedAt: DateTime.now()));
        }
      }
    }

    // Pull from server (deliveries relevant to this provider).
    try {
      List<Map<String, dynamic>> remote;
      try {
        remote = await SupabaseService.select('deliveries', filters: {'providerid': authUser.id}, orderBy: 'deliverydate', ascending: false);
      } catch (e) {
        // Fallback for other schema styles.
        remote = await SupabaseService.select('deliveries', filters: {'provider_id': authUser.id}, orderBy: 'delivery_date', ascending: false);
      }

      final localById = {for (final d in _deliveries) d.id: d};
      var changed = false;

      for (final row in remote) {
        final remoteDelivery = Delivery.fromJson(_fromDbRow(row));
        final local = localById[remoteDelivery.id];
        if (local == null || remoteDelivery.updatedAt.isAfter(local.updatedAt)) {
          localById[remoteDelivery.id] = remoteDelivery.copyWith(syncStatus: SyncStatus.synced);
          changed = true;
        }
      }

      if (changed) {
        _deliveries = localById.values.toList()..sort((a, b) => b.deliveryDate.compareTo(a.deliveryDate));
        await _saveDeliveries(prefs);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Delivery Supabase pull failed (offline ok): $e');
    }
  }

  /// Admin-only: pull all deliveries (no providerId filter). Requires permissive RLS for admin roles.
  Future<void> syncAllForAdmin() async {
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final remote = await SupabaseService.select('deliveries', orderBy: 'deliveryDate', ascending: false);
      _deliveries = remote.map((row) {
        final normalized = _normalizeDates(row);
        return Delivery.fromJson(normalized).copyWith(syncStatus: SyncStatus.synced);
      }).toList();
      await _saveDeliveries(prefs);
      notifyListeners();
    } catch (e) {
      debugPrint('Admin delivery sync failed: $e');
      rethrow;
    }
  }

  void _replaceLocal(Delivery delivery) {
    final idx = _deliveries.indexWhere((d) => d.id == delivery.id);
    if (idx == -1) {
      _deliveries.insert(0, delivery);
    } else {
      _deliveries[idx] = delivery;
    }
  }

  Map<String, dynamic> _normalizeDates(Map<String, dynamic> json) {
    final out = Map<String, dynamic>.from(json);
    for (final key in ['deliveryDate', 'createdAt', 'updatedAt']) {
      final v = out[key];
      if (v is DateTime) out[key] = v.toIso8601String();
    }
    return out;
  }

  Map<String, dynamic> _fromDbRow(Map<String, dynamic> row) {
    // Most of our models still use camelCase, but the DB commonly ends up with lowercase
    // when columns were created as unquoted camelCase (e.g. createdAt -> createdat).
    final out = <String, dynamic>{...row};

    void mapKey(String from, String to) {
      if (out.containsKey(from) && !out.containsKey(to)) out[to] = out[from];
    }

    mapKey('supplierid', 'supplierId');
    mapKey('supplier_id', 'supplierId');
    mapKey('suppliername', 'supplierName');
    mapKey('supplier_name', 'supplierName');
    mapKey('providerid', 'providerId');
    mapKey('provider_id', 'providerId');
    mapKey('deliverydate', 'deliveryDate');
    mapKey('delivery_date', 'deliveryDate');
    mapKey('syncstatus', 'syncStatus');
    mapKey('sync_status', 'syncStatus');
    mapKey('createdat', 'createdAt');
    mapKey('created_at', 'createdAt');
    mapKey('updatedat', 'updatedAt');
    mapKey('updated_at', 'updatedAt');

    // Ensure date fields are ISO strings for our JSON model.
    for (final key in ['deliveryDate', 'createdAt', 'updatedAt']) {
      final v = out[key];
      if (v is DateTime) out[key] = v.toIso8601String();
    }

    // Items can come back as List<dynamic> already.
    final items = out['items'];
    if (items is List) {
      out['items'] = items.map((e) => (e is Map<String, dynamic>) ? e : Map<String, dynamic>.from(e as Map)).toList();
    }

    return out;
  }

  Map<String, dynamic> _deliveryToDbJsonLower(Delivery d) {
    final json = d.toJson();
    return {
      'id': json['id'],
      'supplierid': json['supplierId'],
      'suppliername': json['supplierName'],
      'providerid': json['providerId'],
      'deliverydate': json['deliveryDate'],
      'reference': json['reference'],
      'items': d.items.map((e) => e.toJson()).toList(),
      'status': json['status'],
      'syncstatus': json['syncStatus'],
      'createdat': json['createdAt'],
      'updatedat': json['updatedAt'],
    };
  }

  Map<String, dynamic> _deliveryToSupabaseJson(Delivery d) {
    // Supabase 'deliveries.items' is jsonb; we keep it as List<Map> not string.
    final json = d.toJson();
    json['items'] = d.items.map((e) => e.toJson()).toList();
    return json;
  }

  Future<void> _createSampleData(SharedPreferences prefs) async {
    final now = DateTime.now();
    _deliveries = [
      Delivery(
        id: _uuid.v4(),
        supplierId: 'supplier1',
        supplierName: 'Lagos Medical Supplies',
        providerId: 'provider1',
        deliveryDate: now,
        reference: 'DEL-2024-001',
        items: [
          DeliveryLineItem(
            commodityId: '1',
            commodityName: 'mRDT',
            quantityPushed: 50,
          ),
          DeliveryLineItem(
            commodityId: '2',
            commodityName: 'TopMal',
            quantityPushed: 30,
          ),
        ],
        status: DeliveryStatus.pending,
        createdAt: now,
        updatedAt: now,
      ),
      Delivery(
        id: _uuid.v4(),
        supplierId: 'supplier1',
        supplierName: 'Lagos Medical Supplies',
        providerId: 'provider1',
        deliveryDate: now.subtract(const Duration(days: 7)),
        reference: 'DEL-2024-002',
        items: [
          DeliveryLineItem(
            commodityId: '3',
            commodityName: 'PreP',
            quantityPushed: 25,
            quantityReceived: 25,
          ),
        ],
        status: DeliveryStatus.accepted,
        createdAt: now.subtract(const Duration(days: 7)),
        updatedAt: now.subtract(const Duration(days: 7)),
      ),
    ];
    await _saveDeliveries(prefs);
  }

  Future<void> _saveDeliveries(SharedPreferences prefs) async {
    await prefs.setString('deliveries', jsonEncode(_deliveries.map((d) => d.toJson()).toList()));
  }

  Future<void> addDelivery(Delivery delivery) async {
    _deliveries.insert(0, delivery);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await _saveDeliveries(prefs);

      if (SupabaseConfig.auth.currentUser != null) {
        try {
          await SupabaseService.upsert('deliveries', _normalizeDates(_deliveryToSupabaseJson(delivery)), onConflict: 'id');
          await updateDelivery(delivery.copyWith(syncStatus: SyncStatus.synced, updatedAt: DateTime.now()));
        } catch (e) {
          debugPrint('Supabase add delivery failed (kept local): $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to save delivery: $e');
    }
  }

  Future<void> updateDelivery(Delivery delivery) async {
    final index = _deliveries.indexWhere((d) => d.id == delivery.id);
    if (index != -1) {
      _deliveries[index] = delivery;
      notifyListeners();

      try {
        final prefs = await SharedPreferences.getInstance();
        await _saveDeliveries(prefs);

        if (SupabaseConfig.auth.currentUser != null) {
          try {
            await SupabaseService.upsert('deliveries', _normalizeDates(_deliveryToSupabaseJson(delivery)), onConflict: 'id');
          } catch (e) {
            debugPrint('Supabase update delivery failed (kept local): $e');
          }
        }
      } catch (e) {
        debugPrint('Failed to update delivery: $e');
      }
    }
  }

  int getPendingDeliveriesCount(String providerId) =>
      _deliveries.where((d) => d.providerId == providerId && d.status == DeliveryStatus.pending).length;

  int getPendingDeliveriesCountAll() =>
      _deliveries.where((d) => d.status == DeliveryStatus.pending).length;

  int getAcceptedDeliveriesCountAll() =>
      _deliveries.where((d) => d.status == DeliveryStatus.accepted).length;

  List<Delivery> getDeliveriesByProvider(String providerId) =>
      _deliveries.where((d) => d.providerId == providerId).toList();

  List<Delivery> getAllDeliveries() => List.unmodifiable(_deliveries);

  List<Delivery> getPendingDeliveries(String providerId) =>
      _deliveries.where((d) => d.providerId == providerId && d.status == DeliveryStatus.pending).toList();

  List<Delivery> getAcceptedDeliveries(String providerId) =>
      _deliveries.where((d) => d.providerId == providerId && d.status == DeliveryStatus.accepted).toList();

  Future<void> markAllPendingAsSynced({required String providerId}) async {
    final updated = _deliveries.map((d) {
      if (d.providerId != providerId) return d;
      if (d.syncStatus == SyncStatus.synced) return d;
      return d.copyWith(syncStatus: SyncStatus.synced, updatedAt: DateTime.now());
    }).toList();
    _deliveries = updated;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await _saveDeliveries(prefs);
    } catch (e) {
      debugPrint('Failed to mark deliveries synced: $e');
    }
  }
}
