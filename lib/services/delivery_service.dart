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

  List<Delivery> get deliveries => _deliveries;
  bool get isLoading => _isLoading;

  Future<void> startRealtime({required bool forAdmin, required String providerId}) async {
    await stopRealtime();
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) return;

    try {
      final query = SupabaseConfig.client.from('deliveries').stream(primaryKey: ['id']).order('deliveryDate', ascending: false);

      _realtimeSub = query.listen((rows) async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final filtered = forAdmin ? rows : rows.where((r) => r['providerId']?.toString() == providerId).toList();
          _deliveries = filtered.map((row) {
            final normalized = _normalizeDates(row);
            return Delivery.fromJson(normalized).copyWith(syncStatus: SyncStatus.synced);
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

    // Push pending local deliveries.
    final pending = _deliveries.where((d) => d.syncStatus == SyncStatus.pending || d.syncStatus == SyncStatus.failed).toList();
    if (pending.isNotEmpty) {
      for (final d in pending) {
        try {
          await SupabaseService.upsert('deliveries', _normalizeDates(_deliveryToSupabaseJson(d)), onConflict: 'id');
          _replaceLocal(d.copyWith(syncStatus: SyncStatus.synced, updatedAt: DateTime.now()));
        } catch (e) {
          debugPrint('Failed to push pending delivery ${d.id}: $e');
          _replaceLocal(d.copyWith(syncStatus: SyncStatus.failed, updatedAt: DateTime.now()));
        }
      }
    }

    // Pull from server (deliveries relevant to this provider).
    try {
      final remote = await SupabaseService.select(
        'deliveries',
        filters: {'providerId': authUser.id},
        orderBy: 'deliveryDate',
        ascending: false,
      );

      final localById = {for (final d in _deliveries) d.id: d};
      var changed = false;

      for (final row in remote) {
        final normalized = _normalizeDates(row);
        final remoteDelivery = Delivery.fromJson(normalized);
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

  int getPendingDeliveriesCountForSupplier(String supplierId) =>
      _deliveries.where((d) => d.supplierId == supplierId && d.status == DeliveryStatus.pending).length;

  List<Delivery> getDeliveriesByProvider(String providerId) =>
      _deliveries.where((d) => d.providerId == providerId).toList();

  List<Delivery> getDeliveriesBySupplier(String supplierId) =>
      _deliveries.where((d) => d.supplierId == supplierId).toList();

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
