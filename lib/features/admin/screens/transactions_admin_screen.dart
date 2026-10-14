import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/admin_transaction.dart';
import '../../../models/toll_tariff.dart';
import '../../../models/toll_transaction.dart';
import '../../../services/admin_operations_service.dart';

/// Supervision des transactions : indicateurs, filtre par statut et liste.
/// Lecture seule.
class TransactionsAdminScreen extends StatefulWidget {
  const TransactionsAdminScreen({super.key, required this.service});

  final AdminOperationsServiceBase service;

  @override
  State<TransactionsAdminScreen> createState() =>
      _TransactionsAdminScreenState();
}

class _TransactionsAdminScreenState extends State<TransactionsAdminScreen> {
  bool _loading = true;
  String? _error;
  TransactionsSummary? _summary;
  List<AdminTransaction> _transactions = const [];
  TransactionStatus? _filter;

  static const _statusValues = {
    TransactionStatus.initiee: 'initiee',
    TransactionStatus.enAttentePaiement: 'en_attente_paiement',
    TransactionStatus.payee: 'payee',
    TransactionStatus.verifiee: 'verifiee',
    TransactionStatus.passageValide: 'passage_valide',
    TransactionStatus.echouee: 'echouee',
    TransactionStatus.annulee: 'annulee',
    TransactionStatus.refusee: 'refusee',
  };

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
        widget.service.getTransactionsSummary(),
        widget.service.listTransactions(
          status: _filter == null ? null : _statusValues[_filter],
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as TransactionsSummary;
        _transactions = results[1] as List<AdminTransaction>;
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

  String _tripLabel(TripType type) =>
      type == TripType.longueDistance ? 'Longue distance' : 'Demi-trajet';

  String _formatDate(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  Widget _stat(String label, String value, IconData icon) {
    return SizedBox(
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
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        if (summary != null)
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
              _stat(
                'Passages refusés',
                '${summary.count('refusee')}',
                Icons.block,
              ),
              _stat(
                'À vérifier (payées)',
                '${summary.count('payee')}',
                Icons.qr_code_scanner,
              ),
              _stat('Exemptées', '${summary.exempted}', Icons.verified_outlined),
              _stat(
                'Comptes prépayés',
                '${summary.prepaid}',
                Icons.account_balance_wallet_outlined,
              ),
              for (final amount in summary.collected)
                _stat(
                  'Encaissé (${amount.currency})',
                  amount.amount.toStringAsFixed(2),
                  Icons.payments_outlined,
                ),
            ],
          ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'Transactions',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.navy,
                ),
              ),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<TransactionStatus?>(
                initialValue: _filter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Statut'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tous')),
                  for (final status in TransactionStatus.values)
                    DropdownMenuItem(value: status, child: Text(status.label)),
                ],
                onChanged: (value) {
                  setState(() => _filter = value);
                  _load();
                },
              ),
            ),
            IconButton(
              tooltip: 'Actualiser',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_transactions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aucune transaction pour ce filtre.'),
            ),
          )
        else
          ..._transactions.map(
            (t) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.alt_route),
                title: Text(
                  '${t.registrationNumber} — ${t.amountDue.toStringAsFixed(2)} ${t.currency}',
                ),
                subtitle: Text(
                  '${t.userName} · ${t.brand} ${t.model}\n'
                  '${t.postName}${t.destinationName != null && t.destinationName != t.postName ? ' → ${t.destinationName}' : ''}'
                  ' · ${_tripLabel(t.tripType)}${t.postsCrossed != null ? ' (${t.postsCrossed} poste(s))' : ''} · ${_formatDate(t.createdAt)}'
                  '${t.refusalReason != null ? '\nMotif du refus : ${t.refusalReason}' : ''}',
                ),
                isThreeLine: true,
                trailing: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (t.settlementLabel != null)
                      Chip(label: Text(t.settlementLabel!)),
                    Chip(label: Text(t.status.label)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
