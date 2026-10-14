class DayStat {
  const DayStat({
    required this.day,
    required this.transactions,
    required this.validated,
  });

  final DateTime day;
  final int transactions;
  final int validated;
}

class CategoryStat {
  const CategoryStat({
    required this.code,
    required this.name,
    required this.count,
  });

  final String code;
  final String name;
  final int count;
}

class AdminStatistics {
  const AdminStatistics({
    required this.days,
    required this.byCategory,
    required this.authorized,
    required this.refused,
  });

  final List<DayStat> days;
  final List<CategoryStat> byCategory;
  final int authorized;
  final int refused;

  static int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  factory AdminStatistics.fromMap(Map<String, dynamic> map) {
    final days = (map['days'] as List?) ?? const [];
    final categories = (map['by_category'] as List?) ?? const [];
    final passages = (map['passages'] as Map?) ?? const {};
    return AdminStatistics(
      days: [
        for (final item in days)
          DayStat(
            day: DateTime.tryParse('${(item as Map)['day']}') ?? DateTime.now(),
            transactions: _int(item['transactions']),
            validated: _int(item['validated']),
          ),
      ],
      byCategory: [
        for (final item in categories)
          CategoryStat(
            code: '${(item as Map)['code']}',
            name: '${item['name']}',
            count: _int(item['count']),
          ),
      ],
      authorized: _int(passages['autorise']),
      refused: _int(passages['refuse']),
    );
  }
}
