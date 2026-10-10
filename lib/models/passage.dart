import 'toll_tariff.dart';

enum PassageResult {
  autorise,
  refuse;

  static PassageResult fromValue(String value) =>
      value == 'refuse' ? PassageResult.refuse : PassageResult.autorise;

  String get label =>
      this == PassageResult.autorise ? 'Autorisé' : 'Refusé';
}

class Passage {
  const Passage({
    required this.id,
    required this.receiptId,
    required this.agentId,
    required this.postId,
    required this.result,
    this.refusalReason,
    required this.createdAt,
  });

  final String id;
  final String receiptId;
  final String agentId;
  final String postId;
  final PassageResult result;
  final String? refusalReason;
  final DateTime createdAt;

  factory Passage.fromMap(Map<String, dynamic> map) {
    return Passage(
      id: (map['id'] ?? '').toString(),
      receiptId: (map['receipt_id'] ?? '').toString(),
      agentId: (map['agent_id'] ?? '').toString(),
      postId: (map['post_id'] ?? '').toString(),
      result: PassageResult.fromValue((map['result'] ?? '').toString()),
      refusalReason: map['refusal_reason']?.toString(),
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

/// Informations renvoyées à l'agent après le scan d'un code QR.
class ScannedReceipt {
  const ScannedReceipt({
    required this.qrCode,
    required this.registrationNumber,
    required this.brand,
    required this.model,
    required this.categoryCode,
    required this.categoryName,
    required this.postName,
    required this.tripType,
    required this.amountDue,
    required this.currency,
  });

  final String qrCode;
  final String registrationNumber;
  final String brand;
  final String model;
  final String categoryCode;
  final String categoryName;
  final String postName;
  final TripType tripType;
  final double amountDue;
  final String currency;

  factory ScannedReceipt.fromMap(Map<String, dynamic> map) {
    final amount = map['amount_due'];
    return ScannedReceipt(
      qrCode: (map['qr_code'] ?? '').toString(),
      registrationNumber: (map['registration_number'] ?? '').toString(),
      brand: (map['brand'] ?? '').toString(),
      model: (map['model'] ?? '').toString(),
      categoryCode: (map['category_code'] ?? '').toString(),
      categoryName: (map['category_name'] ?? '').toString(),
      postName: (map['post_name'] ?? '').toString(),
      tripType: TripType.fromValue((map['trip_type'] ?? '').toString()),
      amountDue: amount is num
          ? amount.toDouble()
          : double.tryParse(amount.toString()) ?? 0,
      currency: (map['currency'] ?? '').toString(),
    );
  }
}
