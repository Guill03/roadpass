class PrepaidAccount {
  const PrepaidAccount({
    required this.id,
    required this.userId,
    required this.balance,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String userId;

  /// Nombre de passages restants.
  final int balance;
  final String status;
  final DateTime createdAt;

  bool get isActive => status == 'actif';

  factory PrepaidAccount.fromMap(Map<String, dynamic> map) {
    final balance = map['balance'];
    return PrepaidAccount(
      id: (map['id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      balance: balance is num
          ? balance.toInt()
          : int.tryParse(balance.toString()) ?? 0,
      status: (map['status'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}
