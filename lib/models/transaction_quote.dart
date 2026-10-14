import 'toll_tariff.dart';

/// Devis calculé par la base (quote_transaction) : type de trajet déduit,
/// nombre de postes franchis, montant et devise. C'est la même règle que
/// celle qui s'applique à l'enregistrement : l'écran ne la recalcule pas.
class TransactionQuote {
  const TransactionQuote({
    required this.tripType,
    required this.postsCrossed,
    required this.amount,
    required this.currency,
    required this.isExempt,
  });

  final TripType tripType;
  final int postsCrossed;
  final double amount;
  final String currency;

  /// Le véhicule a une exemption active : le passage sera à 0.
  final bool isExempt;

  factory TransactionQuote.fromMap(Map<String, dynamic> map) {
    final amount = map['amount'];
    final posts = map['posts_crossed'];
    return TransactionQuote(
      tripType: TripType.fromValue((map['trip_type'] ?? '').toString()),
      postsCrossed: posts is num ? posts.toInt() : int.tryParse('$posts') ?? 1,
      amount: amount is num
          ? amount.toDouble()
          : double.tryParse('$amount') ?? 0,
      currency: (map['currency'] ?? '').toString(),
      isExempt: map['exemption_id'] != null,
    );
  }
}
