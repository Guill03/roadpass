import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/toll_post.dart';
import '../models/toll_tariff.dart';
import '../models/vehicle_category.dart';

class TollCatalogServiceException implements Exception {
  const TollCatalogServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Un seul service pour les trois entités du Bloc C : elles se consultent
/// et se combinent toujours ensemble (poste + catégorie + trajet -> tarif),
/// séparer en trois services n'apporterait rien ici.
///
/// Les écritures (create*/end*) sont protégées côté serveur par la RLS
/// (réservées à is_admin()) : les exposer ici ne rend pas l'écran qui les
/// appelle "sûr" en soi, c'est Postgres qui refuse la requête si l'appelant
/// n'est pas administrateur.
abstract class TollCatalogServiceBase {
  Future<List<TollPost>> getTollPosts({bool includeInactive = false});
  Future<List<VehicleCategory>> getVehicleCategories({
    bool includeInactive = false,
  });
  Future<List<TollTariff>> getTariffsForPost(String tollPostId);

  /// Retourne le tarif applicable pour [tollPostId] + [categoryId] +
  /// [tripType] à l'instant [at], en se basant uniquement sur les périodes
  /// de validité — jamais sur "le dernier tarif créé".
  Future<TollTariff?> findApplicableTariff({
    required String tollPostId,
    required String categoryId,
    required TripType tripType,
    required DateTime at,
  });

  Future<TollPost> createTollPost({
    required String code,
    required String name,
    required String location,
  });

  Future<TollPost> updateTollPost(
    String id, {
    String? code,
    String? name,
    String? location,
    bool? isActive,
  });

  Future<VehicleCategory> createVehicleCategory({
    required String code,
    required String name,
    required String description,
  });

  Future<VehicleCategory> updateVehicleCategory(
    String id, {
    String? code,
    String? name,
    String? description,
    bool? isActive,
  });

  /// Crée un nouveau tarif. Ne modifie jamais un tarif existant : la
  /// contrainte d'exclusion en base refuse toute période qui chevaucherait
  /// un tarif déjà actif pour la même combinaison poste/catégorie/trajet.
  Future<TollTariff> createTariff({
    required String tollPostId,
    required String categoryId,
    required TripType tripType,
    required double amount,
    required String currency,
    DateTime? validFrom,
  });

