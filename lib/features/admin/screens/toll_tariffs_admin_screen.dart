import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/toll_post.dart';
import '../../../models/toll_tariff.dart';
import '../../../models/vehicle_category.dart';
import '../../../services/toll_catalog_service.dart';

class TollTariffsAdminScreen extends StatefulWidget {
  const TollTariffsAdminScreen({super.key, required this.catalogService});

  final TollCatalogServiceBase catalogService;

  @override
  State<TollTariffsAdminScreen> createState() =>
      _TollTariffsAdminScreenState();
}

class _TollTariffsAdminScreenState extends State<TollTariffsAdminScreen> {
  bool _loading = true;
  String? _error;

  List<TollPost> _posts = const [];
  List<VehicleCategory> _categories = const [];
  List<TollTariff> _tariffs = const [];
  TollPost? _selectedPost;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.catalogService.getTollPosts(includeInactive: true),
        widget.catalogService.getVehicleCategories(includeInactive: true),
      ]);
      final posts = results[0] as List<TollPost>;
      final categories = results[1] as List<VehicleCategory>;
      _selectedPost ??= posts.isNotEmpty ? posts.first : null;
      final tariffs = _selectedPost != null
          ? await widget.catalogService.getTariffsForPost(_selectedPost!.id)
          : const <TollTariff>[];
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _categories = categories;
        _tariffs = tariffs;
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

  Future<void> _loadTariffsForSelectedPost() async {
    if (_selectedPost == null) return;
    setState(() => _loading = true);
    try {
      final tariffs =
          await widget.catalogService.getTariffsForPost(_selectedPost!.id);
      if (!mounted) return;
      setState(() {
        _tariffs = tariffs;
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

  String _categoryName(String categoryId) {
    final match = _categories
        .where((category) => category.id == categoryId)
        .cast<VehicleCategory?>()
        .firstWhere((_) => true, orElse: () => null);
    return match?.name ?? categoryId;
  }

  Future<void> _endTariff(TollTariff tariff) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clôturer ce tarif ?'),
        content: const Text(
          'Le tarif ne sera plus applicable à partir de maintenant. '
          'Il reste consultable dans l’historique.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.catalogService.endTariffValidity(
        tariff.id,
        validUntil: DateTime.now(),
      );
      await _loadTariffsForSelectedPost();
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _posts.isEmpty) {
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
        _CategoriesPanel(
          catalogService: widget.catalogService,
          categories: _categories,
          onChanged: _loadAll,
        ),
        const SizedBox(height: 24),
        Text(
          'Tarifs',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTheme.navy,
          ),
        ),
        const SizedBox(height: 12),
        if (_posts.isEmpty)
          const Text('Créez d’abord un poste de péage.')
        else ...[
          DropdownButtonFormField<TollPost>(
            initialValue: _selectedPost,
            decoration: const InputDecoration(labelText: 'Poste de péage'),
            items: _posts
                .map(
                  (post) => DropdownMenuItem(
                    value: post,
                    child: Text('${post.code} — ${post.name}'),
                  ),
                )
                .toList(),
            onChanged: (post) {
              setState(() => _selectedPost = post);
              _loadTariffsForSelectedPost();
            },
          ),
          const SizedBox(height: 16),
          if (_categories.isEmpty)
            const Text('Créez d’abord au moins une catégorie de véhicule.')
          else if (_selectedPost != null)
            _CreateTariffForm(
              catalogService: widget.catalogService,
              tollPostId: _selectedPost!.id,
              categories: _categories,
              onCreated: _loadTariffsForSelectedPost,
              onError: (message) => setState(() => _error = message),
            ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_tariffs.isEmpty)
            const Text('Aucun tarif pour ce poste.')
          else
            ..._tariffs.map(
              (tariff) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(
                    '${_categoryName(tariff.categoryId)} — '
                    '${tariff.tripType == TripType.longueDistance ? 'Longue distance' : 'Demi-trajet'}',
                  ),
                  subtitle: Text(
                    '${tariff.amount.toStringAsFixed(2)} ${tariff.currency}   '
                    'Valide depuis ${_formatDate(tariff.validFrom)}'
                    '${tariff.validUntil != null ? ' jusqu\'au ${_formatDate(tariff.validUntil!)}' : ''}',
                  ),
                  trailing: tariff.validUntil == null
                      ? TextButton(
                          onPressed: () => _endTariff(tariff),
                          child: const Text('Clôturer'),
                        )
                      : const Chip(label: Text('Historique')),
                ),
              ),
            ),
        ],
      ],
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _CategoriesPanel extends StatefulWidget {
  const _CategoriesPanel({
    required this.catalogService,
    required this.categories,
    required this.onChanged,
  });

  final TollCatalogServiceBase catalogService;
  final List<VehicleCategory> categories;
  final VoidCallback onChanged;

  @override
  State<_CategoriesPanel> createState() => _CategoriesPanelState();
}

