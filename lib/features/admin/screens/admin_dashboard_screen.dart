import 'package:flutter/material.dart';

import '../../../core/widgets/dashboard_shell.dart';
import '../../../services/admin_operations_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/toll_catalog_service.dart';
import 'exemptions_admin_screen.dart';
import 'prepaid_accounts_admin_screen.dart';
import 'toll_posts_admin_screen.dart';
import 'toll_tariffs_admin_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return DashboardShell(
      authService: authService,
      title: 'Espace administrateur',
      subtitle: 'Une vue structurée de la plateforme RoadPass.',
      contentBuilder: (context, section) {
        switch (section) {
          case 'Agents':
            return _CreateAgentPanel(authService: authService);
          case 'Postes de péage':
            return TollPostsAdminScreen(catalogService: TollCatalogService());
          case 'Tarifs':
            return TollTariffsAdminScreen(catalogService: TollCatalogService());
          case 'Exemptions':
            return ExemptionsAdminScreen(service: AdminOperationsService());
          case 'Comptes prépayés':
            return PrepaidAccountsAdminScreen(service: AdminOperationsService());
          default:
            return const SizedBox.shrink();
        }
      },
      items: const [
        DashboardItem('Tableau de bord', Icons.dashboard_outlined),
        DashboardItem('Utilisateurs', Icons.people_outline),
        DashboardItem('Agents', Icons.badge_outlined),
        DashboardItem('Postes de péage', Icons.location_on_outlined),
        DashboardItem('Tarifs', Icons.sell_outlined),
        DashboardItem('Exemptions', Icons.verified_outlined),
        DashboardItem('Comptes prépayés', Icons.account_balance_wallet_outlined),
        DashboardItem('Transactions', Icons.receipt_long_outlined),
        DashboardItem('Profil', Icons.person_outline),
        DashboardItem('Rapports / Statistiques', Icons.bar_chart_outlined),
        DashboardItem('Paramètres', Icons.settings_outlined),
      ],
    );
  }
}

class _CreateAgentPanel extends StatefulWidget {
  const _CreateAgentPanel({required this.authService});

  final AuthService authService;

  @override
  State<_CreateAgentPanel> createState() => _CreateAgentPanelState();
}

class _CreateAgentPanelState extends State<_CreateAgentPanel> {
  final _formKey = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  final _email = TextEditingController();
  final _telephone = TextEditingController();
  final _password = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  @override
  void dispose() {
    _nom.dispose();
    _prenom.dispose();
    _email.dispose();
    _telephone.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty
        ? 'Ce champ est obligatoire.'
        : null;
  }

  Future<void> _createAgent() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await widget.authService.createAgentAccount(
        nom: _nom.text,
        prenom: _prenom.text,
        email: _email.text,
        telephone: _telephone.text,
        password: _password.text,
      );
      if (!mounted) return;
      _formKey.currentState!.reset();
      _nom.clear();
      _prenom.clear();
      _email.clear();
      _telephone.clear();
      _password.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le compte agent a été créé.')),
      );
    } on RoadPassAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Création impossible : $error')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Créer un agent',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Le compte sera créé avec le rôle agent et pourra accéder à l’espace professionnel.',
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 620;
                  final fields = [
                    TextFormField(
                      controller: _prenom,
                      decoration: const InputDecoration(labelText: 'Prénom'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: _nom,
                      decoration: const InputDecoration(labelText: 'Nom'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'E-mail'),
                      validator: (value) =>
                          value == null || !value.contains('@')
                          ? 'Saisissez un e-mail valide.'
                          : null,
                    ),
                    TextFormField(
                      controller: _telephone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Téléphone'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: _password,
                      obscureText: _isPasswordVisible ? false : true,
                      decoration: InputDecoration(
                        labelText: 'Mot de passe temporaire',
                        suffixIcon: IconButton(
                          icon: _isPasswordVisible
                              ? Icon(Icons.visibility_off)
                              : Icon(Icons.visibility),
                          onPressed: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                        ),
                      ),
                      validator: (value) => value == null || value.length < 8
                          ? 'Minimum 8 caractères.'
                          : null,
                    ),
                  ];
                  if (compact) {
                    return Column(
                      children: [
                        for (final field in fields) ...[
                          field,
                          const SizedBox(height: 16),
                        ],
                      ],
                    );
                  }
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: fields
                        .map((field) => SizedBox(width: 280, child: field))
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 220,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _createAgent,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_alt_1),
                  label: const Text('Créer l’agent'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