  /// Clôt un tarif (fin de validité) au lieu de le supprimer, pour
  /// préserver l'historique tarifaire (section 8/12 du cahier du Bloc C).
  Future<TollTariff> endTariffValidity(
    String id, {
    required DateTime validUntil,
  });
}

class TollCatalogService extends TollCatalogServiceBase {
  TollCatalogService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<TollPost>> getTollPosts({bool includeInactive = false}) async {
    try {
      var query = _client.from('toll_posts').select();
      if (!includeInactive) {
        query = query.eq('is_active', true);
      }
      final response = await query.order('name');

      return (response as List<dynamic>)
          .map((item) => TollPost.fromMap(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (error) {
      throw TollCatalogServiceException(
        'Impossible de récupérer les postes de péage : ${error.message}',
      );
    } catch (_) {
      throw const TollCatalogServiceException(
        'Impossible de récupérer les postes de péage. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<List<VehicleCategory>> getVehicleCategories({
    bool includeInactive = false,
  }) async {
    try {
      var query = _client.from('vehicle_categories').select();
      if (!includeInactive) {
        query = query.eq('is_active', true);
      }
      final response = await query.order('name');

      return (response as List<dynamic>)
          .map((item) => VehicleCategory.fromMap(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (error) {
      throw TollCatalogServiceException(
        'Impossible de récupérer les catégories : ${error.message}',
      );
    } catch (_) {
      throw const TollCatalogServiceException(
        'Impossible de récupérer les catégories. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<List<TollTariff>> getTariffsForPost(String tollPostId) async {
    try {
      final response = await _client
          .from('toll_tariffs')
          .select()
          .eq('toll_post_id', tollPostId)
          .order('valid_from', ascending: false);

      return (response as List<dynamic>)
          .map((item) => TollTariff.fromMap(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (error) {
      throw TollCatalogServiceException(
        'Impossible de récupérer les tarifs : ${error.message}',
      );
    } catch (_) {
      throw const TollCatalogServiceException(
        'Impossible de récupérer les tarifs. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<TollTariff?> findApplicableTariff({
    required String tollPostId,
    required String categoryId,
    required TripType tripType,
    required DateTime at,
  }) async {
    try {
      final isoAt = at.toUtc().toIso8601String();
      final response = await _client
          .from('toll_tariffs')
          .select()
          .eq('toll_post_id', tollPostId)
          .eq('category_id', categoryId)
          .eq('trip_type', tripType.value)
          .lte('valid_from', isoAt)
          .or('valid_until.is.null,valid_until.gt.$isoAt')
          .order('valid_from', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      return TollTariff.fromMap(response);
    } on PostgrestException catch (error) {
      throw TollCatalogServiceException(
        'Impossible de déterminer le tarif applicable : ${error.message}',
      );
    } catch (_) {
      throw const TollCatalogServiceException(
        'Impossible de déterminer le tarif applicable. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<TollPost> createTollPost({
    required String code,
    required String name,
    required String location,
  }) async {
    final sanitizedCode = code.trim();
    final sanitizedName = name.trim();
    final sanitizedLocation = location.trim();
    if (sanitizedCode.isEmpty || sanitizedName.isEmpty || sanitizedLocation.isEmpty) {
      throw const TollCatalogServiceException('Tous les champs sont obligatoires.');
    }
    try {
      final response = await _client
          .from('toll_posts')
          .insert({
            'code': sanitizedCode,
            'name': sanitizedName,
            'location': sanitizedLocation,
          })
          .select()
          .single();
      return TollPost.fromMap(response);
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const TollCatalogServiceException('Ce code de poste existe déjà.');
      }
      throw TollCatalogServiceException(
        'La création du poste a échoué : ${error.message}',
      );
    } on TollCatalogServiceException {
      rethrow;
    } catch (_) {
      throw const TollCatalogServiceException(
        'La création du poste a échoué. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<TollPost> updateTollPost(
    String id, {
    String? code,
    String? name,
    String? location,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{};
    if (code != null) updates['code'] = code.trim();
    if (name != null) updates['name'] = name.trim();
    if (location != null) updates['location'] = location.trim();
    if (isActive != null) updates['is_active'] = isActive;
    if (updates.isEmpty) {
      throw const TollCatalogServiceException('Aucune modification fournie.');
    }
    try {
      final response = await _client
          .from('toll_posts')
          .update(updates)
          .eq('id', id)
          .select()
          .single();
      return TollPost.fromMap(response);
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const TollCatalogServiceException('Ce code de poste existe déjà.');
      }
      throw TollCatalogServiceException(
        'La modification du poste a échoué : ${error.message}',
      );
    } on TollCatalogServiceException {
      rethrow;
    } catch (_) {
      throw const TollCatalogServiceException(
        'La modification du poste a échoué. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<VehicleCategory> createVehicleCategory({
    required String code,
    required String name,
    required String description,
  }) async {
    final sanitizedCode = code.trim();
    final sanitizedName = name.trim();
    if (sanitizedCode.isEmpty || sanitizedName.isEmpty) {
      throw const TollCatalogServiceException(
        'Le code et le nom sont obligatoires.',
      );
    }
    try {
      final response = await _client
          .from('vehicle_categories')
          .insert({
            'code': sanitizedCode,
            'name': sanitizedName,
            'description': description.trim(),
          })
          .select()
          .single();
      return VehicleCategory.fromMap(response);
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const TollCatalogServiceException(
          'Ce code de catégorie existe déjà.',
        );
      }
      throw TollCatalogServiceException(
        'La création de la catégorie a échoué : ${error.message}',
      );
    } on TollCatalogServiceException {
      rethrow;
    } catch (_) {
      throw const TollCatalogServiceException(
        'La création de la catégorie a échoué. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<VehicleCategory> updateVehicleCategory(
    String id, {
    String? code,
    String? name,
    String? description,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{};
    if (code != null) updates['code'] = code.trim();
    if (name != null) updates['name'] = name.trim();
    if (description != null) updates['description'] = description.trim();
    if (isActive != null) updates['is_active'] = isActive;
    if (updates.isEmpty) {
      throw const TollCatalogServiceException('Aucune modification fournie.');
    }
    try {
      final response = await _client
          .from('vehicle_categories')
          .update(updates)
          .eq('id', id)
          .select()
          .single();
      return VehicleCategory.fromMap(response);
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const TollCatalogServiceException(
          'Ce code de catégorie existe déjà.',
        );
      }
      throw TollCatalogServiceException(
        'La modification de la catégorie a échoué : ${error.message}',
      );
    } on TollCatalogServiceException {
      rethrow;
    } catch (_) {
      throw const TollCatalogServiceException(
        'La modification de la catégorie a échoué. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<TollTariff> createTariff({
    required String tollPostId,
    required String categoryId,
    required TripType tripType,
    required double amount,
    required String currency,
    DateTime? validFrom,
  }) async {
    if (amount <= 0) {
      throw const TollCatalogServiceException('Le montant doit être positif.');
    }
    try {
      final response = await _client
          .from('toll_tariffs')
          .insert({
            'toll_post_id': tollPostId,
            'category_id': categoryId,
            'trip_type': tripType.value,
            'amount': amount,
            'currency': currency.trim().isEmpty ? 'USD' : currency.trim(),
            'valid_from': (validFrom ?? DateTime.now()).toUtc().toIso8601String(),
          })
          .select()
          .single();
      return TollTariff.fromMap(response);
    } on PostgrestException catch (error) {
      if (error.code == '23P01') {
        // Violation de la contrainte d'exclusion : chevauchement de périodes.
        throw const TollCatalogServiceException(
          'Un tarif actif existe déjà pour cette combinaison poste/catégorie/trajet '
          'sur cette période. Clôturez d’abord le tarif existant.',
        );
      }
      throw TollCatalogServiceException(
        'La création du tarif a échoué : ${error.message}',
      );
    } on TollCatalogServiceException {
      rethrow;
    } catch (_) {
      throw const TollCatalogServiceException(
        'La création du tarif a échoué. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<TollTariff> endTariffValidity(
    String id, {
    required DateTime validUntil,
  }) async {
    try {
      final response = await _client
          .from('toll_tariffs')
          .update({'valid_until': validUntil.toUtc().toIso8601String()})
          .eq('id', id)
          .select()
          .single();
      return TollTariff.fromMap(response);
    } on PostgrestException catch (error) {
      throw TollCatalogServiceException(
        'La clôture du tarif a échoué : ${error.message}',
      );
    } catch (_) {
      throw const TollCatalogServiceException(
        'La clôture du tarif a échoué. Vérifiez votre connexion.',
      );
    }
  }
}