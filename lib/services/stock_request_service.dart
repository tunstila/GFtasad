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
      final rows = await SupabaseService.select('stock_requests', orderBy: 'createdAt', ascending: false);
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
      final query = SupabaseConfig.client
          .from('stock_requests')
          .stream(primaryKey: ['id'])
          .order('createdAt', ascending: false);
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
      final query = SupabaseConfig.client
          .from('users')
          .select('*')
          .ilike('role', UserRole.supplier.name)
          .ilike('approvalStatus', UserApprovalStatus.approved.name)
          .order('username', ascending: true);
      final rows = await query as List;
      return rows.map((e) => User.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (e) {
      // Back-compat: some environments may still use snake_case `approval_status`.
      try {
        final query = SupabaseConfig.client
            .from('users')
            .select('*')
            .ilike('role', UserRole.supplier.name)
            .ilike('approval_status', UserApprovalStatus.approved.name)
            .order('username', ascending: true);
        final rows = await query as List;
        return rows.map((e) => User.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      } catch (e2) {
        debugPrint('Failed to fetch suppliers: $e2');
        rethrow;
      }
    }
  }

  Future<void> supplierAccept({required String requestId, String? responseNote}) async {
    try {
      await SupabaseConfig.client.rpc(
        'supplier_accept_stock_request',
        params: {
          'p_request_id': requestId,
          'p_response_note': responseNote,
        },
      );
    } catch (e) {
      debugPrint('supplier_accept_stock_request RPC failed: $e');
      rethrow;
    }

    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser != null) await loadForSupplier(authUser.id);
  }

  Future<void> supplierReject({required String requestId, String? responseNote}) async {
    try {
      await SupabaseConfig.client.rpc(
        'supplier_reject_stock_request',
        params: {
          'p_request_id': requestId,
          'p_response_note': responseNote,
        },
      );
    } catch (e) {
      debugPrint('supplier_reject_stock_request RPC failed: $e');
      rethrow;
    }

    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser != null) await loadForSupplier(authUser.id);
  }

  Future<void> loadForProvider(String providerId) async {
    _isLoading = true;
    notifyListeners();
    try {
      final rows = await SupabaseService.select('stock_requests', filters: {'providerId': providerId}, orderBy: 'createdAt', ascending: false);
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
      final rows = await SupabaseService.select('stock_requests', filters: {'supplierId': supplierId}, orderBy: 'createdAt', ascending: false);
      _supplierRequests = rows.map(_mapRow).toList();
    } catch (e) {
      debugPrint('Failed to load supplier stock requests: $e');
      _supplierRequests = const [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String> createRestockRequest({
    required String supplierId,
    required String commodityId,
    required int quantityRequested,
    required String unitOfExpression,
    String? notes,
  }) async {
    try {
      final res = await SupabaseConfig.client.rpc(
        'create_restock_request',
        params: {
          'p_supplier_id': supplierId,
          'p_commodity_id': commodityId,
          'p_quantity_requested': quantityRequested,
          'p_unit_of_expression': unitOfExpression,
          'p_notes': notes,
        },
      );

      // RPC returns a UUID (as String) in most PostgREST configurations.
      final id = res?.toString();
      if (id == null || id.trim().isEmpty) {
        throw Exception('Restock request created but no id returned');
      }

      // Best-effort refresh for current user context.
      final authUser = SupabaseConfig.auth.currentUser;
      if (authUser != null) {
        await Future.wait([
          loadForProvider(authUser.id),
          loadForSupplier(authUser.id),
        ]);
      }

      return id;
    } catch (e) {
      debugPrint('create_restock_request RPC failed: $e');
      rethrow;
    }
  }

  Future<String?> createRequest({required User provider, required User supplier, required List<StockRequestItem> items, String? notes}) async {
    final now = DateTime.now();
    final payload = {
      'providerId': provider.id,
      'providerName': provider.username,
      'providerEmail': provider.email,
      'providerFacilityName': provider.facilityName,
      'providerBusinessAddress': provider.businessAddress,
      'providerState': provider.state,
      'providerLga': provider.lga,
      'providerLatitude': provider.latitude,
      'providerLongitude': provider.longitude,
      'supplierId': supplier.id,
      'supplierName': supplier.username,
      'status': StockRequestStatus.pending.toDb(),
      'items': items.map((e) => e.toJson()).toList(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
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
      await SupabaseService.update('stock_requests', {'status': status.toDb(), 'updatedAt': DateTime.now().toIso8601String()}, filters: {'id': requestId});
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

    return StockRequest.fromJson({
      ...row,
      'items': decoded,
    });
  }
}
