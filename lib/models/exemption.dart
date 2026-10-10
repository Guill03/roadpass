class Exemption {
  const Exemption({
    required this.id,
    required this.vehicleId,
    required this.registrationNumber,
    required this.brand,
    required this.model,
    required this.reason,
    required this.status,
    required this.validFrom,
    this.validUntil,
  });

  final String id;
  final String vehicleId;
  final String registrationNumber;
  final String brand;
  final String model;
  final String reason;
  final String status;
  final DateTime validFrom;
  final DateTime? validUntil;

  bool get isActive =>
      status == 'active' &&
      (validUntil == null || validUntil!.isAfter(DateTime.now()));

  factory Exemption.fromMap(Map<String, dynamic> map) {
    return Exemption(
      id: (map['id'] ?? '').toString(),
      vehicleId: (map['vehicle_id'] ?? '').toString(),
      registrationNumber: (map['registration_number'] ?? '').toString(),
      brand: (map['brand'] ?? '').toString(),
      model: (map['model'] ?? '').toString(),
      reason: (map['reason'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      validFrom:
          DateTime.tryParse((map['valid_from'] ?? '').toString()) ??
          DateTime.now(),
      validUntil: DateTime.tryParse((map['valid_until'] ?? '').toString()),
    );
  }
}

/// Résultat de la recherche d'un véhicule par l'administrateur.
class FoundVehicle {
  const FoundVehicle({
    required this.id,
    required this.registrationNumber,
    required this.brand,
    required this.model,
    required this.ownerName,
  });

  final String id;
  final String registrationNumber;
  final String brand;
  final String model;
  final String ownerName;

  factory FoundVehicle.fromMap(Map<String, dynamic> map) {
    return FoundVehicle(
      id: (map['id'] ?? '').toString(),
      registrationNumber: (map['registration_number'] ?? '').toString(),
      brand: (map['brand'] ?? '').toString(),
      model: (map['model'] ?? '').toString(),
      ownerName: (map['owner_name'] ?? '').toString(),
    );
  }
}
