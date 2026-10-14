import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_statistics.dart';
import '../models/admin_transaction.dart';
import '../models/audit_entry.dart';
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
    this.accountStatus = 'actif',
  });

  final String id;
  final String fullName;
  final String email;
  final String role;
  final String accountStatus;

  bool get isSuspended => accountStatus == 'suspendu';
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

  Future<List<AdminTransaction>> listTransactions({String? status});
  Future<TransactionsSummary> getTransactionsSummary();

  Future<void> setAccountStatus(String userId, String status);
  Future<List<AuditEntry>> listAuditLog({String? entity});
  Future<AdminStatistics> getStatistics({int days = 30});
  Future<bool> getPaymentSimulation();
  Future<void> setPaymentSimulation(bool enabled);
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
  Future<List<AdminUserSummary>> listUsers() => _guard(
    'Chargement impossible.',
    () async {
      // La policy de lecture de profiles autorise l'administrateur à tout lire.
      final data = await _client
          .from('profiles')
          .select('id, nom, prenom, email, role, account_status')
          .order('nom');
      return (data as List<dynamic>).map((item) {
        final map = item as Map<String, dynamic>;
        return AdminUserSummary(
          id: (map['id'] ?? '').toString(),
          fullName: '${map['prenom'] ?? ''} ${map['nom'] ?? ''}'.trim(),
          email: (map['email'] ?? '').toString(),
          role: (map['role'] ?? '').toString(),
          accountStatus: (map['account_status'] ?? 'actif').toString(),
        );
      }).toList();
    },
  );

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

  @override
  Future<List<AdminTransaction>> listTransactions({String? status}) => _guard(
    'Chargement impossible.',
    () async {
      final data = await _client.rpc(
        'admin_list_transactions',
        params: {'p_status': status, 'p_limit': 200},
      );
      return (data as List<dynamic>)
          .map((item) => AdminTransaction.fromMap(item as Map<String, dynamic>))
          .toList();
    },
  );

  @override
  Future<TransactionsSummary> getTransactionsSummary() =>
      _guard('Chargement impossible.', () async {
        final data = await _client.rpc('admin_transactions_summary');
        if (data is! Map<String, dynamic>) {
          throw const AdminOperationsException('Réponse inattendue.');
        }
        return TransactionsSummary.fromMap(data);
      });

  @override
  Future<void> setAccountStatus(String userId, String status) =>
      _guard('Modification impossible.', () async {
        await _client.rpc(
          'admin_set_account_status',
          params: {'p_user_id': userId, 'p_status': status},
        );
      });

  @override
  Future<List<AuditEntry>> listAuditLog({String? entity}) =>
      _guard('Chargement impossible.', () async {
        final data = await _client.rpc(
          'admin_list_audit_log',
          params: {'p_entity': entity, 'p_limit': 200},
        );
        return (data as List<dynamic>)
            .map((item) => AuditEntry.fromMap(item as Map<String, dynamic>))
            .toList();
      });

  @override
  Future<AdminStatistics> getStatistics({int days = 30}) =>
      _guard('Chargement impossible.', () async {
        final data = await _client.rpc(
          'admin_statistics',
          params: {'p_days': days},
        );
        if (data is! Map<String, dynamic>) {
          throw const AdminOperationsException('Réponse inattendue.');
        }
        return AdminStatistics.fromMap(data);
      });

  @override
  Future<bool> getPaymentSimulation() =>
      _guard('Chargement impossible.', () async {
        final data = await _client.rpc('admin_get_payment_simulation');
        return data == true;
      });

  @override
  Future<void> setPaymentSimulation(bool enabled) =>
      _guard('Modification impossible.', () async {
        await _client.rpc(
          'admin_set_payment_simulation',
          params: {'p_enabled': enabled},
        );
      });
}
