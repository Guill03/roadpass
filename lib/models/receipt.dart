enum ReceiptStatus {
  valide,
  utilise,
  invalide;

  static ReceiptStatus fromValue(String value) {
    switch (value) {
      case 'utilise':
        return ReceiptStatus.utilise;
      case 'invalide':
        return ReceiptStatus.invalide;
      case 'valide':
      default:
        return ReceiptStatus.valide;
    }
  }

  String get label => switch (this) {
    ReceiptStatus.valide => 'Valide',
    ReceiptStatus.utilise => 'Utilisé',
    ReceiptStatus.invalide => 'Invalide',
  };
}

class Receipt {
  const Receipt({
    required this.id,
    required this.transactionId,
    required this.qrCode,
    required this.status,
    required this.generatedAt,
  });

  final String id;
  final String transactionId;
  final String qrCode;
  final ReceiptStatus status;
  final DateTime generatedAt;

  factory Receipt.fromMap(Map<String, dynamic> map) {
    return Receipt(
      id: (map['id'] ?? '').toString(),
      transactionId: (map['transaction_id'] ?? '').toString(),
      qrCode: (map['qr_code'] ?? '').toString(),
      status: ReceiptStatus.fromValue((map['status'] ?? '').toString()),
      generatedAt:
          DateTime.tryParse((map['generated_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}
