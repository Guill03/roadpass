import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/exemption.dart';
import '../models/prepaid_account.dart';

class AdminOperationsException implements Exception {
  const AdminOperationsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Un utilisateur tel que l'administrateur le voit (liste pour ouvrir un
/// compte prépayé). Le rôle administrateur est vérifié par la base.
class AdminUserSummary {
  const AdminUserSummary({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
  });

  final String id;
  final String fullName;
  final String email;
  final String role;
}

abstract class AdminOperationsServiceBase {
  Future<FoundVehicle> findVehicle(String registrationNumber);
  Future<List<Exemption>> listExemptions();
  Future<void> createExemption({
    required String vehicleId,
    required String reason,
    DateTime? validUntil,
  });
  Future<void> endExemption(String exemptionId);

  Future<List<AdminUserSummary>> listUsers();
  Future<List<PrepaidAccount>> listPrepaidAccounts();
  Future<void> openPrepaidAccount(String userId);
  Future<void> rechargePrepaidAccount(String accountId, int quantity);
}

class AdminOperationsService extends AdminOperationsServiceBase {
  AdminOperationsService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<T> _guard<T>(String failure, Future<T> Function() action) async {
    if (_client.auth.currentUser == null) {
      throw const AdminOperationsException('Utilisateur non authentifié.');
    }
    try {
      return await action();
    } on PostgrestException catch (error) {
      throw AdminOperationsException(error.message);
    } on AdminOperationsException {
      rethrow;
    } catch (_) {
      throw AdminOperationsException('$failure Vérifiez votre connexion.');
    }
  }

  @override
  Future<FoundVehicle> findVehicle(String registrationNumber) =>
      _guard('Recherche impossible.', () async {
        final data = await _client.rpc(
          'admin_find_vehicle',
          params: {'p_registration_number': registrationNumber.trim()},
        );
        if (data is! Map<String, dynamic>) {
          throw const AdminOperationsException('Réponse inattendue.');
        }
        return FoundVehicle.fromMap(data);
      });

  @override
  Future<List<Exemption>> listExemptions() =>
      _guard('Chargement impossible.', () async {
        final data = await _client.rpc('admin_list_exemptions');
        return (data as List<dynamic>)
            .map((item) => Exemption.fromMap(item as Map<String, dynamic>))
            .toList();
      });

  @override
  Future<void> createExemption({
    required String vehicleId,
    required String reason,
    DateTime? validUntil,
  }) => _guard('Création impossible.', () async {
    await _client.rpc(
      'admin_create_exemption',
      params: {
        'p_vehicle_id': vehicleId,
        'p_reason': reason,
        'p_valid_until': validUntil?.toUtc().toIso8601String(),
      },
    );
  });

  @override
  Future<void> endExemption(String exemptionId) =>
      _guard('Clôture impossible.', () async {
        await _client.rpc(
          'admin_end_exemption',
          params: {'p_exemption_id': exemptionId},
        );
      });

  @override
  Future<List<AdminUserSummary>> listUsers() =>
      _guard('Chargement impossible.', () async {
        // La policy de lecture de profiles autorise l'administrateur à tout lire.
        final data = await _client
            .from('profiles')
            .select('id, nom, prenom, email, role')
            .order('nom');
        return (data as List<dynamic>).map((item) {
          final map = item as Map<String, dynamic>;
          return AdminUserSummary(
            id: (map['id'] ?? '').toString(),
            fullName: '${map['prenom'] ?? ''} ${map['nom'] ?? ''}'.trim(),
            email: (map['email'] ?? '').toString(),
            role: (map['role'] ?? '').toString(),
          );
        }).toList();
      });

  @override
  Future<List<PrepaidAccount>> listPrepaidAccounts() =>
      _guard('Chargement impossible.', () async {
        final data = await _client
            .from('prepaid_accounts')
            .select()
            .order('created_at', ascending: false);
        return (data as List<dynamic>)
            .map((item) => PrepaidAccount.fromMap(item as Map<String, dynamic>))
            .toList();
      });

  @override
  Future<void> openPrepaidAccount(String userId) =>
      _guard('Ouverture impossible.', () async {
        await _client.rpc(
          'admin_open_prepaid_account',
          params: {'p_user_id': userId},
        );
      });

  @override
  Future<void> rechargePrepaidAccount(String accountId, int quantity) =>
      _guard('Recharge impossible.', () async {
        await _client.rpc(
          'admin_recharge_prepaid_account',
          params: {'p_account_id': accountId, 'p_quantity': quantity},
        );
      });
}
