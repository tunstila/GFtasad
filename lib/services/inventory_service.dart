import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediflow/models/commodity.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/supabase/supabase_config.dart';
import 'package:uuid/uuid.dart';

class InventoryService extends ChangeNotifier {
  static const _uuid = Uuid();
  List<Commodity> _commodities = [];
  List<StockMovement> _movements = [];
  Map<String, int> _minThresholdsByUserCommodity = {};
  Map<String, String> _batchNumberByUserCommodity = {};
  Map<String, String> _expiryDateByUserCommodity = {};
  Map<String, String> _unitOverrideByUserCommodity = {};
  bool _isLoading = false;

  StreamSubscription<List<Map<String, dynamic>>>? _commoditiesRealtimeSub;
  StreamSubscription<List<Map<String, dynamic>>>? _movementsRealtimeSub;

  List<Commodity> get commodities => _commodities;
  List<StockMovement> get movements => _movements;
  bool get isLoading => _isLoading;

  static String _thresholdKey(String userId, String commodityId) => '$userId:$commodityId';

  static String _settingsKey(String userId, String commodityId) => '$userId:$commodityId';

  static String? _normalizeBatch(String? input) {
    final trimmed = input?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static String? _formatDateOnly(DateTime? dt) {
    if (dt == null) return null;
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime? _tryParseDateOnly(Object? raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    // Accept either ISO datetime or ISO date.
    final parsed = DateTime.tryParse(s);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  int getMinThresholdForUser({required String userId, required Commodity commodity}) {
    final v = _minThresholdsByUserCommodity[_thresholdKey(userId, commodity.id)];
    return v ?? commodity.minThreshold;
  }

  String? getBatchNumberForUser({required String userId, required String commodityId}) {
    return _batchNumberByUserCommodity[_settingsKey(userId, commodityId)];
  }

  DateTime? getExpiryDateForUser({required String userId, required String commodityId}) {
    final raw = _expiryDateByUserCommodity[_settingsKey(userId, commodityId)];
    return _tryParseDateOnly(raw);
  }

  String? getUnitOverrideForUser({required String userId, required String commodityId}) => _unitOverrideByUserCommodity[_settingsKey(userId, commodityId)];

  /// Standardized unit-of-expression used for quantity display.
  ///
  /// Priority:
  /// 1) Per-provider override (`field_provider_commodity_settings.unit_override`) when valid
  /// 2) Commodity canonical unit_of_expression when valid
  /// 3) null (not set)
  String? getEffectiveUnitOfExpressionForUser({required String userId, required Commodity commodity}) {
    final override = UnitOfExpression.normalize(getUnitOverrideForUser(userId: userId, commodityId: commodity.id));
    if (override != null) return override;
    return UnitOfExpression.normalize(commodity.unitOfExpression);
  }

  String formatQuantityForUser({required String userId, required Commodity commodity, required int quantity, bool showNotSet = false}) {
    final u = getEffectiveUnitOfExpressionForUser(userId: userId, commodity: commodity);
    if (u == null) return showNotSet ? '$quantity (Not set)' : '$quantity';
    return '$quantity $u';
  }

  Future<void> setBatchExpiryForUser({
    required String userId,
    required String commodityId,
    String? batchNumber,
    DateTime? expiryDate,
    String? unitOverride,
  }) async {
    final batch = _normalizeBatch(batchNumber);
    final expiry = _formatDateOnly(expiryDate);

    final key = _settingsKey(userId, commodityId);
    if (batch == null) {
      _batchNumberByUserCommodity.remove(key);
    } else {
      _batchNumberByUserCommodity[key] = batch;
    }
    if (expiry == null) {
      _expiryDateByUserCommodity.remove(key);
    } else {
      _expiryDateByUserCommodity[key] = expiry;
    }

    final unit = UnitOfExpression.normalize(unitOverride);
    if (unit == null) {
      _unitOverrideByUserCommodity.remove(key);
    } else {
      _unitOverrideByUserCommodity[key] = unit;
    }
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await _saveBatchNumbers(prefs);
      await _saveExpiryDates(prefs);
      await _saveUnitOverrides(prefs);
    } catch (e) {
      debugPrint('Failed to save batch/expiry locally: $e');
    }

    // Best-effort remote persistence.
    // IMPORTANT: Never block the UI on network here; sheets/buttons expect this to return fast.
    unawaited(_syncCommoditySettingsToSupabase(
      userId: userId,
      commodityId: commodityId,
      batchNumber: batch,
      expiryDate: expiry,
      unitOverride: unit,
    ));
  }

  Future<void> _syncCommoditySettingsToSupabase({
    required String userId,
    required String commodityId,
    required String? batchNumber,
    required String? expiryDate,
    required String? unitOverride,
  }) async {
    try {
      if (SupabaseConfig.auth.currentUser == null) return;

      await SupabaseService.upsert(
        'field_provider_commodity_settings',
        {
          'field_provider_id': userId,
          'commodity_id': commodityId,
          'batch_number': batchNumber,
          'expiry_date': expiryDate,
          'unit_override': unitOverride,
        },
        onConflict: 'field_provider_id,commodity_id',
      ).timeout(const Duration(seconds: 6));

      try {
        await SupabaseConfig.client.rpc('reconcile_my_stock_alerts').timeout(const Duration(seconds: 6));
      } catch (e) {
        debugPrint('reconcile_my_stock_alerts RPC failed after settings sync (non-fatal): $e');
      }
    } catch (e) {
      debugPrint('Failed to sync commodity settings to Supabase (offline ok): $e');
    }
  }

  /// Production-safe (transaction-safe) stock receipt against the existing system catalog.
  /// This calls a Supabase RPC so quantity increments are never lost.
  Future<int> receiveStockForCurrentFieldProvider({
    required String commodityId,
    required int quantityReceived,
    required DateTime expiryDate,
    required String batchNumber,
    String? unitOverride,
  }) async {
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) throw Exception('Not authenticated');

    final normalizedExpiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    final unit = UnitOfExpression.normalize(unitOverride);
    final res = await SupabaseConfig.client.rpc(
      'receive_fieldprovider_inventory_stock',
      params: {
        'product_id': commodityId,
        'quantity_received': quantityReceived,
        'expiry_date': _formatDateOnly(normalizedExpiry),
        'batch_number': batchNumber,
        'unit_override': unit,
      },
    );

    if (res is! Map) throw Exception('Unexpected RPC response');
    final movementRaw = res['movement'];
    final newQty = int.tryParse(res['new_quantity']?.toString() ?? '') ?? 0;

    // Update local caches immediately for a responsive UI.
    await setBatchExpiryForUser(
      userId: authUser.id,
      commodityId: commodityId,
      batchNumber: batchNumber,
      expiryDate: normalizedExpiry,
      unitOverride: unitOverride,
    );

    try {
      if (movementRaw is Map) {
        final m = StockMovement.fromJson(_normalizeDates(movementRaw.cast<String, dynamic>())).copyWith(syncStatus: SyncStatus.synced);
        _replaceMovement(m);
        final prefs = await SharedPreferences.getInstance();
        await _saveMovements(prefs);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to apply RPC movement to local cache (will resync later): $e');
    }

    return newQty;
  }

  Future<void> setMinThresholdForUser({required String userId, required String commodityId, required int minThreshold}) async {
    final normalized = minThreshold < 0 ? 0 : minThreshold;
    _minThresholdsByUserCommodity[_thresholdKey(userId, commodityId)] = normalized;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await _saveMinThresholds(prefs);
    } catch (e) {
      debugPrint('Failed to save min threshold: $e');
    }

    // Best-effort remote persistence so backend low-stock notifications can be generated.
    try {
      if (SupabaseConfig.auth.currentUser != null) {
        await SupabaseService.upsert(
          'field_provider_commodity_settings',
          {
            'field_provider_id': userId,
            'commodity_id': commodityId,
            'minimum_quantity': normalized,
          },
          onConflict: 'field_provider_id,commodity_id',
        );

        try {
          await SupabaseConfig.client.rpc('reconcile_my_stock_alerts');
        } catch (e) {
          debugPrint('reconcile_my_stock_alerts RPC failed after threshold update (non-fatal): $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to sync min threshold to Supabase (offline ok): $e');
    }
  }

  static bool _isSchemaColumnError(Object e) {
    final msg = e.toString();
    return msg.contains('schema cache') || msg.contains('does not exist') || msg.contains("Could not find the '");
  }

  Map<String, dynamic> _movementToDbJsonLower(StockMovement m) => {
    'id': m.id,
    'commodityid': m.commodityId,
    'userid': m.userId,
    'type': m.type.name,
    'quantity': m.quantity,
    'reason': m.reason.name,
    'notes': m.notes,
    'batchnumber': m.batchNumber,
    'expirydate': m.expiryDate?.toIso8601String(),
    'syncstatus': m.syncStatus.name,
    'createdat': m.createdAt.toIso8601String(),
  };

  Future<void> startRealtime({required bool forAdmin, required String userId}) async {
    await stopRealtime();
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) return;

    // Commodities (global list)
    try {
      _commoditiesRealtimeSub = SupabaseConfig.client
          .from('commodities')
          .stream(primaryKey: ['id'])
          .order('name', ascending: true)
          .listen((rows) async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final next = rows
              .map((row) => Commodity.fromJson(_normalizeDates(row)))
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));

          // If the backend stream is empty (common on fresh projects), keep a stable baseline
          // catalog so FieldProviders never see a blank Inventory.
          if (next.isEmpty) {
            if (_commodities.isEmpty) await _createDefaultCatalog(prefs);
            return;
          }

          _commodities = next;
          await _saveCommodities(prefs);
          notifyListeners();
        } catch (e) {
          debugPrint('Commodities realtime apply failed: $e');
        }
      });
    } catch (e) {
      debugPrint('Failed to start commodities realtime: $e');
    }

    // Movements (scoped per user for providers; all for admins)
    try {
      Stream<List<Map<String, dynamic>>> buildStream(String orderCol) =>
          SupabaseConfig.client.from('stock_movements').stream(primaryKey: ['id']).order(orderCol, ascending: false);

      late final Stream<List<Map<String, dynamic>>> query;
      try {
        query = buildStream('createdAt');
      } catch (e) {
        // Some schemas use snake_case / lowercase.
        query = buildStream('createdat');
      }

      _movementsRealtimeSub = query.listen((rows) async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final filtered = forAdmin
              ? rows
              : rows.where((r) => (r['userId'] ?? r['userid'] ?? r['user_id'])?.toString() == userId).toList();
          _movements = filtered.map((row) => StockMovement.fromJson(_normalizeDates(row)).copyWith(syncStatus: SyncStatus.synced)).toList();
          await _saveMovements(prefs);
          notifyListeners();
        } catch (e) {
          debugPrint('Stock movements realtime apply failed: $e');
        }
      });
    } catch (e) {
      debugPrint('Failed to start stock movements realtime: $e');
    }
  }

  Future<void> stopRealtime() async {
    await _commoditiesRealtimeSub?.cancel();
    await _movementsRealtimeSub?.cancel();
    _commoditiesRealtimeSub = null;
    _movementsRealtimeSub = null;
  }

  Commodity? getCommodityById(String id) =>
      _commodities.where((c) => c.id == id).cast<Commodity?>().firstOrNull;

  Commodity? getCommodityByName(String name) => _commodities
      .where((c) => c.name.toLowerCase() == name.toLowerCase())
      .cast<Commodity?>()
      .firstOrNull;

  int getQuantityForUser({required String commodityId, required String userId}) {
    var qty = 0;
    for (final m in _movements) {
      if (m.userId != userId || m.commodityId != commodityId) continue;
      qty += m.type == MovementType.add ? m.quantity : -m.quantity;
    }
    if (qty < 0) qty = 0;
    return qty;
  }

  /// Facility inventory for a field provider is derived from movements for the logged-in user.
  /// A commodity is considered "assigned" if the user has at least one movement against it.
  List<Commodity> getFacilityCommodities(String userId) {
    final assignedIds = _movements.where((m) => m.userId == userId).map((m) => m.commodityId).toSet();
    return _commodities.where((c) => assignedIds.contains(c.id)).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Commodity withComputedQuantity({required Commodity commodity, required String userId}) => commodity.copyWith(
    currentQuantity: getQuantityForUser(commodityId: commodity.id, userId: userId),
    minThreshold: getMinThresholdForUser(userId: userId, commodity: commodity),
  );

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final commoditiesJson = prefs.getString('commodities');
      final movementsJson = prefs.getString('stockMovements');
      final thresholdsJson = prefs.getString('minThresholdsByUserCommodity');
      final batchJson = prefs.getString('batchNumberByUserCommodity');
      final expiryJson = prefs.getString('expiryDateByUserCommodity');
      final unitJson = prefs.getString('unitOverrideByUserCommodity');

      if (commoditiesJson != null) {
        final decoded = jsonDecode(commoditiesJson) as List;
        _commodities = decoded.map((e) {
          try {
            return Commodity.fromJson(e);
          } catch (err) {
            debugPrint('Skipping corrupted commodity: $err');
            return null;
          }
        }).whereType<Commodity>().toList();

        // Local safety filter: this catalog item is deprecated and should not be selectable.
        // We do NOT delete any historical movements; this only affects future selection.
        final before = _commodities.length;
        _commodities = _commodities.where((c) => c.name.trim().toLowerCase() != 'tb screening form').toList();
        if (_commodities.length != before) {
          await _saveCommodities(prefs);
        }

        if (_commodities.length != decoded.length) {
          await _saveCommodities(prefs);
        }

        // CRITICAL: if the cache exists but is empty (saved as []), bootstrap defaults.
        if (_commodities.isEmpty) {
          await _createDefaultCatalog(prefs);
        }
      } else {
        // Always have a non-empty baseline catalog so the Inventory UI never appears blank.
        // When online, Supabase remains the source-of-truth and will overwrite/extend this.
        await _createDefaultCatalog(prefs);
      }

      if (movementsJson != null) {
        final decoded = jsonDecode(movementsJson) as List;
        _movements = decoded.map((e) {
          try {
            return StockMovement.fromJson(e);
          } catch (err) {
            debugPrint('Skipping corrupted movement: $err');
            return null;
          }
        }).whereType<StockMovement>().toList();

        if (_movements.length != decoded.length) {
          await _saveMovements(prefs);
        }
      }

      if (thresholdsJson != null) {
        try {
          final decoded = jsonDecode(thresholdsJson);
          if (decoded is Map) {
            _minThresholdsByUserCommodity = decoded.map((k, v) {
              final key = k.toString();
              final parsed = int.tryParse(v.toString());
              final safe = (parsed ?? 0) < 0 ? 0 : (parsed ?? 0);
              return MapEntry(key, safe);
            });
          }
        } catch (e) {
          debugPrint('Failed to decode min thresholds cache, resetting: $e');
          _minThresholdsByUserCommodity = {};
          await _saveMinThresholds(prefs);
        }
      }

      if (batchJson != null) {
        try {
          final decoded = jsonDecode(batchJson);
          if (decoded is Map) {
            _batchNumberByUserCommodity = decoded.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
              ..removeWhere((k, v) => v.trim().isEmpty);
          }
        } catch (e) {
          debugPrint('Failed to decode batch number cache, resetting: $e');
          _batchNumberByUserCommodity = {};
          await _saveBatchNumbers(prefs);
        }
      }

      if (expiryJson != null) {
        try {
          final decoded = jsonDecode(expiryJson);
          if (decoded is Map) {
            _expiryDateByUserCommodity = decoded.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
              ..removeWhere((k, v) => v.trim().isEmpty);
          }
        } catch (e) {
          debugPrint('Failed to decode expiry date cache, resetting: $e');
          _expiryDateByUserCommodity = {};
          await _saveExpiryDates(prefs);
        }
      }

      if (unitJson != null) {
        try {
          final decoded = jsonDecode(unitJson);
          if (decoded is Map) {
            _unitOverrideByUserCommodity = decoded.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
              ..removeWhere((k, v) => v.trim().isEmpty);
          }
        } catch (e) {
          debugPrint('Failed to decode unit override cache, resetting: $e');
          _unitOverrideByUserCommodity = {};
          await _saveUnitOverrides(prefs);
        }
      }

      await _syncWithSupabase(prefs);
    } catch (e) {
      debugPrint('Failed to load inventory: $e');
      _commodities = [];
      _movements = [];
      _minThresholdsByUserCommodity = {};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _syncWithSupabase(SharedPreferences prefs) async {
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) return;

    // Push pending local movements first.
    final pendingMoves = _movements.where((m) => m.syncStatus == SyncStatus.pending || m.syncStatus == SyncStatus.failed).toList();
    if (pendingMoves.isNotEmpty) {
      var pushedAny = false;
      for (final m in pendingMoves) {
        try {
          try {
            await SupabaseService.upsert('stock_movements', _normalizeDates(m.toJson()), onConflict: 'id');
          } catch (e) {
            if (!_isSchemaColumnError(e)) rethrow;
            await SupabaseService.upsert('stock_movements', _movementToDbJsonLower(m), onConflict: 'id');
          }
          _replaceMovement(m.copyWith(syncStatus: SyncStatus.synced));
          pushedAny = true;
        } catch (e) {
          debugPrint('Failed to push pending stock movement ${m.id}: $e');
          _replaceMovement(m.copyWith(syncStatus: SyncStatus.failed));
        }
      }

      if (pushedAny) {
        try {
          await SupabaseConfig.client.rpc('reconcile_my_stock_alerts');
        } catch (e) {
          debugPrint('reconcile_my_stock_alerts RPC failed after movement push (non-fatal): $e');
        }
      }
    }

    // Pull commodities (global) + movements (for this user) from server.
    try {
      var remoteCommodities = await SupabaseService.select('commodities', orderBy: 'name', ascending: true);

      // Ensure the required allowlisted catalog exists in Supabase. If the table is empty
      // OR partially populated (missing our stable IDs), inserts are idempotent.
      try {
        await _seedDefaultCatalogToSupabase(remoteCommodities: remoteCommodities);
        remoteCommodities = await SupabaseService.select('commodities', orderBy: 'name', ascending: true);
      } catch (e) {
        debugPrint('Default commodity seed failed (continuing with local cache): $e');
      }

      // Soft-deactivated commodities are excluded from selection lists going forward.
      // Historical inventory movements remain viewable because they reference commodityId.
      remoteCommodities = remoteCommodities.where((r) {
        final v = r['is_active'] ?? r['isactive'] ?? r['isActive'];
        if (v == null) return true;
        return v == true;
      }).toList();

      final commodityById = {for (final c in _commodities) c.id: c};
      var commoditiesChanged = false;
      for (final row in remoteCommodities) {
        final normalized = _normalizeDates(row);
        final remote = Commodity.fromJson(normalized);
        final local = commodityById[remote.id];
        if (local == null || remote.updatedAt.isAfter(local.updatedAt)) {
          commodityById[remote.id] = remote;
          commoditiesChanged = true;
        }
      }
      if (commoditiesChanged) {
        _commodities = commodityById.values.toList()..sort((a, b) => a.name.compareTo(b.name));
        await _saveCommodities(prefs);
      }

      List<Map<String, dynamic>> remoteMoves;
      try {
        remoteMoves = await SupabaseService.select(
          'stock_movements',
          filters: {'userId': authUser.id},
          orderBy: 'createdAt',
          ascending: false,
        );
      } catch (e) {
        if (!_isSchemaColumnError(e)) rethrow;
        try {
          remoteMoves = await SupabaseService.select(
            'stock_movements',
            filters: {'userid': authUser.id},
            orderBy: 'createdat',
            ascending: false,
          );
        } catch (e2) {
          if (!_isSchemaColumnError(e2)) rethrow;
          remoteMoves = await SupabaseService.select(
            'stock_movements',
            filters: {'user_id': authUser.id},
            orderBy: 'created_at',
            ascending: false,
          );
        }
      }

      final moveById = {for (final m in _movements) m.id: m};
      var movesChanged = false;
      for (final row in remoteMoves) {
        final normalized = _normalizeDates(row);
        final remote = StockMovement.fromJson(normalized);
        if (!moveById.containsKey(remote.id)) {
          moveById[remote.id] = remote.copyWith(syncStatus: SyncStatus.synced);
          movesChanged = true;
        }
      }
      if (movesChanged) {
        _movements = moveById.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await _saveMovements(prefs);
      }

      if (commoditiesChanged || movesChanged) notifyListeners();

      // Pull per-provider minimum thresholds so settings follow the user across devices.
      try {
        final remoteSettings = await SupabaseService.select(
          'field_provider_commodity_settings',
          filters: {'field_provider_id': authUser.id},
        );
        var changed = false;
        for (final row in remoteSettings) {
          final commodityId = (row['commodity_id'] ?? row['commodityId'])?.toString();
          final minQ = int.tryParse((row['minimum_quantity'] ?? row['minimumQuantity'])?.toString() ?? '');
          if (commodityId == null || minQ == null) continue;
          final key = _thresholdKey(authUser.id, commodityId);
          if (_minThresholdsByUserCommodity[key] != minQ) {
            _minThresholdsByUserCommodity[key] = minQ;
            changed = true;
          }

          // Optional batch + expiry settings (safe for existing rows).
          final batch = _normalizeBatch((row['batch_number'] ?? row['batchNumber'])?.toString());
          final expiry = _tryParseDateOnly(row['expiry_date'] ?? row['expiryDate']);
          final unit = (row['unit_override'] ?? row['unitOverride'])?.toString().trim();
          final sk = _settingsKey(authUser.id, commodityId);

          final prevBatch = _batchNumberByUserCommodity[sk];
          if (batch != prevBatch) {
            if (batch == null) {
              _batchNumberByUserCommodity.remove(sk);
            } else {
              _batchNumberByUserCommodity[sk] = batch;
            }
            changed = true;
          }

          final prevExpiryRaw = _expiryDateByUserCommodity[sk];
          final nextExpiryRaw = _formatDateOnly(expiry);
          if (nextExpiryRaw != prevExpiryRaw) {
            if (nextExpiryRaw == null) {
              _expiryDateByUserCommodity.remove(sk);
            } else {
              _expiryDateByUserCommodity[sk] = nextExpiryRaw;
            }
            changed = true;
          }

          final prevUnit = _unitOverrideByUserCommodity[sk];
          final nextUnit = (unit == null || unit.isEmpty) ? null : unit;
          if (nextUnit != prevUnit) {
            if (nextUnit == null) {
              _unitOverrideByUserCommodity.remove(sk);
            } else {
              _unitOverrideByUserCommodity[sk] = nextUnit;
            }
            changed = true;
          }
        }
        if (changed) {
          await _saveMinThresholds(prefs);
          await _saveBatchNumbers(prefs);
          await _saveExpiryDates(prefs);
          await _saveUnitOverrides(prefs);
          notifyListeners();
        }
      } catch (e) {
        debugPrint('Inventory settings Supabase pull failed (offline ok): $e');
      }
    } catch (e) {
      debugPrint('Inventory Supabase pull failed (offline ok): $e');
    }
  }

  Future<void> _createDefaultCatalog(SharedPreferences prefs) async {
    final now = DateTime.now();
    _commodities = [
      Commodity(
        id: _stableCommodityId('prep'),
        name: 'PreP',
        program: HealthProgram.hiv,
        unit: 'units',
        currentQuantity: 0,
        minThreshold: 0,
        createdAt: now,
        updatedAt: now,
      ),
      Commodity(
        id: _stableCommodityId('mrdt'),
        name: 'mRDT',
        program: HealthProgram.malaria,
        unit: 'units',
        currentQuantity: 0,
        minThreshold: 0,
        createdAt: now,
        updatedAt: now,
      ),
      Commodity(
        id: _stableCommodityId('topmal'),
        name: 'TopMal',
        program: HealthProgram.malaria,
        unit: 'packs',
        currentQuantity: 0,
        minThreshold: 0,
        createdAt: now,
        updatedAt: now,
      ),
    ];
    await _saveCommodities(prefs);
    notifyListeners();
  }

  static String _stableCommodityId(String key) => _uuid.v5(Uuid.NAMESPACE_URL, 'mediflow:commodity:$key');

  Future<void> _seedDefaultCatalogToSupabase({List<Map<String, dynamic>>? remoteCommodities}) async {
    // NOTE: This MUST be schema-tolerant.
    // Different environments may use camelCase or lowercase columns.
    // Some schemas also require non-null qty/threshold + timestamps.
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final defaults = [
      {
        'id': _stableCommodityId('prep'),
        'name': 'PreP',
        'program': 'hiv',
        'unit': 'units',
        // Lowercase schema requirements (non-null)
        'currentquantity': 0,
        'minthreshold': 0,
        'createdat': nowIso,
        'updatedat': nowIso,
        'is_active': true,
        'isactive': true,
      },
      {
        'id': _stableCommodityId('mrdt'),
        'name': 'mRDT',
        'program': 'malaria',
        'unit': 'units',
        'currentquantity': 0,
        'minthreshold': 0,
        'createdat': nowIso,
        'updatedat': nowIso,
        'is_active': true,
        'isactive': true,
      },
      {
        'id': _stableCommodityId('topmal'),
        'name': 'TopMal',
        'program': 'malaria',
        'unit': 'packs',
        'currentquantity': 0,
        'minthreshold': 0,
        'createdat': nowIso,
        'updatedat': nowIso,
        'is_active': true,
        'isactive': true,
      },
    ];

    final existingIds = <String>{};
    if (remoteCommodities != null) {
      for (final r in remoteCommodities) {
        final id = r['id']?.toString();
        if (id != null && id.isNotEmpty) existingIds.add(id);
      }
    }

    Map<String, dynamic> _toCamelMinimal(Map<String, dynamic> lower) {
      final camel = <String, dynamic>{
        'id': lower['id'],
        'name': lower['name'],
        'program': lower['program'],
        'unit': lower['unit'],
        'currentQuantity': lower['currentquantity'],
        'minThreshold': lower['minthreshold'],
        'createdAt': lower['createdat'],
        'updatedAt': lower['updatedat'],
      };
      return camel;
    }

    Map<String, dynamic> _toSnakeMinimal(Map<String, dynamic> lower) => {
      'id': lower['id'],
      'name': lower['name'],
      'program': lower['program'],
      'unit': lower['unit'],
      'current_quantity': lower['currentquantity'],
      'min_threshold': lower['minthreshold'],
      'created_at': lower['createdat'],
      'updated_at': lower['updatedat'],
    };

    for (final lower in defaults) {
      final id = lower['id']?.toString();
      if (id != null && existingIds.contains(id)) continue;

      try {
        final candidates = <Map<String, dynamic>>[
          // Try the most common schemas first.
          lower,
          _toSnakeMinimal(lower),
          _toCamelMinimal(lower),
        ];

        Object? last;
        var ok = false;
        for (final payload in candidates) {
          try {
            await SupabaseService.upsert('commodities', payload, onConflict: 'id');
            ok = true;
            break;
          } catch (e) {
            last = e;
            if (!_isSchemaColumnError(e)) rethrow;
          }
        }

        if (!ok) throw last ?? 'Unknown commodities upsert failure';
      } catch (e) {
        debugPrint('Commodity seed upsert failed for ${lower['name']}: $e');
      }
    }
  }

  /// Admin-only: pull all movements (no userId filter). Requires permissive RLS for admin roles.
  Future<void> syncAllForAdmin() async {
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final remoteCommodities = await SupabaseService.select('commodities', orderBy: 'name', ascending: true);
      _commodities = remoteCommodities.map((row) {
        final normalized = _normalizeDates(row);
        return Commodity.fromJson(normalized);
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      final remoteMoves = await SupabaseService.select('stock_movements', orderBy: 'createdAt', ascending: false);
      _movements = remoteMoves.map((row) {
        final normalized = _normalizeDates(row);
        return StockMovement.fromJson(normalized).copyWith(syncStatus: SyncStatus.synced);
      }).toList();

      await _saveCommodities(prefs);
      await _saveMovements(prefs);
      notifyListeners();
    } catch (e) {
      debugPrint('Admin inventory sync failed: $e');
      rethrow;
    }
  }

  void _replaceMovement(StockMovement movement) {
    final idx = _movements.indexWhere((m) => m.id == movement.id);
    if (idx == -1) {
      _movements.insert(0, movement);
    } else {
      _movements[idx] = movement;
    }
  }

  Map<String, dynamic> _normalizeDates(Map<String, dynamic> json) {
    final out = Map<String, dynamic>.from(json);
    for (final key in ['createdAt', 'updatedAt']) {
      final v = out[key];
      if (v is DateTime) out[key] = v.toIso8601String();
    }
    return out;
  }

  // Sample data helper removed in favor of a stable default catalog that works for
  // both logged-in and logged-out states.

  Future<void> _saveCommodities(SharedPreferences prefs) async {
    await prefs.setString('commodities', jsonEncode(_commodities.map((c) => c.toJson()).toList()));
  }

  Future<void> _saveMovements(SharedPreferences prefs) async {
    await prefs.setString('stockMovements', jsonEncode(_movements.map((m) => m.toJson()).toList()));
  }

  Future<void> _saveMinThresholds(SharedPreferences prefs) async {
    await prefs.setString('minThresholdsByUserCommodity', jsonEncode(_minThresholdsByUserCommodity));
  }

  Future<void> _saveBatchNumbers(SharedPreferences prefs) async {
    await prefs.setString('batchNumberByUserCommodity', jsonEncode(_batchNumberByUserCommodity));
  }

  Future<void> _saveExpiryDates(SharedPreferences prefs) async {
    await prefs.setString('expiryDateByUserCommodity', jsonEncode(_expiryDateByUserCommodity));
  }

  Future<void> _saveUnitOverrides(SharedPreferences prefs) async {
    await prefs.setString('unitOverrideByUserCommodity', jsonEncode(_unitOverrideByUserCommodity));
  }

  Future<void> adjustStock({
    required String commodityId,
    required MovementType type,
    required int quantity,
    required MovementReason reason,
    required String userId,
    String? notes,
    String? batchNumber,
    DateTime? expiryDate,
  }) async {
    // Prefer the centralized backend RPC when authenticated so quantities, alerts,
    // notifications and audit logs stay consistent.
    if (SupabaseConfig.auth.currentUser != null) {
      try {
        final action = type == MovementType.add ? 'increase' : 'decrease';
        final res = await SupabaseConfig.client.rpc(
          'manual_stock_adjustment',
          params: {
            'p_commodity_id': commodityId,
            'p_action': action,
            'p_quantity': quantity,
            'p_reason': reason.name,
            'p_notes': notes,
            'p_batch_number': batchNumber,
            'p_expiry_date': expiryDate == null ? null : _formatDateOnly(DateTime(expiryDate.year, expiryDate.month, expiryDate.day)),
          },
        );

        if (res is Map) {
          final movementRaw = res['movement'];
          if (movementRaw is Map) {
            final m = StockMovement.fromJson(_normalizeDates(movementRaw.cast<String, dynamic>())).copyWith(syncStatus: SyncStatus.synced);
            _replaceMovement(m);
            try {
              final prefs = await SharedPreferences.getInstance();
              await _saveMovements(prefs);
            } catch (e) {
              debugPrint('Failed to persist movement cache after RPC: $e');
            }
            notifyListeners();
          }
        }

        return;
      } catch (e) {
        debugPrint('manual_stock_adjustment RPC failed; falling back to local/offline adjustment: $e');
      }
    }

    // IMPORTANT:
    // In this app, `commodities` is the master product list (global), while facility/user stock
    // is derived from `stock_movements` (scoped by userId). So we do not mutate commodity
    // quantities here.
    final movement = StockMovement(
      id: _uuid.v4(),
      commodityId: commodityId,
      userId: userId,
      type: type,
      quantity: quantity,
      reason: reason,
      notes: notes,
      batchNumber: batchNumber,
      expiryDate: expiryDate,
      createdAt: DateTime.now(),
    );
    _movements.insert(0, movement);

    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await _saveCommodities(prefs);
      await _saveMovements(prefs);

      // Best-effort remote writes.
      if (SupabaseConfig.auth.currentUser != null) {
        try {
          try {
            await SupabaseService.upsert('stock_movements', _normalizeDates(movement.toJson()), onConflict: 'id');
          } catch (e) {
            if (!_isSchemaColumnError(e)) rethrow;
            await SupabaseService.upsert('stock_movements', _movementToDbJsonLower(movement), onConflict: 'id');
          }

          // Safety net: ensure stock alerts are evaluated even if DB triggers
          // are missing/disabled on a given environment.
          try {
            await SupabaseConfig.client.rpc('reconcile_my_stock_alerts');
            debugPrint('reconcile_my_stock_alerts OK after stock movement (commodityId=$commodityId, userId=$userId)');
          } catch (e) {
            debugPrint('reconcile_my_stock_alerts RPC failed (non-fatal): $e');
          }

          _replaceMovement(movement.copyWith(syncStatus: SyncStatus.synced));
          await _saveMovements(prefs);
        } catch (e) {
          debugPrint('Supabase insert stock movement failed (kept local): $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to save inventory adjustment: $e');
    }
  }

  int getStockAlertCountForUser(String userId) => getStockAlertsForUser(userId).length;

  List<Commodity> getStockAlertsForUser(String userId) {
    final facility = getFacilityCommodities(userId);
    return facility.where((c) {
      final qty = getQuantityForUser(commodityId: c.id, userId: userId);
      final minT = getMinThresholdForUser(userId: userId, commodity: c);
      return qty == 0 || qty <= minT;
    }).toList();
  }

  int getStockAlertCountAll() => getStockAlertsAll().length;

  List<Commodity> getStockAlertsAll() => _commodities.where((c) => c.currentQuantity < c.minThreshold).toList();

  List<Commodity> getCommoditiesByProgram(HealthProgram program) =>
      _commodities.where((c) => c.program == program).toList();

  int getMovementsTodayCountAll() {
    final today = DateTime.now();
    return _movements.where((m) => m.createdAt.year == today.year && m.createdAt.month == today.month && m.createdAt.day == today.day).length;
  }

  List<StockMovement> getMovementsByCommodity(String commodityId) =>
      _movements.where((m) => m.commodityId == commodityId).toList();

  /// Batch-level breakdown derived from stock movements for one provider + commodity.
  ///
  /// Missing values are represented as null.
  List<InventoryBatchBreakdownRow> getBatchBreakdownForUser({required String userId, required String commodityId}) {
    final relevant = _movements.where((m) => m.userId == userId && m.commodityId == commodityId).toList();
    final map = <String, InventoryBatchBreakdownRow>{};

    String keyOf(String? batch, DateTime? expiry) {
      final b = (batch ?? '').trim();
      final e = expiry == null ? '' : _formatDateOnly(DateTime(expiry.year, expiry.month, expiry.day))!;
      return '${b.isEmpty ? '∅' : b}|${e.isEmpty ? '∅' : e}';
    }

    for (final m in relevant) {
      final batch = (m.batchNumber ?? '').trim().isEmpty ? null : m.batchNumber!.trim();
      final expiry = m.expiryDate == null ? null : DateTime(m.expiryDate!.year, m.expiryDate!.month, m.expiryDate!.day);
      final k = keyOf(batch, expiry);
      final prev = map[k];
      final delta = m.type == MovementType.add ? m.quantity : -m.quantity;
      final nextQty = (prev?.quantity ?? 0) + delta;

      map[k] = InventoryBatchBreakdownRow(
        batchNumber: batch,
        expiryDate: expiry,
        quantity: nextQty < 0 ? 0 : nextQty,
        lastReceivedAt: (() {
          if (m.type != MovementType.add) return prev?.lastReceivedAt;
          final existing = prev?.lastReceivedAt;
          return (existing == null || m.createdAt.isAfter(existing)) ? m.createdAt : existing;
        })(),
        movementIdsWithMissingData: {
          ...?prev?.movementIdsWithMissingData,
          if (m.type == MovementType.add && (((m.batchNumber ?? '').trim().isEmpty) || m.expiryDate == null)) m.id,
        }.toList(),
      );
    }

    final rows = map.values.where((r) => r.quantity > 0).toList();
    rows.sort((a, b) {
      final ae = a.expiryDate;
      final be = b.expiryDate;
      if (ae == null && be == null) return (a.batchNumber ?? '').compareTo(b.batchNumber ?? '');
      if (ae == null) return 1;
      if (be == null) return -1;
      return ae.compareTo(be);
    });
    return rows;
  }

  /// Expiry-only breakdown (sum of all batches for each expiry date).
  List<InventoryExpiryBreakdownRow> getExpiryBreakdownForUser({required String userId, required String commodityId}) {
    final batches = getBatchBreakdownForUser(userId: userId, commodityId: commodityId);
    final map = <String, InventoryExpiryBreakdownRow>{};
    for (final b in batches) {
      final expiry = b.expiryDate;
      final k = expiry == null ? '∅' : _formatDateOnly(expiry)!;
      final prev = map[k];
      map[k] = InventoryExpiryBreakdownRow(expiryDate: expiry, quantity: (prev?.quantity ?? 0) + b.quantity);
    }
    final rows = map.values.toList();
    rows.sort((a, b) {
      if (a.expiryDate == null && b.expiryDate == null) return 0;
      if (a.expiryDate == null) return 1;
      if (b.expiryDate == null) return -1;
      return a.expiryDate!.compareTo(b.expiryDate!);
    });
    return rows;
  }

  /// Production-safe: updates missing batch/expiry on one of the caller's own movements.
  Future<void> backfillMissingBatchExpiryOnMovement({
    required String movementId,
    String? batchNumber,
    DateTime? expiryDate,
  }) async {
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) throw Exception('Not authenticated');

    final batch = _normalizeBatch(batchNumber);
    final expiry = expiryDate == null ? null : DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    if (batch == null && expiry == null) throw Exception('Provide batch number and/or expiry date');

    try {
      final res = await SupabaseConfig.client.rpc(
        'update_my_stock_movement_batch_expiry',
        params: {
          'p_movement_id': movementId,
          'p_batch_number': batch,
          'p_expiry_date': expiry == null ? null : _formatDateOnly(expiry),
        },
      );

      if (res is Map) {
        final raw = res['movement'];
        if (raw is Map) {
          final updated = StockMovement.fromJson(_normalizeDates(raw.cast<String, dynamic>())).copyWith(syncStatus: SyncStatus.synced);
          _replaceMovement(updated);
          try {
            final prefs = await SharedPreferences.getInstance();
            await _saveMovements(prefs);
          } catch (e) {
            debugPrint('Failed to persist movement cache after backfill: $e');
          }
          notifyListeners();
        }
      }

      // Pull to ensure any other devices/rows stay consistent.
      await _syncWithSupabase(await SharedPreferences.getInstance());
    } catch (e) {
      debugPrint('update_my_stock_movement_batch_expiry RPC failed: $e');
      rethrow;
    }
  }

  Future<void> addCommodityToFacility({required String commodityId, required String userId}) async {
    // If the commodity is already assigned (has a movement), do nothing.
    if (_movements.any((m) => m.userId == userId && m.commodityId == commodityId)) return;
    await adjustStock(
      commodityId: commodityId,
      type: MovementType.add,
      quantity: 0,
      reason: MovementReason.countCorrection,
      userId: userId,
      notes: 'Added to facility inventory list',
    );
  }

  Future<void> requestNewProduct({
    required String userId,
    required String requestedName,
    String? unit,
    HealthProgram? program,
    String? notes,
    String? facilityName,
  }) async {
    // Best-effort: this requires a `product_requests` table (see supabase_tables.sql).
    final payload = {
      'requestedBy': userId,
      'facilityName': facilityName,
      'requestedName': requestedName.trim(),
      'unit': unit?.trim(),
      'program': program?.name,
      'notes': notes?.trim(),
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    };

    try {
      await SupabaseService.insert('product_requests', payload);
    } catch (e) {
      debugPrint('Failed to submit new product request (offline ok): $e');
      rethrow;
    }
  }

  Future<void> addToStockFromDelivery({
    required String commodityId,
    required String commodityNameFallback,
    required int quantity,
    required String userId,
  }) async {
    final byId = getCommodityById(commodityId);
    final commodity = byId ?? getCommodityByName(commodityNameFallback);
    if (commodity == null) {
      debugPrint('Delivery line could not be matched to inventory commodity: $commodityId / $commodityNameFallback');
      return;
    }

    await adjustStock(
      commodityId: commodity.id,
      type: MovementType.add,
      quantity: quantity,
      reason: MovementReason.delivery,
      userId: userId,
      notes: 'Added via delivery confirmation',
    );
  }

  Future<void> markAllPendingAsSynced() async {
    if (_movements.isEmpty) return;
    _movements = _movements
        .map((m) => m.syncStatus == SyncStatus.synced
            ? m
            : StockMovement(
                id: m.id,
                commodityId: m.commodityId,
                userId: m.userId,
                type: m.type,
                quantity: m.quantity,
                reason: m.reason,
                notes: m.notes,
                batchNumber: m.batchNumber,
                expiryDate: m.expiryDate,
                syncStatus: SyncStatus.synced,
                createdAt: m.createdAt,
              ))
        .toList();
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await _saveMovements(prefs);
    } catch (e) {
      debugPrint('Failed to mark movements synced: $e');
    }
  }
}

class InventoryBatchBreakdownRow {
  final String? batchNumber;
  final DateTime? expiryDate;
  final int quantity;
  final DateTime? lastReceivedAt;

  /// Add-movement IDs that contributed to this batch group but have missing batch/expiry.
  /// Used to offer a safe “backfill” action without editing other providers.
  final List<String> movementIdsWithMissingData;

  InventoryBatchBreakdownRow({
    required this.batchNumber,
    required this.expiryDate,
    required this.quantity,
    required this.lastReceivedAt,
    required this.movementIdsWithMissingData,
  });
}

class InventoryExpiryBreakdownRow {
  final DateTime? expiryDate;
  final int quantity;
  InventoryExpiryBreakdownRow({required this.expiryDate, required this.quantity});
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
