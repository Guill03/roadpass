import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/admin_operations_service.dart';

/// Liste des utilisateurs et suspension/réactivation des agents (RG11).
/// Seuls les comptes agents peuvent être suspendus : la base le refuse
/// pour tout autre rôle.
class UsersAdminScreen extends StatefulWidget {
  const UsersAdminScreen({super.key, required this.service});

  final AdminOperationsServiceBase service;

  @override
  State<UsersAdminScreen> createState() => _UsersAdminScreenState();
}

class _UsersAdminScreenState extends State<UsersAdminScreen> {
  bool _loading = true;
  String? _error;
  List<AdminUserSummary> _users = const [];

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
      final users = await widget.service.listUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
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

  String _roleLabel(String role) => switch (role) {
    'agent' => 'Agent',
    'admin' => 'Administrateur',
    _ => 'Usager',
  };

  Future<void> _toggle(AdminUserSummary user) async {
    final suspend = !user.isSuspended;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(suspend ? 'Suspendre cet agent ?' : 'Réactiver cet agent ?'),
        content: Text(
          suspend
              ? '${user.fullName} ne pourra plus vérifier de justificatifs '
                    'ni décider d’un passage.'
              : '${user.fullName} pourra de nouveau vérifier des justificatifs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(suspend ? 'Suspendre' : 'Réactiver'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.service.setAccountStatus(
        user.id,
        suspend ? 'suspendu' : 'actif',
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Utilisateurs',
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
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else
          ..._users.map(
            (user) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Icon(
                  user.role == 'agent'
                      ? Icons.badge_outlined
                      : user.role == 'admin'
                      ? Icons.admin_panel_settings_outlined
                      : Icons.person_outline,
                ),
                title: Text(user.fullName.isEmpty ? user.email : user.fullName),
                subtitle: Text(user.email),
                trailing: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(label: Text(_roleLabel(user.role))),
                    if (user.isSuspended)
                      Chip(
                        label: const Text('Suspendu'),
                        backgroundColor: Colors.orange.shade100,
                      ),
                    if (user.role == 'agent')
                      TextButton(
                        onPressed: () => _toggle(user),
                        child: Text(user.isSuspended ? 'Réactiver' : 'Suspendre'),
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
