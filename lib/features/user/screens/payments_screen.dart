import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/payment.dart';
import '../../../models/toll_transaction.dart';
import '../../../services/payment_service.dart';
import '../../../services/transaction_service.dart';

/// Historique des paiements de l'utilisateur (simulés pour l'instant).
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({
    super.key,
    required this.paymentService,
    required this.transactionService,
  });

  final PaymentServiceBase paymentService;
  final TransactionServiceBase transactionService;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  bool _loading = true;
  String? _error;
  List<Payment> _payments = const [];
  Map<String, TollTransaction> _transactionsById = const {};

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
        widget.paymentService.getMyPayments(),
        widget.transactionService.getMyTransactions(),
      ]);
      if (!mounted) return;
      setState(() {
        _payments = results[0] as List<Payment>;
        _transactionsById = {
          for (final t in results[1] as List<TollTransaction>) t.id: t,
        };
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

  String _formatDate(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mes paiements',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTheme.navy,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Les paiements sont simulés : aucun argent réel n’est débité.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        if (_payments.isEmpty && _error == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aucun paiement pour le moment.'),
            ),
          )
        else
          ..._payments.map((payment) {
            final transaction = _transactionsById[payment.transactionId];
            final amount = transaction == null
                ? ''
                : '${transaction.amountDue.toStringAsFixed(2)} ${transaction.currency} — ';
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Icon(
                  payment.status == PaymentStatus.reussi
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color: payment.status == PaymentStatus.reussi
                      ? Colors.green
                      : Colors.orange,
                ),
                title: Text('$amount${payment.methodLabel}'),
                subtitle: Text(
                  'Réf. ${payment.externalReference}\n${_formatDate(payment.createdAt)}',
                ),
                isThreeLine: true,
                trailing: Chip(label: Text(payment.status.label)),
              ),
            );
          }),
      ],
    );
  }
}
