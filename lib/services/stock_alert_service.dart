import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mediflow/models/stock_alert.dart';
import 'package:mediflow/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StockAlertService extends ChangeNotifier {
  List<StockAlert> _items = [];
  bool _isLoading = false;
  int _unreadActiveCount = 0;

  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSub;
  StreamSubscription<AuthState>? _authSub;

  List<StockAlert> get items => _items;
  bool get isLoading => _isLoading;
  int get unreadActiveCount => _unreadActiveCount;

  List<StockAlert> get unreadActive => _items.where((a) => a.readState == StockAlertReadState.unread && a.isActive).toList();
  List<StockAlert> get history => _items.where((a) => a.readState == StockAlertReadState.read || !a.isActive).toList();

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      _authSub?.cancel();
      _authSub = SupabaseConfig.auth.onAuthStateChange.listen((_) {
        unawaited(_handleAuthChanged());
      });
      await _handleAuthChanged();
    } catch (e) {
      debugPrint('StockAlertService init failed: $e');
      _items = [];
      _unreadActiveCount = 0;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _handleAuthChanged() async {
    await _realtimeSub?.cancel();
    _realtimeSub = null;

    final user = SupabaseConfig.auth.currentUser;
    if (user == null) {
      _items = [];
      _unreadActiveCount = 0;
      notifyListeners();
      return;
    }

    await refresh();

    try {
      _realtimeSub = SupabaseConfig.client
          .from('stock_alerts')
          .stream(primaryKey: ['id'])
          .eq('field_provider_id', user.id)
          .order('created_at', ascending: false)
          .listen((rows) {
        _items = rows.map(StockAlert.fromJson).toList();
        notifyListeners();
        unawaited(_refreshUnreadActiveCount());
      });
    } catch (e) {
      debugPrint('Failed to start stock_alerts realtime: $e');
    }
  }

  Future<void> refresh() async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return;

    try {
      final rows = await SupabaseService.select(
        'stock_alerts',
        filters: {'field_provider_id': user.id},
        orderBy: 'created_at',
        ascending: false,
        limit: 300,
      );
      _items = rows.map(StockAlert.fromJson).toList();
      await _refreshUnreadActiveCount();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to refresh stock alerts: $e');
    }
  }

  Future<void> _refreshUnreadActiveCount() async {
    try {
      final v = await SupabaseConfig.client.rpc('count_unread_active_stock_alerts');
      _unreadActiveCount = int.tryParse(v.toString()) ?? 0;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to fetch unread active stock alert count: $e');
      _unreadActiveCount = _items.where((a) => a.readState == StockAlertReadState.unread && a.isActive).length;
      notifyListeners();
    }
  }

  Future<void> markRead(String id) async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return;

    final idx = _items.indexWhere((a) => a.id == id);
    final wasUnreadActive = idx != -1 && _items[idx].readState == StockAlertReadState.unread && _items[idx].isActive;

    if (idx != -1) {
      _items[idx] = _items[idx].copyWith(readState: StockAlertReadState.read, readAt: DateTime.now());
      if (wasUnreadActive) _unreadActiveCount = (_unreadActiveCount - 1).clamp(0, 1 << 30);
      notifyListeners();
    }

    try {
      await SupabaseService.update(
        'stock_alerts',
        {'is_read': true, 'read_at': DateTime.now().toIso8601String()},
        filters: {'id': id, 'field_provider_id': user.id},
      );
    } catch (e) {
      debugPrint('Failed to mark stock alert read: $e');
    } finally {
      await refresh();
    }
  }

  Future<void> markAllRead() async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    _items = _items.map((a) => (a.readState == StockAlertReadState.unread && a.isActive) ? a.copyWith(readState: StockAlertReadState.read, readAt: now) : a).toList();
    _unreadActiveCount = 0;
    notifyListeners();

    try {
      await SupabaseService.update(
        'stock_alerts',
        {'is_read': true, 'read_at': now.toIso8601String()},
        filters: {'field_provider_id': user.id, 'is_read': false, 'resolved_at': null},
      );
    } catch (e) {
      debugPrint('Failed to mark all stock alerts read: $e');
    } finally {
      await refresh();
    }
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
