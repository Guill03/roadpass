import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/exemption.dart';
import '../../../services/admin_operations_service.dart';

/// Gestion des exemptions par l'administrateur : recherche du véhicule par
/// immatriculation, motif, durée optionnelle, clôture.
class ExemptionsAdminScreen extends StatefulWidget {
  const ExemptionsAdminScreen({super.key, required this.service});

  final AdminOperationsServiceBase service;

  @override
  State<ExemptionsAdminScreen> createState() => _ExemptionsAdminScreenState();
}

class _ExemptionsAdminScreenState extends State<ExemptionsAdminScreen> {
  final _plateController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _busy = false;
  bool _loading = true;
  String? _error;
  FoundVehicle? _found;
  DateTime? _validUntil;
  List<Exemption> _exemptions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _plateController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await widget.service.listExemptions();
      if (!mounted) return;
      setState(() {
        _exemptions = list;
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

  Future<void> _search() async {
    if (_plateController.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _found = null;
    });
    try {
      final vehicle = await widget.service.findVehicle(_plateController.text);
      if (mounted) setState(() => _found = vehicle);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 30)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _validUntil = picked);
  }

  Future<void> _create() async {
    final vehicle = _found;
    if (vehicle == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.createExemption(
        vehicleId: vehicle.id,
        reason: _reasonController.text,
        validUntil: _validUntil,
      );
      if (!mounted) return;
      setState(() {
        _found = null;
        _validUntil = null;
        _plateController.clear();
        _reasonController.clear();
      });
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end(Exemption exemption) async {
    try {
      await widget.service.endExemption(exemption.id);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  String _date(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Accorder une exemption',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _plateController,
                        decoration: const InputDecoration(
                          labelText: 'Immatriculation du véhicule',
                        ),
                        onSubmitted: (_) => _search(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _busy ? null : _search,
                      child: const Text('Rechercher'),
                    ),
                  ],
                ),
                if (_found != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    '${_found!.registrationNumber} — ${_found!.brand} ${_found!.model}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text('Propriétaire : ${_found!.ownerName}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Motif (ex. véhicule de l’État)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickEndDate,
                        icon: const Icon(Icons.event),
                        label: Text(
                          _validUntil == null
                              ? 'Sans date de fin'
                              : 'Jusqu’au ${_date(_validUntil!)}',
                        ),
                      ),
                      if (_validUntil != null)
                        IconButton(
                          tooltip: 'Retirer la date de fin',
                          onPressed: () => setState(() => _validUntil = null),
                          icon: const Icon(Icons.close),
                        ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _busy ? null : _create,
                        child: const Text('Accorder l’exemption'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Exemptions',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTheme.navy,
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_exemptions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aucune exemption enregistrée.'),
            ),
          )
        else
          ..._exemptions.map(
            (e) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Icon(
                  e.isActive ? Icons.verified_outlined : Icons.history,
                  color: e.isActive ? Colors.green : Colors.grey,
                ),
                title: Text('${e.registrationNumber} — ${e.brand} ${e.model}'),
                subtitle: Text(
                  '${e.reason}\nDepuis le ${_date(e.validFrom)}'
                  '${e.validUntil != null ? ' jusqu’au ${_date(e.validUntil!)}' : ''}',
                ),
                isThreeLine: true,
                trailing: e.isActive
                    ? TextButton(
                        onPressed: () => _end(e),
                        child: const Text('Mettre fin'),
                      )
                    : const Chip(label: Text('Terminée')),
              ),
            ),
          ),
      ],
    );
  }
}
