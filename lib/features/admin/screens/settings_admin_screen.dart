import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/admin_operations_service.dart';

/// Réglages sensibles. Pour l'instant : activation de la simulation de
/// paiement (à désactiver en production dès qu'un vrai prestataire est
/// branché).
class SettingsAdminScreen extends StatefulWidget {
  const SettingsAdminScreen({super.key, required this.service});

  final AdminOperationsServiceBase service;

  @override
  State<SettingsAdminScreen> createState() => _SettingsAdminScreenState();
}

class _SettingsAdminScreenState extends State<SettingsAdminScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _simulation = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await widget.service.getPaymentSimulation();
      if (!mounted) return;
      setState(() {
        _simulation = enabled;
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

  Future<void> _change(bool enabled) async {
    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Activer la simulation de paiement ?'),
          content: const Text(
            'Tant qu’elle est active, tout usager peut déclarer un passage '
            'payé sans débit réel. À réserver aux tests.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Activer'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.setPaymentSimulation(enabled);
      if (mounted) setState(() => _simulation = enabled);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paramètres',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTheme.navy,
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        Card(
          child: SwitchListTile(
            title: const Text('Simulation de paiement'),
            subtitle: Text(
              _simulation
                  ? 'Active : les usagers peuvent « payer » sans débit réel.'
                  : 'Désactivée : aucun paiement simulé n’est accepté.',
            ),
            value: _simulation,
            onChanged: _busy ? null : _change,
          ),
        ),
      ],
    );
  }
}