class _CategoriesPanelState extends State<_CategoriesPanel> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  VehicleCategory? _editing;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _resetForm() {
    _editing = null;
    _codeController.clear();
    _nameController.clear();
    _descriptionController.clear();
    if (mounted) setState(() {});
  }

  void _fillForm(VehicleCategory category) {
    _editing = category;
    _codeController.text = category.code;
    _nameController.text = category.name;
    _descriptionController.text = category.description;
    setState(() {});
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      if (_editing == null) {
        await widget.catalogService.createVehicleCategory(
          code: _codeController.text,
          name: _nameController.text,
          description: _descriptionController.text,
        );
      } else {
        await widget.catalogService.updateVehicleCategory(
          _editing!.id,
          code: _codeController.text,
          name: _nameController.text,
          description: _descriptionController.text,
        );
      }
      _resetForm();
      widget.onChanged();
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Catégories de véhicules',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.navy,
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            Form(
              key: _formKey,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _codeController,
                      decoration: const InputDecoration(labelText: 'Code'),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Obligatoire.'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Nom'),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Obligatoire.'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Explication (affichée à l’utilisateur)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: Text(_editing == null ? 'Ajouter' : 'Enregistrer'),
                  ),
                  if (_editing != null)
                    TextButton(
                      onPressed: _resetForm,
                      child: const Text('Annuler'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...widget.categories.map(
              (category) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${category.code} — ${category.name}'),
                subtitle: category.description.isNotEmpty
                    ? Text(category.description)
                    : null,
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _fillForm(category),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateTariffForm extends StatefulWidget {
  const _CreateTariffForm({
    required this.catalogService,
    required this.tollPostId,
    required this.categories,
    required this.onCreated,
    required this.onError,
  });

  final TollCatalogServiceBase catalogService;
  final String tollPostId;
  final List<VehicleCategory> categories;
  final VoidCallback onCreated;
  final ValueChanged<String> onError;

  @override
  State<_CreateTariffForm> createState() => _CreateTariffFormState();
}

class _CreateTariffFormState extends State<_CreateTariffForm> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController(text: '0');
  final _currencyController = TextEditingController(text: 'USD');
  VehicleCategory? _category;
  TripType _tripType = TripType.longueDistance;
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_category == null) {
      widget.onError('Sélectionnez une catégorie.');
      return;
    }
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      widget.onError('Montant invalide.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.catalogService.createTariff(
        tollPostId: widget.tollPostId,
        categoryId: _category!.id,
        tripType: _tripType,
        amount: amount,
        currency: _currencyController.text,
      );
      widget.onCreated();
    } catch (error) {
      widget.onError(error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<VehicleCategory>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Catégorie'),
                  items: widget.categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category,
                          child: Text('${category.code} — ${category.name}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _category = value),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<TripType>(
                  initialValue: _tripType,
                  decoration: const InputDecoration(labelText: 'Type de trajet'),
                  items: const [
                    DropdownMenuItem(
                      value: TripType.longueDistance,
                      child: Text('Longue distance'),
                    ),
                    DropdownMenuItem(
                      value: TripType.demiTrajet,
                      child: Text('Demi-trajet'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _tripType = value ?? TripType.longueDistance),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Montant'),
                ),
              ),
              SizedBox(
                width: 100,
                child: TextFormField(
                  controller: _currencyController,
                  decoration: const InputDecoration(labelText: 'Devise'),
                ),
              ),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: const Text('Créer le tarif'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
