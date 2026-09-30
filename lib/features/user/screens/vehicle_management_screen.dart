import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/vehicle.dart';
import '../../../models/vehicle_category.dart';
import '../../../services/auth_service.dart';
import '../../../services/toll_catalog_service.dart';
import '../../../services/vehicle_service.dart';

class VehicleManagementScreen extends StatefulWidget {
  const VehicleManagementScreen({
    super.key,
    required this.authService,
    required this.vehicleService,
    required this.catalogService,
  });

  final AuthService authService;
  final VehicleServiceBase vehicleService;
  final TollCatalogServiceBase catalogService;

  @override
  State<VehicleManagementScreen> createState() =>
      _VehicleManagementScreenState();
}

class _VehicleManagementScreenState extends State<VehicleManagementScreen> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<Vehicle> _vehicles = const [];
  List<VehicleCategory> _categories = const [];
  Vehicle? _editingVehicle;
  VehicleCategory? _selectedCategory;

  final _formKey = GlobalKey<FormState>();
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _registrationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _brandController.dispose();
    _modelController.dispose();
    _registrationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        widget.vehicleService.getMyVehicles(),
        widget.catalogService.getVehicleCategories(),
      ]);
      if (!mounted) return;
      setState(() {
        _vehicles = results[0] as List<Vehicle>;
        _categories = results[1] as List<VehicleCategory>;
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

  bool get _isAuthenticated => widget.authService.currentUser != null;

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isAuthenticated) {
      setState(() => _error = 'Utilisateur non authentifié.');
      return;
    }
    final category = _selectedCategory;
    if (category == null) {
      setState(() => _error = 'Sélectionnez une catégorie de véhicule.');
      return;
    }

    setState(() => _submitting = true);
    try {
      if (_editingVehicle == null) {
        await widget.vehicleService.createVehicle(
          brand: _brandController.text,
          model: _modelController.text,
          registrationNumber: _registrationController.text,
          category: category,
        );
      } else {
        await widget.vehicleService.updateVehicle(
          _editingVehicle!.id,
          brand: _brandController.text,
          model: _modelController.text,
          registrationNumber: _registrationController.text,
          category: category,
        );
      }
      _resetForm();
      await _loadData();
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _deactivateVehicle(Vehicle vehicle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Désactiver ce véhicule ?'),
        content: Text(
          'Le véhicule ${vehicle.brand} ${vehicle.model} ne sera plus affiché comme actif.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Désactiver'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _submitting = true);
    try {
      await widget.vehicleService.deactivateVehicle(vehicle.id);
      await _loadData();
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _resetForm() {
    _editingVehicle = null;
    _brandController.clear();
    _modelController.clear();
    _registrationController.clear();
    _selectedCategory = null;
    _error = null;
    if (mounted) {
      setState(() {});
    }
  }

  void _fillForm(Vehicle vehicle) {
    _editingVehicle = vehicle;
    _brandController.text = vehicle.brand;
    _modelController.text = vehicle.model;
    _registrationController.text = vehicle.registrationNumber;
    _selectedCategory = _categories
        .where((category) => category.id == vehicle.categoryId)
        .cast<VehicleCategory?>()
        .firstWhere((_) => true, orElse: () => null);
    setState(() {});
  }

  String _categoryLabelFor(Vehicle vehicle) {
    final match = _categories
        .where((category) => category.id == vehicle.categoryId)
        .cast<VehicleCategory?>()
        .firstWhere((_) => true, orElse: () => null);
    return match?.name ?? vehicle.category;
  }

  @override
  Widget build(BuildContext context) {
    final activeVehicles = _vehicles
        .where((vehicle) => vehicle.isActive)
        .toList();
    final inactiveVehicles = _vehicles
        .where((vehicle) => !vehicle.isActive)
        .toList();

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
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _editingVehicle == null
                            ? 'Ajouter un véhicule'
                            : 'Modifier le véhicule',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.navy,
                        ),
                      ),
                      const Spacer(),
                      if (_editingVehicle != null)
                        TextButton.icon(
                          onPressed: _resetForm,
                          icon: const Icon(Icons.close),
                          label: const Text('Annuler'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _brandController,
                          decoration: const InputDecoration(
                            labelText: 'Marque',
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? 'La marque est obligatoire.'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _modelController,
                          decoration: const InputDecoration(
                            labelText: 'Modèle',
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? 'Le modèle est obligatoire.'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _registrationController,
                          decoration: const InputDecoration(
                            labelText: 'Immatriculation',
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? 'L’immatriculation est obligatoire.'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<VehicleCategory>(
                          initialValue: _selectedCategory,
                          decoration: const InputDecoration(
                            labelText: 'Catégorie',
                            helperText:
                                'Détermine le tarif de péage applicable.',
                          ),
                          isExpanded: true,
                          items: _categories
                              .map(
                                (category) => DropdownMenuItem(
                                  value: category,
                                  child: Text(
                                    '${category.code} — ${category.name}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _selectedCategory = value),
                          validator: (value) =>
                              value == null ? 'Choisissez une catégorie.' : null,
                        ),
                      ),
                    ],
                  ),
                  if (_selectedCategory != null &&
                      _selectedCategory!.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _selectedCategory!.description,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _submitForm,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add),
                      label: Text(
                        _editingVehicle == null ? 'Ajouter' : 'Enregistrer',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_vehicles.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const Icon(
                    Icons.directions_car_outlined,
                    size: 48,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Vous n’avez encore aucun véhicule.',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ajoutez votre premier véhicule pour commencer.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          )
        else ...[
          if (activeVehicles.isNotEmpty) ...[
            _sectionTitle('Véhicules actifs'),
            const SizedBox(height: 12),
            ...activeVehicles.map(_vehicleCard),
          ],
          if (inactiveVehicles.isNotEmpty) ...[
            const SizedBox(height: 24),
            _sectionTitle('Véhicules désactivés'),
            const SizedBox(height: 12),
            ...inactiveVehicles.map(_vehicleCard),
          ],
        ],
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppTheme.navy,
      ),
    );
  }

  Widget _vehicleCard(Vehicle vehicle) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.skyBlue.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.directions_car_outlined, color: AppTheme.navy),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${vehicle.brand} ${vehicle.model}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('Immatriculation : ${vehicle.registrationNumber}'),
                  const SizedBox(height: 4),
                  Text('Catégorie : ${_categoryLabelFor(vehicle)}'),
                  const SizedBox(height: 4),
                  Text(
                    'Statut : ${vehicle.isActive ? 'Actif' : 'Désactivé'}',
                    style: TextStyle(
                      color: vehicle.isActive
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                TextButton.icon(
                  onPressed: () => _fillForm(vehicle),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifier'),
                ),
                if (vehicle.isActive)
                  TextButton.icon(
                    onPressed: () => _deactivateVehicle(vehicle),
                    icon: const Icon(Icons.block_outlined),
                    label: const Text('Désactiver'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}