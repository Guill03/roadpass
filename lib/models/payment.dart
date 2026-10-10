enum PaymentStatus {
  enAttente,
  reussi,
  refuse;

  static PaymentStatus fromValue(String value) {
    switch (value) {
      case 'reussi':
        return PaymentStatus.reussi;
      case 'refuse':
        return PaymentStatus.refuse;
      case 'en_attente':
      default:
        return PaymentStatus.enAttente;
    }
  }

  String get label => switch (this) {
    PaymentStatus.enAttente => 'En attente',
    PaymentStatus.reussi => 'Réussi',
    PaymentStatus.refuse => 'Refusé',
  };
}

class Payment {
  const Payment({
    required this.id,
    required this.transactionId,
    required this.paymentMethod,
    required this.externalReference,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String transactionId;
  final String paymentMethod;
  final String externalReference;
  final PaymentStatus status;
  final DateTime createdAt;

  String get methodLabel =>
      paymentMethod == 'simulation' ? 'Simulation' : paymentMethod;

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: (map['id'] ?? '').toString(),
      transactionId: (map['transaction_id'] ?? '').toString(),
      paymentMethod: (map['payment_method'] ?? '').toString(),
      externalReference: (map['external_reference'] ?? '').toString(),
      status: PaymentStatus.fromValue((map['status'] ?? '').toString()),
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}
