import 'package:mediflow/models/test_record.dart';

enum DeliveryStatus { pending, accepted, disputed }

class DeliveryLineItem {
  final String commodityId;
  final String commodityName;
  final int quantityPushed;
  final int? quantityReceived;
  final String? discrepancyReason;

  DeliveryLineItem({
    required this.commodityId,
    required this.commodityName,
    required this.quantityPushed,
    this.quantityReceived,
    this.discrepancyReason,
  });

  Map<String, dynamic> toJson() => {
    'commodityId': commodityId,
    'commodityName': commodityName,
    'quantityPushed': quantityPushed,
    'quantityReceived': quantityReceived,
    'discrepancyReason': discrepancyReason,
  };

  factory DeliveryLineItem.fromJson(Map<String, dynamic> json) => DeliveryLineItem(
    commodityId: json['commodityId'],
    commodityName: json['commodityName'],
    quantityPushed: json['quantityPushed'],
    quantityReceived: json['quantityReceived'],
    discrepancyReason: json['discrepancyReason'],
  );

  DeliveryLineItem copyWith({
    String? commodityId,
    String? commodityName,
    int? quantityPushed,
    int? quantityReceived,
    String? discrepancyReason,
  }) => DeliveryLineItem(
    commodityId: commodityId ?? this.commodityId,
    commodityName: commodityName ?? this.commodityName,
    quantityPushed: quantityPushed ?? this.quantityPushed,
    quantityReceived: quantityReceived ?? this.quantityReceived,
    discrepancyReason: discrepancyReason ?? this.discrepancyReason,
  );
}

class Delivery {
  final String id;
  final String supplierId;
  final String supplierName;
  final String providerId;
  final DateTime deliveryDate;
  final String? reference;
  final List<DeliveryLineItem> items;
  final DeliveryStatus status;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  Delivery({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.providerId,
    required this.deliveryDate,
    this.reference,
    required this.items,
    this.status = DeliveryStatus.pending,
    this.syncStatus = SyncStatus.pending,
    required this.createdAt,
    required this.updatedAt,
  });

  int get totalUnits => items.fold(0, (sum, item) => sum + item.quantityPushed);

  Map<String, dynamic> toJson() => {
    'id': id,
    'supplierId': supplierId,
    'supplierName': supplierName,
    'providerId': providerId,
    'deliveryDate': deliveryDate.toIso8601String(),
    'reference': reference,
    'items': items.map((e) => e.toJson()).toList(),
    'status': status.name,
    'syncStatus': syncStatus.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Delivery.fromJson(Map<String, dynamic> json) => Delivery(
    id: json['id'],
    supplierId: json['supplierId'],
    supplierName: json['supplierName'],
    providerId: json['providerId'],
    deliveryDate: DateTime.parse(json['deliveryDate']),
    reference: json['reference'],
    items: (json['items'] as List).map((e) => DeliveryLineItem.fromJson(e)).toList(),
    status: DeliveryStatus.values.firstWhere((e) => e.name == json['status']),
    syncStatus: SyncStatus.values.firstWhere((e) => e.name == json['syncStatus']),
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: DateTime.parse(json['updatedAt']),
  );

  Delivery copyWith({
    String? id,
    String? supplierId,
    String? supplierName,
    String? providerId,
    DateTime? deliveryDate,
    String? reference,
    List<DeliveryLineItem>? items,
    DeliveryStatus? status,
    SyncStatus? syncStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Delivery(
    id: id ?? this.id,
    supplierId: supplierId ?? this.supplierId,
    supplierName: supplierName ?? this.supplierName,
    providerId: providerId ?? this.providerId,
    deliveryDate: deliveryDate ?? this.deliveryDate,
    reference: reference ?? this.reference,
    items: items ?? this.items,
    status: status ?? this.status,
    syncStatus: syncStatus ?? this.syncStatus,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
