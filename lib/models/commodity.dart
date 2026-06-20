import 'package:mediflow/models/test_record.dart';

enum StockStatus { ok, low, stockOut }

/// Allowed standardized units for displaying quantities.
/// Stored as text in the database (`unit_of_expression`) with strict validation.
class UnitOfExpression {
  static const String ea = 'EA';
  static const String pc = 'PC';
  static const String pck = 'PCK';
  static const String carton = 'Carton';

  static const List<String> allowed = [ea, pc, pck, carton];

  static String? normalize(Object? raw) {
    final v = raw?.toString().trim();
    if (v == null || v.isEmpty) return null;
    return allowed.contains(v) ? v : null;
  }
}

class Commodity {
  final String id;
  final String name;
  final HealthProgram program;
  /// Legacy free-text unit label (e.g., "packs", "units"). Kept for backwards compatibility.
  final String unit;
  /// Standardized unit of expression for quantities (e.g., EA/PC/PCK/Carton).
  final String? unitOfExpression;
  final int currentQuantity;
  final int minThreshold;
  final DateTime createdAt;
  final DateTime updatedAt;

  Commodity({
    required this.id,
    required this.name,
    required this.program,
    required this.unit,
    this.unitOfExpression,
    required this.currentQuantity,
    required this.minThreshold,
    required this.createdAt,
    required this.updatedAt,
  });

  String? get normalizedUnitOfExpression => UnitOfExpression.normalize(unitOfExpression);

  StockStatus get status {
    if (currentQuantity == 0) return StockStatus.stockOut;
    if (currentQuantity <= minThreshold) return StockStatus.low;
    return StockStatus.ok;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'program': program.name,
    'unit': unit,
    'unit_of_expression': unitOfExpression,
    'currentQuantity': currentQuantity,
    'minThreshold': minThreshold,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Commodity.fromJson(Map<String, dynamic> json) => Commodity(
    id: json['id'],
    name: json['name'],
    program: HealthProgram.values.firstWhere((e) => e.name == json['program']),
    unit: json['unit'] ?? 'units',
    unitOfExpression: UnitOfExpression.normalize(json['unit_of_expression'] ?? json['unitOfExpression']),
    // Backend commodities are a global catalog and often do not store per-user quantities.
    currentQuantity: int.tryParse((json['currentQuantity'] ?? json['current_quantity'] ?? json['currentquantity'] ?? 0).toString()) ?? 0,
    minThreshold: int.tryParse((json['minThreshold'] ?? json['min_threshold'] ?? json['minthreshold'] ?? 0).toString()) ?? 0,
    createdAt: DateTime.tryParse((json['createdAt'] ?? json['created_at'] ?? json['createdat'] ?? DateTime.now().toIso8601String()).toString()) ?? DateTime.now(),
    updatedAt: DateTime.tryParse((json['updatedAt'] ?? json['updated_at'] ?? json['updatedat'] ?? DateTime.now().toIso8601String()).toString()) ?? DateTime.now(),
  );

  Commodity copyWith({
    String? id,
    String? name,
    HealthProgram? program,
    String? unit,
    String? unitOfExpression,
    int? currentQuantity,
    int? minThreshold,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Commodity(
    id: id ?? this.id,
    name: name ?? this.name,
    program: program ?? this.program,
    unit: unit ?? this.unit,
    unitOfExpression: unitOfExpression ?? this.unitOfExpression,
    currentQuantity: currentQuantity ?? this.currentQuantity,
    minThreshold: minThreshold ?? this.minThreshold,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

enum MovementType { add, deduct }

enum MovementReason { receive, wastage, expiry, returnItem, countCorrection, delivery, other }

class StockMovement {
  final String id;
  final String commodityId;
  final String userId;
  final MovementType type;
  final int quantity;
  final MovementReason reason;
  final String? notes;
  final String? batchNumber;
  final DateTime? expiryDate;
  final SyncStatus syncStatus;
  final DateTime createdAt;

  StockMovement({
    required this.id,
    required this.commodityId,
    required this.userId,
    required this.type,
    required this.quantity,
    required this.reason,
    this.notes,
    this.batchNumber,
    this.expiryDate,
    this.syncStatus = SyncStatus.pending,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'commodityId': commodityId,
    'userId': userId,
    'type': type.name,
    'quantity': quantity,
    'reason': reason.name,
    'notes': notes,
    'batchNumber': batchNumber,
    'expiryDate': expiryDate?.toIso8601String(),
    'syncStatus': syncStatus.name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
    id: json['id'],
    commodityId: (json['commodityId'] ?? json['commodityid'] ?? json['commodity_id']).toString(),
    userId: (json['userId'] ?? json['userid'] ?? json['user_id']).toString(),
    type: (() {
      final raw = (json['type'] ?? '').toString();
      return MovementType.values.firstWhere((e) => e.name == raw, orElse: () => MovementType.add);
    })(),
    quantity: json['quantity'],
    reason: (() {
      final raw = (json['reason'] ?? '').toString();
      return MovementReason.values.firstWhere((e) => e.name == raw, orElse: () => MovementReason.other);
    })(),
    notes: json['notes'],
    batchNumber: json['batchNumber'] ?? json['batch_number'] ?? json['batchnumber'],
    expiryDate: (() {
      final raw = json['expiryDate'] ?? json['expiry_date'] ?? json['expirydate'];
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    })(),
    syncStatus: SyncStatus.values.firstWhere((e) => e.name == (json['syncStatus'] ?? json['syncstatus']).toString()),
    createdAt: DateTime.parse((json['createdAt'] ?? json['createdat']).toString()),
  );

  StockMovement copyWith({
    String? id,
    String? commodityId,
    String? userId,
    MovementType? type,
    int? quantity,
    MovementReason? reason,
    String? notes,
    String? batchNumber,
    DateTime? expiryDate,
    SyncStatus? syncStatus,
    DateTime? createdAt,
  }) => StockMovement(
    id: id ?? this.id,
    commodityId: commodityId ?? this.commodityId,
    userId: userId ?? this.userId,
    type: type ?? this.type,
    quantity: quantity ?? this.quantity,
    reason: reason ?? this.reason,
    notes: notes ?? this.notes,
    batchNumber: batchNumber ?? this.batchNumber,
    expiryDate: expiryDate ?? this.expiryDate,
    syncStatus: syncStatus ?? this.syncStatus,
    createdAt: createdAt ?? this.createdAt,
  );
}
