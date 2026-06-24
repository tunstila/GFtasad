import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mediflow/models/stock_request.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/supabase/supabase_config.dart';

class StockRequestService extends ChangeNotifier {
  List<StockRequest> _providerRequests = const [];
  List<StockRequest> _supplierRequests = const [];
  List<StockRequest> _allRequests = const [];
  bool _isLoading = false;

  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSub;

  List<StockRequest> get providerRequests => _providerRequests;
  List<StockRequest> get supplierRequests => _supplierRequests;
  List<StockRequest> get allRequests => _allRequests;
  bool get isLoading => _isLoading;

  int getPendingCountAll() =>
      _allRequests.where((r) => r.status == StockRequestStatus.pending).length;

  int getTotalCountAll() => _allRequests.length;

  Future<void> loadAllForAdmin() async {
    try {
      List<Map<String, dynamic>> rows;
      try {
        rows = await SupabaseService.select('stock_requests', orderBy: 'createdat', ascending: false);
      } catch (_) {
        rows = await SupabaseService.select('stock_requests', orderBy: 'createdAt', ascending: false);
      }
      _allRequests = rows.map(_mapRow).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load all stock requests (admin): $e');
      _allRequests = const [];
      notifyListeners();
    }
  }

  Future<void> startRealtimeForAdmin() async {
    await stopRealtime();
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) return;

    try {
      final query = SupabaseConfig.client.from('stock_requests').stream(primaryKey: ['id']).order('createdat', ascending: false);
      _realtimeSub = query.listen((rows) {
        try {
          _allRequests = rows.map(_mapRow).toList();
          notifyListeners();
        } catch (e) {
          debugPrint('Stock requests realtime apply failed: $e');
        }
      });
    } catch (e) {
      debugPrint('Failed to start stock requests realtime: $e');
    }
  }

  Future<void> stopRealtime() async {
    await _realtimeSub?.cancel();
    _realtimeSub = null;
  }

  Future<List<User>> fetchSuppliers() async {
    try {
      final rows = await SupabaseService.select('users', filters: {'role': UserRole.supplier.name}, orderBy: 'username', ascending: true);
      return rows.map((e) => User.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Failed to fetch suppliers: $e');
      rethrow;
    }
  }

  Future<void> loadForProvider(String providerId) async {
    _isLoading = true;
    notifyListeners();
    try {
      List<Map<String, dynamic>> rows;
      try {
        rows = await SupabaseService.select('stock_requests', filters: {'providerid': providerId}, orderBy: 'createdat', ascending: false);
      } catch (_) {
        rows = await SupabaseService.select('stock_requests', filters: {'providerId': providerId}, orderBy: 'createdAt', ascending: false);
      }
      _providerRequests = rows.map(_mapRow).toList();
    } catch (e) {
      debugPrint('Failed to load provider stock requests: $e');
      _providerRequests = const [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadForSupplier(String supplierId) async {
    _isLoading = true;
    notifyListeners();
    try {
      List<Map<String, dynamic>> rows;
      try {
        rows = await SupabaseService.select('stock_requests', filters: {'supplierid': supplierId}, orderBy: 'createdat', ascending: false);
      } catch (_) {
        rows = await SupabaseService.select('stock_requests', filters: {'supplierId': supplierId}, orderBy: 'createdAt', ascending: false);
      }
      _supplierRequests = rows.map(_mapRow).toList();
    } catch (e) {
      debugPrint('Failed to load supplier stock requests: $e');
      _supplierRequests = const [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> createRequest({required User provider, required User supplier, required List<StockRequestItem> items, String? notes}) async {
    final now = DateTime.now();
    final payload = {
      'providerid': provider.id,
      'providername': provider.username,
      'provideremail': provider.email,
      'providerfacilityname': provider.facilityName,
      'providerbusinessaddress': provider.businessAddress,
      'providerstate': provider.state,
      'providerlga': provider.lga,
      'providerlatitude': provider.latitude,
      'providerlongitude': provider.longitude,
      'supplierid': supplier.id,
      'suppliername': supplier.username,
      'status': StockRequestStatus.pending.toDb(),
      'items': items.map((e) => e.toJson()).toList(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      'createdat': now.toIso8601String(),
      'updatedat': now.toIso8601String(),
    };

    try {
      final inserted = await SupabaseService.insert('stock_requests', payload);
      final id = inserted.isNotEmpty ? inserted.first['id']?.toString() : null;
      // Best-effort refresh.
      await Future.wait([
        loadForProvider(provider.id),
        loadForSupplier(supplier.id),
      ]);
      return id;
    } catch (e) {
      debugPrint('Failed to create stock request: $e');
      rethrow;
    }
  }

  Future<void> updateStatus({required String requestId, required StockRequestStatus status}) async {
    try {
      await SupabaseService.update('stock_requests', {'status': status.toDb(), 'updatedat': DateTime.now().toIso8601String()}, filters: {'id': requestId});
    } catch (e) {
      debugPrint('Failed to update stock request status: $e');
      rethrow;
    }
  }

  StockRequest _mapRow(Map<String, dynamic> row) {
    // items stored as jsonb or text; support both.
    final raw = row['items'];
    List<dynamic> decoded;
    if (raw is String) {
      decoded = jsonDecode(raw) as List<dynamic>;
    } else if (raw is List) {
      decoded = raw;
    } else {
      decoded = const [];
    }

    final out = <String, dynamic>{...row, 'items': decoded};
    void mapKey(String from, String to) {
      if (out.containsKey(from) && !out.containsKey(to)) out[to] = out[from];
    }

    mapKey('providerid', 'providerId');
    mapKey('providername', 'providerName');
    mapKey('provideremail', 'providerEmail');
    mapKey('providerfacilityname', 'providerFacilityName');
    mapKey('providerbusinessaddress', 'providerBusinessAddress');
    mapKey('providerstate', 'providerState');
    mapKey('providerlga', 'providerLga');
    mapKey('providerlatitude', 'providerLatitude');
    mapKey('providerlongitude', 'providerLongitude');
    mapKey('supplierid', 'supplierId');
    mapKey('suppliername', 'supplierName');
    mapKey('createdat', 'createdAt');
    mapKey('updatedat', 'updatedAt');

    for (final key in ['createdAt', 'updatedAt']) {
      final v = out[key];
      if (v is DateTime) out[key] = v.toIso8601String();
    }

    return StockRequest.fromJson(out);
  }
}
