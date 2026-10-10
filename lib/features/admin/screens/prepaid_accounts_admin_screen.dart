import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/prepaid_account.dart';
import '../../../services/admin_operations_service.dart';

/// Ouverture et recharge des comptes prépayés (sous-provision) par
/// l'administrateur, après encaissement du client à la caisse.
class PrepaidAccountsAdminScreen extends StatefulWidget {
  const PrepaidAccountsAdminScreen({super.key, required this.service});

  final AdminOperationsServiceBase service;

  @override
  State<PrepaidAccountsAdminScreen> createState() =>
      _PrepaidAccountsAdminScreenState();
}

class _PrepaidAccountsAdminScreenState
    extends State<PrepaidAccountsAdminScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<AdminUserSummary> _users = const [];
  List<PrepaidAccount> _accounts = const [];
  AdminUserSummary? _selectedUser;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.service.listUsers(),
        widget.service.listPrepaidAccounts(),
      ]);
      if (!mounted) return;
      setState(() {
        _users = results[0] as List<AdminUserSummary>;
        _accounts = results[1] as List<PrepaidAccount>;
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

  AdminUserSummary? _userFor(String userId) {
    for (final user in _users) {
      if (user.id == userId) return user;
    }
    return null;
  }

  Future<void> _open() async {
    final user = _selectedUser;
    if (user == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.openPrepaidAccount(user.id);
      if (mounted) setState(() => _selectedUser = null);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recharge(PrepaidAccount account) async {
    final controller = TextEditingController();
    final quantity = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recharger le compte'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Nombre de passages à ajouter',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(controller.text.trim())),
            child: const Text('Recharger'),
          ),
        ],
      ),
    );
    if (quantity == null) return;
    if (quantity < 1) {
      setState(() => _error = 'La quantité doit être positive.');
      return;
    }
    try {
      await widget.service.rechargePrepaidAccount(account.id, quantity);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersWithoutAccount = _users
        .where((u) => !_accounts.any((a) => a.userId == u.id))
        .toList();

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
                  'Ouvrir un compte prépayé',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<AdminUserSummary>(
                        initialValue: _selectedUser,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Utilisateur',
                        ),
                        items: usersWithoutAccount
                            .map(
                              (u) => DropdownMenuItem(
                                value: u,
                                child: Text(
                                  '${u.fullName} — ${u.email}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedUser = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: (_busy || _selectedUser == null) ? null : _open,
                      child: const Text('Ouvrir le compte'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Comptes prépayés',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTheme.navy,
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_accounts.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aucun compte prépayé ouvert.'),
            ),
          )
        else
          ..._accounts.map((a) {
            final user = _userFor(a.userId);
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(user?.fullName ?? a.userId),
                subtitle: Text(
                  '${user?.email ?? ''}\nSolde : ${a.balance} passage(s)',
                ),
                isThreeLine: true,
                trailing: FilledButton(
                  onPressed: () => _recharge(a),
                  child: const Text('Recharger'),
                ),
              ),
            );
          }),
      ],
    );
  }
}
