import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mediflow/models/notification_item.dart';
import 'package:mediflow/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService extends ChangeNotifier {
  List<NotificationItem> _items = [];
  bool _isLoading = false;
  int _unreadCount = 0;
  int _unreadLowStockCount = 0;

  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSub;
  StreamSubscription<AuthState>? _authSub;

  List<NotificationItem> get items => _items;
  bool get isLoading => _isLoading;

  /// All unread notifications (all types).
  int get unreadCount => _unreadCount;

  /// Unread low-stock alerts only (source-of-truth for the Stock Alerts tile).
  int get unreadLowStockCount => _unreadLowStockCount;

  List<NotificationItem> get unreadItems => _items.where((n) => n.readState == NotificationReadState.unread).toList();
  List<NotificationItem> get readItems => _items.where((n) => n.readState == NotificationReadState.read).toList();

  List<NotificationItem> get unreadLowStockItems => _items.where((n) => n.type == NotificationType.lowStock && n.readState == NotificationReadState.unread).toList();
  List<NotificationItem> get readLowStockItems => _items.where((n) => n.type == NotificationType.lowStock && n.readState == NotificationReadState.read).toList();

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      _authSub?.cancel();
      _authSub = SupabaseConfig.auth.onAuthStateChange.listen((evt) {
        // Refresh on sign-in/out so the Home tile stays correct.
        unawaited(_handleAuthChanged());
      });

      await _handleAuthChanged();
    } catch (e) {
      debugPrint('NotificationService init failed: $e');
      _items = [];
      _unreadCount = 0;
      _unreadLowStockCount = 0;
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
      _unreadCount = 0;
      _unreadLowStockCount = 0;
      notifyListeners();
      return;
    }

    await refresh();

    // Realtime: keep the list in sync; unread counts are still fetched via RPC
    // after any change to guarantee backend truth.
    try {
      _realtimeSub = SupabaseConfig.client
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('field_provider_id', user.id)
          .order('created_at', ascending: false)
          .listen((rows) {
        _items = rows.map((r) => NotificationItem.fromJson(r)).toList();
        notifyListeners();
        unawaited(_refreshUnreadCounts());
      });
    } catch (e) {
      debugPrint('Failed to start notifications realtime: $e');
    }
  }

  Future<void> refresh() async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return;

    try {
      final rows = await SupabaseService.select(
        'notifications',
        filters: {'field_provider_id': user.id},
        orderBy: 'created_at',
        ascending: false,
        limit: 200,
      );
      _items = rows.map((r) => NotificationItem.fromJson(r)).toList();
      await _refreshUnreadCounts();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to refresh notifications: $e');
    }
  }

  Future<void> _refreshUnreadCounts() async {
    await Future.wait([
      _refreshUnreadCountAll(),
      _refreshUnreadCountLowStock(),
    ]);
  }

  Future<void> _refreshUnreadCountAll() async {
    try {
      final v = await SupabaseConfig.client.rpc('count_unread_notifications');
      final parsed = int.tryParse(v.toString());
      _unreadCount = parsed ?? 0;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to fetch unread notification count: $e');
      _unreadCount = _items.where((n) => n.readState == NotificationReadState.unread).length;
      notifyListeners();
    }
  }

  Future<void> _refreshUnreadCountLowStock() async {
    try {
      final v = await SupabaseConfig.client.rpc('count_unread_low_stock_alerts');
      final parsed = int.tryParse(v.toString());
      _unreadLowStockCount = parsed ?? 0;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to fetch unread low-stock count: $e');
      _unreadLowStockCount = _items.where((n) => n.type == NotificationType.lowStock && n.readState == NotificationReadState.unread).length;
      notifyListeners();
    }
  }

  Future<void> markAllLowStockRead() async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return;

    // Optimistic UI: immediately reduce low-stock count.
    _items = _items
        .map((n) => n.type == NotificationType.lowStock ? n.copyWith(readState: NotificationReadState.read, readAt: DateTime.now()) : n)
        .toList();
    _unreadLowStockCount = 0;
    notifyListeners();

    try {
      await SupabaseService.update(
        'notifications',
        {'is_read': true, 'read_at': DateTime.now().toIso8601String()},
        filters: {'field_provider_id': user.id, 'type': 'low_stock', 'is_read': false},
      );
    } catch (e) {
      debugPrint('Failed to mark all low-stock alerts read: $e');
    } finally {
      await refresh();
    }
  }

  Future<void> markAllRead() async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final unreadBefore = _items.where((n) => n.readState == NotificationReadState.unread).length;

    _items = _items.map((n) => n.readState == NotificationReadState.unread ? n.copyWith(readState: NotificationReadState.read, readAt: now) : n).toList();
    _unreadCount = 0;
    _unreadLowStockCount = _items.where((n) => n.type == NotificationType.lowStock && n.readState == NotificationReadState.unread).length;
    notifyListeners();

    if (unreadBefore == 0) return;

    try {
      await SupabaseService.update(
        'notifications',
        {'is_read': true, 'read_at': now.toIso8601String()},
        filters: {'field_provider_id': user.id, 'is_read': false},
      );
    } catch (e) {
      debugPrint('Failed to mark all notifications read: $e');
    } finally {
      await refresh();
    }
  }

  Future<void> markRead(String id) async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return;

    final idx = _items.indexWhere((n) => n.id == id);
    final isUnread = idx != -1 && _items[idx].readState == NotificationReadState.unread;
    final isLowStock = idx != -1 && _items[idx].type == NotificationType.lowStock;

    if (isUnread) {
      _items[idx] = _items[idx].copyWith(readState: NotificationReadState.read, readAt: DateTime.now());
      _unreadCount = (_unreadCount - 1).clamp(0, 1 << 30);
      if (isLowStock) _unreadLowStockCount = (_unreadLowStockCount - 1).clamp(0, 1 << 30);
      notifyListeners();
    }

    try {
      await SupabaseService.update(
        'notifications',
        {'is_read': true, 'read_at': DateTime.now().toIso8601String()},
        filters: {'id': id, 'field_provider_id': user.id},
      );
    } catch (e) {
      debugPrint('Failed to mark notification read: $e');
    } finally {
      // Full refresh keeps list + unread counts correct even if realtime drops events.
      await refresh();
    }
  }

  String _dbType(NotificationType t) => switch (t) {
    NotificationType.lowStock => 'low_stock',
    NotificationType.deliveryArrived => 'delivery_arrived',
    NotificationType.syncFailure => 'sync_failure',
    NotificationType.system => 'system',
  };

  /// Backwards-compatible helper used by existing UI flows.
  /// Low-stock notifications MUST come from the backend trigger, so this blocks lowStock inserts.
  Future<void> addSystem({required String title, required String description, NotificationType type = NotificationType.system}) async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return;
    if (type == NotificationType.lowStock) return;

    try {
      await SupabaseService.insert('notifications', {
        'field_provider_id': user.id,
        'title': title,
        'message': description,
        'type': _dbType(type),
        'is_read': false,
        'metadata': {},
      });
    } catch (e) {
      debugPrint('Failed to create notification: $e');
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
