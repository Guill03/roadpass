import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/toll_tariff.dart';
import '../models/toll_transaction.dart';

class TransactionServiceException implements Exception {
  const TransactionServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class TransactionServiceBase {
  Future<List<TollTransaction>> getMyTransactions();

  /// Le montant et le tarif sont calculés par la base (RPC create_transaction) :
  /// le client ne les envoie jamais.
  Future<TollTransaction> createTransaction({
    required String vehicleId,
    required String tollPostId,
    required TripType tripType,
  });

  Future<TollTransaction> cancelTransaction(String transactionId);
}

class TransactionService extends TransactionServiceBase {
  TransactionService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<TollTransaction>> getMyTransactions() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const TransactionServiceException('Utilisateur non authentifié.');
    }
    try {
      final response = await _client
          .from('transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return (response as List<dynamic>)
          .map((item) => TollTransaction.fromMap(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (error) {
      throw TransactionServiceException(
        'Impossible de récupérer vos passages : ${error.message}',
      );
    } catch (_) {
      throw const TransactionServiceException(
        'Impossible de récupérer vos passages. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<TollTransaction> createTransaction({
    required String vehicleId,
    required String tollPostId,
    required TripType tripType,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const TransactionServiceException('Utilisateur non authentifié.');
    }
    try {
      final data = await _client.rpc(
        'create_transaction',
        params: {
          'p_vehicle_id': vehicleId,
          'p_post_id': tollPostId,
          'p_trip_type': tripType.value,
        },
      );
      return TollTransaction.fromMap(_asMap(data));
    } on PostgrestException catch (error) {
      throw TransactionServiceException(error.message);
    } on TransactionServiceException {
      rethrow;
    } catch (_) {
      throw const TransactionServiceException(
        'L’enregistrement du passage a échoué. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<TollTransaction> cancelTransaction(String transactionId) async {
    if (_client.auth.currentUser == null) {
      throw const TransactionServiceException('Utilisateur non authentifié.');
    }
    try {
      final data = await _client.rpc(
        'cancel_transaction',
        params: {'p_transaction_id': transactionId},
      );
      return TollTransaction.fromMap(_asMap(data));
    } on PostgrestException catch (error) {
      throw TransactionServiceException(error.message);
    } on TransactionServiceException {
      rethrow;
    } catch (_) {
      throw const TransactionServiceException(
        'L’annulation a échoué. Vérifiez votre connexion.',
      );
    }
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is List && data.isNotEmpty && data.first is Map<String, dynamic>) {
      return data.first as Map<String, dynamic>;
    }
    throw const TransactionServiceException('Réponse inattendue du serveur.');
  }
}
