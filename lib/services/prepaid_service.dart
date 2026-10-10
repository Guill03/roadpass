import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/prepaid_account.dart';
import '../models/toll_transaction.dart';

class PrepaidServiceException implements Exception {
  const PrepaidServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Côté usager : consulter son compte prépayé et régler un passage avec.
abstract class PrepaidServiceBase {
  Future<PrepaidAccount?> getMyAccount();
  Future<TollTransaction> payTransactionWithAccount(String transactionId);
}

class PrepaidService extends PrepaidServiceBase {
  PrepaidService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<PrepaidAccount?> getMyAccount() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const PrepaidServiceException('Utilisateur non authentifié.');
    }
    try {
      final response = await _client
          .from('prepaid_accounts')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      return response == null ? null : PrepaidAccount.fromMap(response);
    } on PostgrestException catch (error) {
      throw PrepaidServiceException(
        'Impossible de récupérer votre compte prépayé : ${error.message}',
      );
    } catch (_) {
      throw const PrepaidServiceException(
        'Impossible de récupérer votre compte prépayé. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<TollTransaction> payTransactionWithAccount(
    String transactionId,
  ) async {
    if (_client.auth.currentUser == null) {
      throw const PrepaidServiceException('Utilisateur non authentifié.');
    }
    try {
      final data = await _client.rpc(
        'pay_transaction_with_account',
        params: {'p_transaction_id': transactionId},
      );
      final map = data is List && data.isNotEmpty ? data.first : data;
      if (map is! Map<String, dynamic>) {
        throw const PrepaidServiceException('Réponse inattendue du serveur.');
      }
      return TollTransaction.fromMap(map);
    } on PostgrestException catch (error) {
      throw PrepaidServiceException(error.message);
    } on PrepaidServiceException {
      rethrow;
    } catch (_) {
      throw const PrepaidServiceException(
        'Le règlement a échoué. Vérifiez votre connexion.',
      );
    }
  }
}
