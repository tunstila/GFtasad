import 'package:mediflow/models/commodity.dart';

/// Restock/stock request lifecycle.
///
/// Notes:
/// - We keep backwards compatibility with older statuses persisted in Supabase
///   (requested/acknowledged/fulfilled/cancelled).
enum StockRequestStatus { pending, approved, rejected, in_transit, delivered, cancelled }

extension StockRequestStatusCompat on StockRequestStatus {
  static StockRequestStatus fromDb(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    return switch (v) {
      'pending' => StockRequestStatus.pending,
      'approved' => StockRequestStatus.approved,
      'rejected' => StockRequestStatus.rejected,
      'in_transit' || 'intransit' => StockRequestStatus.in_transit,
      'delivered' => StockRequestStatus.delivered,
      'cancelled' || 'canceled' => StockRequestStatus.cancelled,
      // Back-compat
      'requested' => StockRequestStatus.pending,
      'acknowledged' => StockRequestStatus.approved,
      'fulfilled' => StockRequestStatus.delivered,
      _ => StockRequestStatus.pending,
    };
  }

  String toDb() => switch (this) {
    StockRequestStatus.in_transit => 'in_transit',
    _ => name,
  };
}

class StockRequestItem {
  final String commodityId;
  final String commodityName;
  final String unit;
  final int quantity;
  final String program;

  StockRequestItem({required this.commodityId, required this.commodityName, required this.unit, required this.quantity, required this.program});

  Map<String, dynamic> toJson() => {
    'commodityId': commodityId,
    'commodityName': commodityName,
    'unit': unit,
    'quantity': quantity,
    'program': program,
  };

  factory StockRequestItem.fromJson(Map<String, dynamic> json) => StockRequestItem(
    commodityId: json['commodityId'],
    commodityName: json['commodityName'],
    unit: json['unit'],
    quantity: json['quantity'],
    program: json['program'],
  );

  static StockRequestItem fromCommodity(Commodity c, {required int quantity}) => StockRequestItem(
    commodityId: c.id,
    commodityName: c.name,
    unit: c.unit,
    quantity: quantity,
    program: c.program.name,
  );
}

class StockRequest {
  final String id;
  final String providerId;
  final String providerName;
  final String providerEmail;
  final String? providerFacilityName;
  final String? providerBusinessAddress;
  final String? providerState;
  final String? providerLga;
  final double? providerLatitude;
  final double? providerLongitude;

  final String supplierId;
  final String supplierName;
  final StockRequestStatus status;
  final List<StockRequestItem> items;

  final String? notes;

  final DateTime createdAt;
  final DateTime updatedAt;

  StockRequest({
    required this.id,
    required this.providerId,
    required this.providerName,
    required this.providerEmail,
    this.providerFacilityName,
    this.providerBusinessAddress,
    this.providerState,
    this.providerLga,
    this.providerLatitude,
    this.providerLongitude,
    required this.supplierId,
    required this.supplierName,
    this.status = StockRequestStatus.pending,
    required this.items,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'providerId': providerId,
    'providerName': providerName,
    'providerEmail': providerEmail,
    'providerFacilityName': providerFacilityName,
    'providerBusinessAddress': providerBusinessAddress,
    'providerState': providerState,
    'providerLga': providerLga,
    'providerLatitude': providerLatitude,
    'providerLongitude': providerLongitude,
    'supplierId': supplierId,
    'supplierName': supplierName,
    'status': status.toDb(),
    'items': items.map((e) => e.toJson()).toList(),
    'notes': notes,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory StockRequest.fromJson(Map<String, dynamic> json) => StockRequest(
    id: json['id'],
    providerId: json['providerId'],
    providerName: json['providerName'],
    providerEmail: json['providerEmail'],
    providerFacilityName: json['providerFacilityName'],
    providerBusinessAddress: json['providerBusinessAddress'],
    providerState: json['providerState'],
    providerLga: json['providerLga'],
    providerLatitude: (json['providerLatitude'] as num?)?.toDouble(),
    providerLongitude: (json['providerLongitude'] as num?)?.toDouble(),
    supplierId: json['supplierId'],
    supplierName: json['supplierName'],
    status: StockRequestStatusCompat.fromDb(json['status']?.toString()),
    items: ((json['items'] ?? const []) as List).whereType<Map>().map((e) => StockRequestItem.fromJson(Map<String, dynamic>.from(e))).toList(),
    notes: json['notes']?.toString(),
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: DateTime.parse(json['updatedAt']),
  );

  StockRequest copyWith({
    String? id,
    String? providerId,
    String? providerName,
    String? providerEmail,
    String? providerFacilityName,
    String? providerBusinessAddress,
    String? providerState,
    String? providerLga,
    double? providerLatitude,
    double? providerLongitude,
    String? supplierId,
    String? supplierName,
    StockRequestStatus? status,
    List<StockRequestItem>? items,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => StockRequest(
    id: id ?? this.id,
    providerId: providerId ?? this.providerId,
    providerName: providerName ?? this.providerName,
    providerEmail: providerEmail ?? this.providerEmail,
    providerFacilityName: providerFacilityName ?? this.providerFacilityName,
    providerBusinessAddress: providerBusinessAddress ?? this.providerBusinessAddress,
    providerState: providerState ?? this.providerState,
    providerLga: providerLga ?? this.providerLga,
    providerLatitude: providerLatitude ?? this.providerLatitude,
    providerLongitude: providerLongitude ?? this.providerLongitude,
    supplierId: supplierId ?? this.supplierId,
    supplierName: supplierName ?? this.supplierName,
    status: status ?? this.status,
    items: items ?? this.items,
    notes: notes ?? this.notes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
