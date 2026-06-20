enum StockAlertType { lowStock, outOfStock, nearExpiry }

enum StockAlertSeverity { warning, critical }

enum StockAlertReadState { unread, read }

class StockAlert {
  final String id;
  final String fieldProviderId;
  final String? commodityId;
  final String? commodityName;
  final String? batchNumber;
  final DateTime? expiryDate;
  final StockAlertType type;
  final StockAlertSeverity severity;
  final String title;
  final String message;
  final int? currentQuantity;
  final int? minimumThreshold;
  final DateTime createdAt;
  final StockAlertReadState readState;
  final DateTime? readAt;
  final DateTime? resolvedAt;
  final Map<String, dynamic> metadata;

  const StockAlert({
    required this.id,
    required this.fieldProviderId,
    required this.type,
    required this.severity,
    required this.title,
    required this.message,
    required this.createdAt,
    this.readState = StockAlertReadState.unread,
    this.readAt,
    this.resolvedAt,
    this.commodityId,
    this.commodityName,
    this.batchNumber,
    this.expiryDate,
    this.currentQuantity,
    this.minimumThreshold,
    this.metadata = const {},
  });

  bool get isActive => resolvedAt == null;

  String? get unitOfExpression {
    final v = metadata['unit_of_expression']?.toString().trim();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  String? get reason {
    final v = metadata['reason']?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
    return switch (type) {
      StockAlertType.outOfStock => 'Out of stock',
      StockAlertType.lowStock => 'Low stock',
      StockAlertType.nearExpiry => 'Near expiry',
    };
  }

  StockAlert copyWith({StockAlertReadState? readState, DateTime? readAt, DateTime? resolvedAt}) => StockAlert(
    id: id,
    fieldProviderId: fieldProviderId,
    commodityId: commodityId,
    commodityName: commodityName,
    batchNumber: batchNumber,
    expiryDate: expiryDate,
    type: type,
    severity: severity,
    title: title,
    message: message,
    currentQuantity: currentQuantity,
    minimumThreshold: minimumThreshold,
    createdAt: createdAt,
    readState: readState ?? this.readState,
    readAt: readAt ?? this.readAt,
    resolvedAt: resolvedAt ?? this.resolvedAt,
    metadata: metadata,
  );

  static StockAlertType _parseType(String raw) => switch (raw) {
    'low_stock' => StockAlertType.lowStock,
    'out_of_stock' => StockAlertType.outOfStock,
    'near_expiry' => StockAlertType.nearExpiry,
    _ => StockAlertType.lowStock,
  };

  static StockAlertSeverity _parseSeverity(String raw) => switch (raw) {
    'critical' => StockAlertSeverity.critical,
    _ => StockAlertSeverity.warning,
  };

  static DateTime _parseDateTime(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString()) ?? DateTime.now();
  }

  static DateTime? _parseNullableDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  static DateTime? _parseNullableDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    final parsed = DateTime.tryParse(v.toString());
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  factory StockAlert.fromJson(Map<String, dynamic> json) {
    final meta = (json['metadata'] is Map) ? Map<String, dynamic>.from(json['metadata'] as Map) : <String, dynamic>{};
    final typeRaw = (json['alert_type'] ?? '').toString();
    final severityRaw = (json['severity'] ?? '').toString();

    return StockAlert(
      id: json['id'].toString(),
      fieldProviderId: (json['field_provider_id'] ?? '').toString(),
      commodityId: json['commodity_id']?.toString(),
      commodityName: (meta['commodity_name'] ?? json['commodity_name'])?.toString(),
      batchNumber: (json['batch_number'] ?? meta['batch_number'])?.toString(),
      expiryDate: _parseNullableDate(json['expiry_date'] ?? meta['expiry_date']),
      type: _parseType(typeRaw),
      severity: _parseSeverity(severityRaw),
      title: (json['title'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      currentQuantity: int.tryParse((json['current_quantity'] ?? meta['current_quantity'])?.toString() ?? ''),
      minimumThreshold: int.tryParse((json['minimum_threshold'] ?? meta['minimum_threshold'])?.toString() ?? ''),
      createdAt: _parseDateTime(json['created_at']),
      readState: (json['is_read'] == true || json['is_read']?.toString() == 'true') ? StockAlertReadState.read : StockAlertReadState.unread,
      readAt: _parseNullableDateTime(json['read_at']),
      resolvedAt: _parseNullableDateTime(json['resolved_at']),
      metadata: meta,
    );
  }
}
