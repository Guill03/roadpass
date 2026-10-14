import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/audit_entry.dart';
import '../../../services/admin_operations_service.dart';

/// Journal d'audit : qui a fait quoi, quand. Lecture seule.
class AuditLogAdminScreen extends StatefulWidget {
  const AuditLogAdminScreen({super.key, required this.service});

  final AdminOperationsServiceBase service;

  @override
  State<AuditLogAdminScreen> createState() => _AuditLogAdminScreenState();
}

class _AuditLogAdminScreenState extends State<AuditLogAdminScreen> {
  bool _loading = true;
  String? _error;
  List<AuditEntry> _entries = const [];
  String? _entity;

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
      final entries = await widget.service.listAuditLog(entity: _entity);
      if (!mounted) return;
      setState(() {
        _entries = entries;
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
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Journal d’audit',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.navy,
                ),
              ),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String?>(
                initialValue: _entity,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Type d’objet'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tous')),
                  for (final entry in AuditEntry.entityLabels.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                ],
                onChanged: (value) {
                  setState(() => _entity = value);
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
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_entries.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aucune entrée pour ce filtre.'),
            ),
          )
        else
          ..._entries.map(
            (entry) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Icon(
                  entry.action == 'insert'
                      ? Icons.add_circle_outline
                      : Icons.edit_outlined,
                ),
                title: Text('${entry.actionLabel} — ${entry.entityLabel}'),
                subtitle: Text(
                  '${entry.userName ?? 'Action automatique'}'
                  '${entry.userRole != null ? ' (${entry.userRole})' : ''}'
                  ' · ${_formatDate(entry.createdAt)}'
                  '${entry.detailsText.isNotEmpty ? '\n${entry.detailsText}' : ''}',
                ),
                isThreeLine: entry.detailsText.isNotEmpty,
              ),
            ),
          ),
      ],
    );
  }
}
