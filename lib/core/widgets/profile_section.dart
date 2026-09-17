import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../theme/app_theme.dart';

class ProfileSection extends StatefulWidget {
  const ProfileSection({super.key, required this.authService, this.onSaved});

  final AuthService authService;
  final VoidCallback? onSaved;

  @override
  State<ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends State<ProfileSection> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _prenom;
  late final TextEditingController _nom;
  late final TextEditingController _email;
  late final TextEditingController _telephone;
  final _password = TextEditingController();
  bool _saving = false;
  bool _showPassword = false;

  RoadUser get _user => widget.authService.currentUser!;

  @override
  void initState() {
    super.initState();
    _prenom = TextEditingController(text: _user.prenom);
    _nom = TextEditingController(text: _user.nom);
    _email = TextEditingController(text: _user.email);
    _telephone = TextEditingController(text: _user.telephone);
  }

  @override
  void dispose() {
    _prenom.dispose();
    _nom.dispose();
    _email.dispose();
    _telephone.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? 'Ce champ est obligatoire.'
      : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.authService.updateProfile(
        nom: _nom.text,
        prenom: _prenom.text,
        email: _email.text,
        telephone: _telephone.text,
        password: _password.text.isEmpty ? null : _password.text,
      );
      if (!mounted) return;
      _password.clear();
      setState(() {});
      widget.onSaved?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Votre profil a été mis à jour.')),
      );
    } on RoadPassAuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La mise à jour du profil a échoué.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _roleLabel => switch (_user.role) {
    UserRole.user => 'Utilisateur',
    UserRole.agent => 'Agent de péage',
    UserRole.admin => 'Administrateur',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: AppTheme.navy,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white24,
                  child: Text(
                    _user.prenom.isEmpty ? '?' : _user.prenom[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _user.fullName,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _user.email,
                        style: const TextStyle(color: Color(0xFFD5E7F4)),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(_roleLabel),
                  avatar: const Icon(Icons.verified_user_outlined, size: 18),
                  backgroundColor: Colors.white,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Informations personnelles',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Gardez vos coordonnées à jour pour sécuriser votre compte.',
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Un changement d’e-mail peut demander une confirmation par e-mail.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final fields = [
                        TextFormField(
                          controller: _prenom,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(labelText: 'Prénom'),
                          validator: _required,
                        ),
                        TextFormField(
                          controller: _nom,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(labelText: 'Nom'),
                          validator: _required,
                        ),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Adresse e-mail'),
                          validator: (value) => value == null || !value.contains('@')
                              ? 'Saisissez une adresse e-mail valide.'
                              : null,
                        ),
                        TextFormField(
                          controller: _telephone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(labelText: 'Téléphone'),
                          validator: _required,
                        ),
                      ];
                      if (constraints.maxWidth < 620) {
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
                            .map((field) => SizedBox(width: 320, child: field))
                            .toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'Sécurité',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: !_showPassword,
                    decoration: InputDecoration(
                      labelText: 'Nouveau mot de passe (facultatif)',
                      helperText: 'Laissez vide pour conserver votre mot de passe actuel.',
                      suffixIcon: IconButton(
                        tooltip: _showPassword ? 'Masquer le mot de passe' : 'Afficher le mot de passe',
                        onPressed: () => setState(() => _showPassword = !_showPassword),
                        icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                      ),
                    ),
                    validator: (value) => value != null && value.isNotEmpty && value.length < 8
                        ? 'Le mot de passe doit contenir au moins 8 caractères.'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 240,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('Enregistrer les modifications'),
                    ),
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
