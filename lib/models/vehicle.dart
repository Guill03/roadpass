class Vehicle {
  const Vehicle({
    required this.id,
    required this.userId,
    required this.brand,
    required this.model,
    required this.registrationNumber,
    required this.category,
    this.categoryId,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String brand;
  final String model;
  final String registrationNumber;

  /// Libellé texte historique (Bloc B). Conservé pour compatibilité, mais
  /// [categoryId] est désormais la source de vérité pour le calcul des
  /// tarifs (Bloc C) : voir vehicle_categories.
  final String category;
  final String? categoryId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Vehicle.fromMap(Map<String, dynamic> map) {
    return Vehicle(
      id: (map['id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      brand: (map['brand'] ?? '').toString(),
      model: (map['model'] ?? '').toString(),
      registrationNumber: (map['registration_number'] ?? '').toString(),
      category: (map['category'] ?? '').toString(),
      categoryId: map['category_id']?.toString(),
      isActive: map['is_active'] == true || map['is_active'] == 'true',
      createdAt: _parseDate(map['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(map['updated_at']) ?? DateTime.now(),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  Vehicle copyWith({
    String? id,
    String? userId,
    String? brand,
    String? model,
    String? registrationNumber,
    String? category,
    String? categoryId,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Vehicle(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      category: category ?? this.category,
      categoryId: categoryId ?? this.categoryId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
