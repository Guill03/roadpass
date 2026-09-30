import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/vehicle.dart';
import '../models/vehicle_category.dart';

class VehicleServiceException implements Exception {
  const VehicleServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class VehicleServiceBase {
  Future<List<Vehicle>> getMyVehicles();
  Future<Vehicle> getVehicle(String id);
  Future<Vehicle> createVehicle({
    required String brand,
    required String model,
    required String registrationNumber,
    required VehicleCategory category,
  });
  Future<Vehicle> updateVehicle(
    String id, {
    String? brand,
    String? model,
    String? registrationNumber,
    VehicleCategory? category,
  });
  Future<Vehicle> deactivateVehicle(String id);
}

class VehicleService extends VehicleServiceBase {
  VehicleService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<Vehicle>> getMyVehicles() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const VehicleServiceException('Utilisateur non authentifié.');
    }

    try {
      final response = await _client
          .from('vehicles')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final data = response as List<dynamic>;
      return data
          .map((item) => Vehicle.fromMap(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (error) {
      throw VehicleServiceException(
        'Impossible de récupérer vos véhicules : ${error.message}',
      );
    } on VehicleServiceException {
      rethrow;
    } catch (_) {
      throw const VehicleServiceException(
        'Impossible de récupérer vos véhicules. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<Vehicle> getVehicle(String id) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const VehicleServiceException('Utilisateur non authentifié.');
    }

    try {
      final response = await _client
          .from('vehicles')
          .select()
          .eq('id', id)
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        throw const VehicleServiceException('Véhicule introuvable.');
      }
      return Vehicle.fromMap(response);
    } on PostgrestException catch (error) {
      throw VehicleServiceException(
        'Impossible de charger le véhicule : ${error.message}',
      );
    } on VehicleServiceException {
      rethrow;
    } catch (_) {
      throw const VehicleServiceException(
        'Impossible de charger le véhicule. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<Vehicle> createVehicle({
    required String brand,
    required String model,
    required String registrationNumber,
    required VehicleCategory category,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const VehicleServiceException('Utilisateur non authentifié.');
    }

    final sanitizedBrand = brand.trim();
    final sanitizedModel = model.trim();
    final sanitizedRegistrationNumber = registrationNumber.trim();

    if (sanitizedBrand.isEmpty ||
        sanitizedModel.isEmpty ||
        sanitizedRegistrationNumber.isEmpty) {
      throw const VehicleServiceException('Tous les champs sont obligatoires.');
    }

    try {
      final response = await _client
          .from('vehicles')
          .insert({
            // user_id doit venir de la session authentifiée, jamais d'un
            // paramètre de la méthode : c'est ce que la RLS (with check
            // user_id = auth.uid()) attend et vérifie de son côté.
            'user_id': userId,
            'brand': sanitizedBrand,
            'model': sanitizedModel,
            'registration_number': sanitizedRegistrationNumber,
            // 'category' (texte) est conservé pour compatibilité avec la
            // contrainte NOT NULL existante ; category_id (Bloc C) est la
            // source de vérité pour le calcul des tarifs.
            'category': category.name,
            'category_id': category.id,
            'is_active': true,
          })
          .select()
          .single();

      return Vehicle.fromMap(response);
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const VehicleServiceException(
          'Cette immatriculation est déjà enregistrée.',
        );
      }
      throw VehicleServiceException(
        'La création du véhicule a échoué : ${error.message}',
      );
    } on VehicleServiceException {
      rethrow;
    } catch (_) {
      throw const VehicleServiceException(
        'La création du véhicule a échoué. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<Vehicle> updateVehicle(
    String id, {
    String? brand,
    String? model,
    String? registrationNumber,
    VehicleCategory? category,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const VehicleServiceException('Utilisateur non authentifié.');
    }

    final current = await getVehicle(id);
    final next = current.copyWith(
      brand: brand?.trim() ?? current.brand,
      model: model?.trim() ?? current.model,
      registrationNumber:
          registrationNumber?.trim() ?? current.registrationNumber,
      category: category?.name ?? current.category,
      categoryId: category?.id ?? current.categoryId,
      updatedAt: DateTime.now(),
    );

    if (next.brand.isEmpty ||
        next.model.isEmpty ||
        next.registrationNumber.isEmpty) {
      throw const VehicleServiceException(
        'Les informations du véhicule sont incomplètes.',
      );
    }

    try {
      final response = await _client
          .from('vehicles')
          .update({
            'brand': next.brand,
            'model': next.model,
            'registration_number': next.registrationNumber,
            'category': next.category,
            'category_id': next.categoryId,
            'updated_at': next.updatedAt.toUtc().toIso8601String(),
          })
          .eq('id', id)
          .eq('user_id', userId)
          .select()
          .single();

      return Vehicle.fromMap(response);
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const VehicleServiceException(
          'Cette immatriculation est déjà enregistrée.',
        );
      }
      throw VehicleServiceException(
        'La modification du véhicule a échoué : ${error.message}',
      );
    } on VehicleServiceException {
      rethrow;
    } catch (_) {
      throw const VehicleServiceException(
        'La modification du véhicule a échoué. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<Vehicle> deactivateVehicle(String id) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const VehicleServiceException('Utilisateur non authentifié.');
    }

    final current = await getVehicle(id);

    try {
      final response = await _client
          .from('vehicles')
          .update({
            'is_active': false,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id)
          .eq('user_id', userId)
          .select()
          .single();

      return Vehicle.fromMap(response);
    } on PostgrestException catch (error) {
      throw VehicleServiceException(
        'La désactivation a échoué : ${error.message}',
      );
    } on VehicleServiceException {
      rethrow;
    } catch (_) {
      throw const VehicleServiceException(
        'La désactivation a échoué. Vérifiez votre connexion.',
      );
    }
  }
}