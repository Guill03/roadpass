import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/receipt.dart';
import '../../../models/toll_post.dart';
import '../../../models/toll_tariff.dart';
import '../../../models/toll_transaction.dart';
import '../../../models/vehicle.dart';
import '../../../models/prepaid_account.dart';
import '../../../services/payment_service.dart';
import '../../../services/prepaid_service.dart';
import '../../../services/receipt_service.dart';
import '../../../services/toll_catalog_service.dart';
import '../../../services/transaction_service.dart';
import '../../../services/vehicle_service.dart';

/// Enregistrement d'un passage (transaction « Initiée ») et suivi des
/// passages de l'utilisateur. Le paiement est simulé (aucun débit réel).
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    super.key,
    required this.vehicleService,
    required this.catalogService,
    required this.transactionService,
    required this.paymentService,
    required this.receiptService,
    required this.prepaidService,
  });

  final VehicleServiceBase vehicleService;
  final TollCatalogServiceBase catalogService;
  final TransactionServiceBase transactionService;
  final PaymentServiceBase paymentService;
  final ReceiptServiceBase receiptService;
  final PrepaidServiceBase prepaidService;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  List<Vehicle> _vehicles = const [];
  List<TollPost> _posts = const [];
  List<TollTransaction> _transactions = const [];
  Map<String, Receipt> _receiptsByTransaction = const {};
  PrepaidAccount? _account;

  Vehicle? _vehicle;
  TollPost? _post;
  TripType _tripType = TripType.longueDistance;

  bool _previewLoading = false;
  TollTariff? _previewTariff;
  bool _previewDone = false;

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
        widget.vehicleService.getMyVehicles(),
        widget.catalogService.getTollPosts(),
        widget.transactionService.getMyTransactions(),
        widget.receiptService.getMyReceipts(),
        widget.prepaidService.getMyAccount(),
      ]);
      if (!mounted) return;
      final vehicles = (results[0] as List<Vehicle>)
          .where((v) => v.isActive && v.categoryId != null)
          .toList();
      final posts = results[1] as List<TollPost>;
      setState(() {
        _vehicles = vehicles;
        _posts = posts;
        _transactions = results[2] as List<TollTransaction>;
        _account = results[4] as PrepaidAccount?;
        _receiptsByTransaction = {
          for (final r in results[3] as List<Receipt>) r.transactionId: r,
        };
        _vehicle = vehicles.any((v) => v.id == _vehicle?.id)
            ? vehicles.firstWhere((v) => v.id == _vehicle!.id)
            : null;
        _post = posts.any((p) => p.id == _post?.id)
            ? posts.firstWhere((p) => p.id == _post!.id)
            : (posts.length == 1 ? posts.first : null);
        _loading = false;
      });
      _refreshPreview();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  /// Aperçu informatif du montant. Le montant réellement enregistré est
  /// recalculé par la base au moment de la création.
  Future<void> _refreshPreview() async {
    final vehicle = _vehicle;
    final post = _post;
    if (vehicle == null || post == null || vehicle.categoryId == null) {
      setState(() {
        _previewTariff = null;
        _previewDone = false;
      });
      return;
    }
    setState(() => _previewLoading = true);
    try {
      final tariff = await widget.catalogService.findApplicableTariff(
        tollPostId: post.id,
        categoryId: vehicle.categoryId!,
        tripType: _tripType,
        at: DateTime.now(),
      );
      if (!mounted) return;
      setState(() {
        _previewTariff = tariff;
        _previewDone = true;
        _previewLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _previewLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    final vehicle = _vehicle;
    final post = _post;
    if (vehicle == null || post == null) {
      setState(() => _error = 'Choisissez un véhicule et un poste de péage.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.transactionService.createTransaction(
        vehicleId: vehicle.id,
        tollPostId: post.id,
        tripType: _tripType,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passage enregistré.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _cancel(TollTransaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler ce passage ?'),
        content: const Text('Cette action est définitive.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Annuler le passage'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.transactionService.cancelTransaction(transaction.id);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _pay(TollTransaction transaction) async {
    final account = _account;
    final canUseAccount =
        account != null && account.isActive && account.balance >= 1;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Régler ce passage'),
        content: Text(
          'Montant : ${transaction.amountDue.toStringAsFixed(2)} '
          '${transaction.currency}\n\n'
          'Paiement simulé : aucun argent réel n’est débité.'
          '${account != null ? '\nSolde de votre compte prépayé : ${account.balance} passage(s).' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Retour'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('fail'),
            child: const Text('Simuler un échec'),
          ),
          if (canUseAccount)
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop('account'),
              child: const Text('Compte prépayé'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('success'),
            child: const Text('Payer'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    try {
      if (choice == 'account') {
        await widget.prepaidService.payTransactionWithAccount(transaction.id);
      } else {
        await widget.paymentService.payTransactionSimulated(
          transaction.id,
          succeed: choice == 'success',
        );
      }
      await _load();
      if (!mounted) return;
      final message = switch (choice) {
        'account' => 'Passage réglé avec votre compte prépayé.',
        'success' => 'Paiement réussi (simulation).',
        _ => 'Paiement refusé (simulation).',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _showReceipt(TollTransaction transaction) {
    final receipt = _receiptsByTransaction[transaction.id];
    if (receipt == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Justificatif de paiement'),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: QrImageView(data: receipt.qrCode, size: 220),
              ),
              const SizedBox(height: 12),
              SelectableText(
                receipt.qrCode,
                style: const TextStyle(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text('Statut : ${receipt.status.label}'),
              const SizedBox(height: 4),
              const Text(
                'Présentez ce code à l’agent de vérification.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  String _vehicleLabel(String vehicleId) {
    for (final vehicle in _vehicles) {
      if (vehicle.id == vehicleId) {
        return '${vehicle.brand} ${vehicle.model} (${vehicle.registrationNumber})';
      }
    }
    return 'Véhicule';
  }

  String _tripLabel(TripType type) =>
      type == TripType.longueDistance ? 'Longue distance' : 'Demi-trajet';

  String _formatDate(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enregistrer un passage',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 16),
                if (_vehicles.isEmpty)
                  const Text(
                    'Ajoutez d’abord un véhicule actif avec une catégorie '
                    'dans « Mes véhicules ».',
                  )
                else if (_posts.isEmpty)
                  const Text('Aucun poste de péage n’est disponible.')
                else ...[
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 300,
                        child: DropdownButtonFormField<Vehicle>(
                          initialValue: _vehicle,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Véhicule',
                          ),
                          items: _vehicles
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(
                                    '${v.brand} ${v.model} — ${v.registrationNumber}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() => _vehicle = value);
                            _refreshPreview();
                          },
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: DropdownButtonFormField<TollPost>(
                          initialValue: _post,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Poste de péage',
                          ),
                          items: _posts
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(
                                    p.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() => _post = value);
                            _refreshPreview();
                          },
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<TripType>(
                          initialValue: _tripType,
                          decoration: const InputDecoration(
                            labelText: 'Type de trajet',
                          ),
                          items: TripType.values
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(_tripLabel(t)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(
                              () => _tripType = value ?? TripType.longueDistance,
                            );
                            _refreshPreview();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Demi-trajet : vous ne dépassez pas un autre poste de péage.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  if (_previewLoading)
                    const LinearProgressIndicator()
                  else if (_previewDone && _previewTariff != null)
                    Text(
                      'Montant : ${_previewTariff!.amount.toStringAsFixed(2)} '
                      '${_previewTariff!.currency}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else if (_previewDone)
                    const Text(
                      'Aucun tarif disponible pour cette combinaison.',
                      style: TextStyle(color: Colors.orange),
                    ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: (_submitting ||
                              _previewTariff == null ||
                              _vehicle == null ||
                              _post == null)
                          ? null
                          : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.alt_route),
                      label: const Text('Enregistrer le passage'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Mes passages',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTheme.navy,
          ),
        ),
        const SizedBox(height: 12),
        if (_transactions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Vous n’avez encore enregistré aucun passage.'),
            ),
          )
        else
          ..._transactions.map(
            (t) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.alt_route),
                title: Text(
                  '${t.amountDue.toStringAsFixed(2)} ${t.currency} — ${_tripLabel(t.tripType)}',
                ),
                subtitle: Text(
                  '${_vehicleLabel(t.vehicleId)}\n${_formatDate(t.createdAt)}',
                ),
                isThreeLine: true,
                trailing: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (t.settlementLabel != null)
                      Chip(label: Text(t.settlementLabel!)),
                    Chip(label: Text(t.status.label)),
                    if (_receiptsByTransaction[t.id] != null)
                      OutlinedButton(
                        onPressed: () => _showReceipt(t),
                        child: const Text('Justificatif'),
                      ),
                    if (t.canCancel)
                      FilledButton(
                        onPressed: () => _pay(t),
                        child: const Text('Payer'),
                      ),
                    if (t.canCancel)
                      TextButton(
                        onPressed: () => _cancel(t),
                        child: const Text('Annuler'),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
