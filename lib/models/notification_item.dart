enum NotificationType { lowStock, deliveryArrived, syncFailure, system }

enum NotificationReadState { unread, read }

class NotificationItem {
  final String id;
  final NotificationType type;
  final String title;
  final String description;
  final DateTime createdAt;
  final NotificationReadState readState;
  final DateTime? readAt;
  final Map<String, dynamic> metadata;

  NotificationItem({required this.id, required this.type, required this.title, required this.description, required this.createdAt, this.readState = NotificationReadState.unread, this.readAt, Map<String, dynamic>? metadata}) : metadata = metadata ?? const {};

  String? get commodityName => metadata['commodity_name']?.toString();

  int? _tryParseInt(dynamic v) => int.tryParse(v?.toString() ?? '');

  int? _parseIntFromDescription(String label) {
    // Handles: "Current 12", "Current: 12", "Min 5", "Minimum 5" etc.
    final pattern = r'(?:^|\b)' + RegExp.escape(label) + r'\s*[:]?\s*(\d+)(?:\b|$)';
    final r = RegExp(pattern, caseSensitive: false);
    final m = r.firstMatch(description);
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? '');
  }

  int? get currentQuantity => _tryParseInt(metadata['current_quantity']) ?? _parseIntFromDescription('Current');
  int? get minimumQuantity => _tryParseInt(metadata['minimum_quantity']) ?? _parseIntFromDescription('Min') ?? _parseIntFromDescription('Minimum');

  /// For low-stock alerts: 'at_minimum' | 'below_minimum'
  String? get lowStockState {
    final v = (metadata['low_stock_state'] ?? metadata['lowStockState'])?.toString().trim();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  /// For low-stock alerts: e.g. 'At minimum stock' | 'Below minimum stock'
  String? get reason {
    final v = metadata['reason']?.toString().trim();
    if (v != null && v.isNotEmpty) return v;

    final state = lowStockState;
    if (state == 'below_minimum') return 'Below minimum stock';
    if (state == 'at_minimum') return 'At minimum stock';

    // Legacy fallback: if the backend wrote a human message, just reuse it.
    return null;
  }

  String? get unitOfExpression {
    final v = metadata['unit_of_expression']?.toString().trim();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
    'readState': readState.name,
    'readAt': readAt?.toIso8601String(),
    'metadata': metadata,
  };

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final createdRaw = json['createdAt'] ?? json['created_at'];
    final readAtRaw = json['readAt'] ?? json['read_at'] ?? json['readAtRaw'];
    final isRead = json['is_read'] ?? json['isRead'];

    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    DateTime? parseNullableDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    final typeStr = (json['type'] ?? 'system').toString();
    final normalizedType = typeStr == 'low_stock' ? 'lowStock' : (typeStr == 'delivery_arrived' ? 'deliveryArrived' : (typeStr == 'sync_failure' ? 'syncFailure' : typeStr));
    final parsedType = NotificationType.values.firstWhere((e) => e.name == normalizedType, orElse: () => NotificationType.system);

    final meta = (json['metadata'] is Map) ? Map<String, dynamic>.from(json['metadata'] as Map) : <String, dynamic>{};

    // Backfill metadata from top-level DB columns for older / partially-migrated rows.
    void backfill(String key, dynamic value) {
      if ((meta[key] == null || (meta[key] is String && (meta[key] as String).trim().isEmpty)) && value != null) {
        meta[key] = value;
      }
    }

    backfill('low_stock_state', json['low_stock_state']);
    backfill('commodity_name', json['commodity_name']);
    backfill('current_quantity', json['current_quantity']);
    backfill('minimum_quantity', json['minimum_quantity']);
    backfill('unit_of_expression', json['unit_of_expression']);
    backfill('reason', json['reason']);

    final readState = (isRead == true || isRead?.toString() == 'true')
        ? NotificationReadState.read
        : NotificationReadState.values.firstWhere((e) => e.name == (json['readState'] ?? 'unread'), orElse: () => NotificationReadState.unread);

    return NotificationItem(
      id: json['id'].toString(),
      type: parsedType,
      title: (json['title'] ?? '').toString(),
      description: (json['message'] ?? json['description'] ?? '').toString(),
      createdAt: parseDate(createdRaw),
      readState: readState,
      readAt: parseNullableDate(readAtRaw),
      metadata: meta,
    );
  }

  NotificationItem copyWith({String? id, NotificationType? type, String? title, String? description, DateTime? createdAt, NotificationReadState? readState, DateTime? readAt, Map<String, dynamic>? metadata}) => NotificationItem(
    id: id ?? this.id,
    type: type ?? this.type,
    title: title ?? this.title,
    description: description ?? this.description,
    createdAt: createdAt ?? this.createdAt,
    readState: readState ?? this.readState,
    readAt: readAt ?? this.readAt,
    metadata: metadata ?? this.metadata,
  );
}
