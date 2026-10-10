import 'toll_tariff.dart';

/// Statuts du cycle de vie d'une transaction (Figure 13 du Chapitre 3).
enum TransactionStatus {
  initiee,
  enAttentePaiement,
  payee,
  verifiee,
  passageValide,
  echouee,
  annulee,
  refusee;

  static TransactionStatus fromValue(String value) {
    switch (value) {
      case 'en_attente_paiement':
        return TransactionStatus.enAttentePaiement;
      case 'payee':
        return TransactionStatus.payee;
      case 'verifiee':
        return TransactionStatus.verifiee;
      case 'passage_valide':
        return TransactionStatus.passageValide;
      case 'echouee':
        return TransactionStatus.echouee;
      case 'annulee':
        return TransactionStatus.annulee;
      case 'refusee':
        return TransactionStatus.refusee;
      case 'initiee':
      default:
        return TransactionStatus.initiee;
    }
  }

  String get label => switch (this) {
    TransactionStatus.initiee => 'Initiée',
    TransactionStatus.enAttentePaiement => 'En attente de paiement',
    TransactionStatus.payee => 'Payée',
    TransactionStatus.verifiee => 'Vérifiée',
    TransactionStatus.passageValide => 'Passage validé',
    TransactionStatus.echouee => 'Échouée',
    TransactionStatus.annulee => 'Annulée',
    TransactionStatus.refusee => 'Refusée',
  };
}

class TollTransaction {
  const TollTransaction({
    required this.id,
    required this.userId,
    required this.vehicleId,
    required this.tariffId,
    required this.registrationPostId,
    required this.tripType,
    required this.amountDue,
    required this.currency,
    required this.status,
    this.settlementType = 'paiement',
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String vehicleId;
  final String tariffId;
  final String registrationPostId;
  final TripType tripType;
  final double amountDue;
  final String currency;
  final TransactionStatus status;

  /// 'paiement', 'sous_provision' ou 'exemption' (RG5).
  final String settlementType;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get canCancel => status == TransactionStatus.initiee;

  String? get settlementLabel => switch (settlementType) {
    'sous_provision' => 'Compte prépayé',
    'exemption' => 'Exemption',
    _ => null,
  };

  factory TollTransaction.fromMap(Map<String, dynamic> map) {
    return TollTransaction(
      id: (map['id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      vehicleId: (map['vehicle_id'] ?? '').toString(),
      tariffId: (map['tariff_id'] ?? '').toString(),
      registrationPostId: (map['registration_post_id'] ?? '').toString(),
      tripType: TripType.fromValue((map['trip_type'] ?? '').toString()),
      amountDue: _parseDouble(map['amount_due']) ?? 0,
      currency: (map['currency'] ?? '').toString(),
      status: TransactionStatus.fromValue((map['status'] ?? '').toString()),
      settlementType: (map['settlement_type'] ?? 'paiement').toString(),
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
