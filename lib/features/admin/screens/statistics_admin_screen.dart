import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/admin_statistics.dart';
import '../../../models/admin_transaction.dart';
import '../../../services/admin_operations_service.dart';

/// Statistiques d'activité : indicateurs globaux, transactions par jour,
/// répartition par catégorie et résultat des contrôles. Lecture seule.
class StatisticsAdminScreen extends StatefulWidget {
  const StatisticsAdminScreen({super.key, required this.service});

  final AdminOperationsServiceBase service;

  @override
  State<StatisticsAdminScreen> createState() => _StatisticsAdminScreenState();
}

class _StatisticsAdminScreenState extends State<StatisticsAdminScreen> {
  bool _loading = true;
  String? _error;
  int _days = 14;
  AdminStatistics? _stats;
  TransactionsSummary? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.service.getStatistics(days: _days),
        widget.service.getTransactionsSummary(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as AdminStatistics;
        _summary = results[1] as TransactionsSummary;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppTheme.navy,
      ),
    ),
  );

  Widget _stat(String label, String value, IconData icon) => SizedBox(
    width: 190,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppTheme.skyBlue),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    ),
  );

  Widget _bar(String label, int value, int max) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(width: 150, child: Text(label, overflow: TextOverflow.ellipsis)),
        Expanded(
          child: LinearProgressIndicator(
            value: max == 0 ? 0 : value / max,
            minHeight: 10,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text('$value', textAlign: TextAlign.right),
        ),
      ],
    ),
  );

  String _shortDay(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final stats = _stats;
    final summary = _summary;
    if (stats == null || summary == null) {
      return Text(
        _error ?? 'Statistiques indisponibles.',
        style: const TextStyle(color: Colors.red),
      );
    }

    final maxDay = stats.days.fold<int>(
      0,
      (max, d) => d.transactions > max ? d.transactions : max,
    );
    final maxCategory = stats.byCategory.fold<int>(
      0,
      (max, c) => c.count > max ? c.count : max,
    );
    final controls = stats.authorized + stats.refused;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _stat('Transactions', '${summary.total}', Icons.receipt_long_outlined),
            _stat(
              'Passages validés',
              '${summary.count('passage_valide')}',
              Icons.check_circle_outline,
            ),
            _stat('Passages refusés', '${summary.count('refusee')}', Icons.block),
            _stat('Exemptées', '${summary.exempted}', Icons.verified_outlined),
            for (final amount in summary.collected)
              _stat(
                'Encaissé (${amount.currency})',
                amount.amount.toStringAsFixed(2),
                Icons.payments_outlined,
              ),
          ],
        ),
        _title('Transactions par jour'),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7 jours')),
            ButtonSegment(value: 14, label: Text('14 jours')),
            ButtonSegment(value: 30, label: Text('30 jours')),
          ],
          selected: {_days},
          onSelectionChanged: (value) {
            setState(() => _days = value.first);
            _load();
          },
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final day in stats.days)
                  _bar(_shortDay(day.day), day.transactions, maxDay),
              ],
            ),
          ),
        ),
        _title('Par catégorie de véhicule'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: stats.byCategory.isEmpty
                ? const Text('Aucune catégorie.')
                : Column(
                    children: [
                      for (final category in stats.byCategory)
                        _bar(
                          '${category.code} — ${category.name}',
                          category.count,
                          maxCategory,
                        ),
                    ],
                  ),
          ),
        ),
        _title('Contrôles à la barrière'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: controls == 0
                ? const Text('Aucun contrôle enregistré.')
                : Column(
                    children: [
                      _bar('Autorisés', stats.authorized, controls),
                      _bar('Refusés', stats.refused, controls),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
