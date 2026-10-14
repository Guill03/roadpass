class TollPost {
  const TollPost({
    required this.id,
    required this.code,
    required this.name,
    required this.location,
    required this.isActive,
    this.sequence,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String code;
  final String name;
  final String location;
  final bool isActive;

  /// Position sur l'axe Kinshasa-Matadi (1 = premier poste en sortant de
  /// Kinshasa). Nul tant que l'ordre n'est pas défini.
  final int? sequence;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory TollPost.fromMap(Map<String, dynamic> map) {
    return TollPost(
      id: (map['id'] ?? '').toString(),
      code: (map['code'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      location: (map['location'] ?? '').toString(),
      isActive: map['is_active'] == true || map['is_active'] == 'true',
      sequence: map['sequence'] is num
          ? (map['sequence'] as num).toInt()
          : int.tryParse('${map['sequence'] ?? ''}'),
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
