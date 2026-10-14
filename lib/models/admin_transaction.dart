import 'toll_tariff.dart';
import 'toll_transaction.dart';

/// Une transaction telle que l'administrateur la voit (avec plaque, usager,
/// poste et résultat du passage).
class AdminTransaction {
  const AdminTransaction({
    required this.id,
    required this.status,
    required this.settlementType,
    required this.tripType,
    required this.amountDue,
    required this.currency,
    required this.createdAt,
    required this.registrationNumber,
    required this.brand,
    required this.model,
    required this.userName,
    required this.postName,
    this.destinationName,
    this.postsCrossed,
    this.passageResult,
    this.refusalReason,
  });

  final String id;
  final TransactionStatus status;
  final String settlementType;
  final TripType tripType;
  final double amountDue;
  final String currency;
  final DateTime createdAt;
  final String registrationNumber;
  final String brand;
  final String model;
  final String userName;
  final String postName;
  final String? destinationName;
  final int? postsCrossed;
  final String? passageResult;
  final String? refusalReason;

  String? get settlementLabel => switch (settlementType) {
    'sous_provision' => 'Compte prépayé',
    'exemption' => 'Exemption',
    _ => null,
  };

  factory AdminTransaction.fromMap(Map<String, dynamic> map) {
    final amount = map['amount_due'];
    return AdminTransaction(
      id: (map['id'] ?? '').toString(),
      status: TransactionStatus.fromValue((map['status'] ?? '').toString()),
      settlementType: (map['settlement_type'] ?? 'paiement').toString(),
      tripType: TripType.fromValue((map['trip_type'] ?? '').toString()),
      amountDue: amount is num
          ? amount.toDouble()
          : double.tryParse(amount.toString()) ?? 0,
      currency: (map['currency'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '').toString()) ??
          DateTime.now(),
      registrationNumber: (map['registration_number'] ?? '').toString(),
      brand: (map['brand'] ?? '').toString(),
      model: (map['model'] ?? '').toString(),
      userName: (map['user_name'] ?? '').toString(),
      postName: (map['post_name'] ?? '').toString(),
      destinationName: map['destination_name']?.toString(),
      postsCrossed: map['posts_crossed'] is num
          ? (map['posts_crossed'] as num).toInt()
          : null,
      passageResult: map['passage_result']?.toString(),
      refusalReason: map['refusal_reason']?.toString(),
    );
  }
}

class CollectedAmount {
  const CollectedAmount({required this.currency, required this.amount});

  final String currency;
  final double amount;
}

class TransactionsSummary {
  const TransactionsSummary({
    required this.total,
    required this.byStatus,
    required this.collected,
    required this.exempted,
    required this.prepaid,
  });

  final int total;
  final Map<String, int> byStatus;
  final List<CollectedAmount> collected;
  final int exempted;
  final int prepaid;

  int count(String status) => byStatus[status] ?? 0;

  static int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  factory TransactionsSummary.fromMap(Map<String, dynamic> map) {
    final status = (map['by_status'] as Map?) ?? const {};
    final collected = (map['collected'] as List?) ?? const [];
    return TransactionsSummary(
      total: _int(map['total']),
      byStatus: {
        for (final entry in status.entries) '${entry.key}': _int(entry.value),
      },
      collected: [
        for (final item in collected)
          CollectedAmount(
            currency: '${(item as Map)['currency']}',
            amount: item['amount'] is num
                ? (item['amount'] as num).toDouble()
                : double.tryParse('${item['amount']}') ?? 0,
          ),
      ],
      exempted: _int(map['exempted']),
      prepaid: _int(map['prepaid']),
    );
  }
}
