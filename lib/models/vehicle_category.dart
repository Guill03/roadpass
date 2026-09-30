class VehicleCategory {
  const VehicleCategory({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String code;
  final String name;

  /// Explication destinée à être affichée à l'utilisateur, pour qu'il
  /// comprenne pourquoi son véhicule est classé dans cette catégorie.
  final String description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory VehicleCategory.fromMap(Map<String, dynamic> map) {
    return VehicleCategory(
      id: (map['id'] ?? '').toString(),
      code: (map['code'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
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
}
