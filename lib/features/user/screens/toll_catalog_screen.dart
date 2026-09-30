import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/toll_post.dart';
import '../../../models/toll_tariff.dart';
import '../../../models/vehicle_category.dart';
import '../../../services/toll_catalog_service.dart';

/// Consultation des postes de péage, catégories et tarifs (Bloc C).
/// Lecture seule : aucune écriture n'est possible depuis cet écran.
class TollCatalogScreen extends StatefulWidget {
  const TollCatalogScreen({super.key, required this.catalogService});

  final TollCatalogServiceBase catalogService;

  @override
  State<TollCatalogScreen> createState() => _TollCatalogScreenState();
}

class _TollCatalogScreenState extends State<TollCatalogScreen> {
  bool _loading = true;
  String? _error;
  List<TollPost> _posts = const [];
  List<VehicleCategory> _categories = const [];
  List<TollTariff> _tariffs = const [];
  TollPost? _selectedPost;

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
        widget.catalogService.getTollPosts(),
        widget.catalogService.getVehicleCategories(),
      ]);
      final posts = results[0] as List<TollPost>;
      final categories = results[1] as List<VehicleCategory>;
      final selected = posts.isNotEmpty ? posts.first : null;
      final tariffs = selected != null
          ? await widget.catalogService.getTariffsForPost(selected.id)
          : const <TollTariff>[];
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _categories = categories;
        _selectedPost = selected;
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

  Future<void> _selectPost(TollPost post) async {
    setState(() {
      _selectedPost = post;
      _loading = true;
    });
    try {
      final tariffs = await widget.catalogService.getTariffsForPost(post.id);
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
    return match?.name ?? 'Catégorie inconnue';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _posts.isEmpty && _error == null) {
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
        if (_posts.isEmpty && !_loading)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Aucun poste de péage n’est encore disponible.',
              ),
            ),
          )
        else ...[
          Text(
            'Postes de péage',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 12),
          ..._posts.map(
            (post) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: _selectedPost?.id == post.id
                  ? AppTheme.skyBlue.withAlpha(20)
                  : null,
              child: ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(post.name),
                subtitle: Text(post.location),
                onTap: () => _selectPost(post),
                trailing: _selectedPost?.id == post.id
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Catégories de véhicules',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 12),
          if (_categories.isEmpty)
            const Text('Les catégories ne sont pas encore disponibles.')
          else
            Card(
              child: Column(
                children: _categories
                    .map(
                      (category) => ListTile(
                        title: Text('${category.code} — ${category.name}'),
                        subtitle: category.description.isNotEmpty
                            ? Text(category.description)
                            : null,
                      ),
                    )
                    .toList(),)
            ),
          const SizedBox(height: 24),
          Text(
            'Tarifs${_selectedPost != null ? ' — ${_selectedPost!.name}' : ''}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_tariffs.where((t) => t.validUntil == null).isEmpty)
            const Text(
              'Aucun tarif actuellement en vigueur pour ce poste.',
            )
          else
            Card(
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(1),
                },
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: Color(0xFFF2F5F8)),
                    children: [
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Catégorie', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Type de trajet', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Montant', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  for (final tariff in _tariffs.where((t) => t.validUntil == null))
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_categoryName(tariff.categoryId)),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            tariff.tripType == TripType.longueDistance
                                ? 'Longue distance'
                                : 'Demi-trajet',
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '${tariff.amount.toStringAsFixed(2)} ${tariff.currency}',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}