/// Type de trajet tel que documenté sur le terrain (Chapitre 2) :
/// - [longueDistance] : trajet complet.
/// - [demiTrajet] : l'usager ne dépasse pas un autre poste de péage sur son
///   trajet. Le calcul de cette condition à partir d'un itinéraire réel
///   appartient à un bloc futur ; ici la valeur est seulement stockée.
enum TripType {
  longueDistance,
  demiTrajet;

  static TripType fromValue(String value) {
    switch (value) {
      case 'demi_trajet':
        return TripType.demiTrajet;
      case 'longue_distance':
      default:
        return TripType.longueDistance;
    }
  }

  String get value => switch (this) {
    TripType.longueDistance => 'longue_distance',
    TripType.demiTrajet => 'demi_trajet',
  };
}

class TollTariff {
  const TollTariff({
    required this.id,
    required this.tollPostId,
    required this.categoryId,
    required this.tripType,
    required this.amount,
    required this.currency,
    required this.validFrom,
    this.validUntil,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String tollPostId;
  final String categoryId;
  final TripType tripType;
  final double amount;
  final String currency;
  final DateTime validFrom;
  final DateTime? validUntil;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Un tarif est valide à l'instant [at] si [at] est dans
  /// [validFrom, validUntil[ (borne haute exclusive, ou tarif toujours actif
  /// si [validUntil] est nul).
  bool isValidAt(DateTime at) {
    if (at.isBefore(validFrom)) return false;
    if (validUntil != null && !at.isBefore(validUntil!)) return false;
    return true;
  }

  factory TollTariff.fromMap(Map<String, dynamic> map) {
    return TollTariff(
      id: (map['id'] ?? '').toString(),
      tollPostId: (map['toll_post_id'] ?? '').toString(),
      categoryId: (map['category_id'] ?? '').toString(),
      tripType: TripType.fromValue((map['trip_type'] ?? '').toString()),
      amount: _parseDouble(map['amount']) ?? 0,
      currency: (map['currency'] ?? '').toString(),
      validFrom: _parseDate(map['valid_from']) ?? DateTime.now(),
      validUntil: _parseDate(map['valid_until']),
      createdAt: _parseDate(map['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(map['updated_at']) ?? DateTime.now(),
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}
