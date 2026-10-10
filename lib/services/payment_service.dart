import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/payment.dart';

class PaymentServiceException implements Exception {
  const PaymentServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class PaymentServiceBase {
  Future<List<Payment>> getMyPayments();

  /// SIMULATION : aucun argent réel n'est débité. Quand un prestataire réel
  /// sera branché, cette méthode sera remplacée par une demande de paiement
  /// dont le résultat est confirmé côté serveur (webhook).
  Future<Payment> payTransactionSimulated(
    String transactionId, {
    bool succeed = true,
  });
}

class PaymentService extends PaymentServiceBase {
  PaymentService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<Payment>> getMyPayments() async {
    if (_client.auth.currentUser == null) {
      throw const PaymentServiceException('Utilisateur non authentifié.');
    }
    try {
      // La RLS ne renvoie que les paiements des transactions de l'utilisateur.
      final response = await _client
          .from('payments')
          .select()
          .order('created_at', ascending: false);
      return (response as List<dynamic>)
          .map((item) => Payment.fromMap(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (error) {
      throw PaymentServiceException(
        'Impossible de récupérer vos paiements : ${error.message}',
      );
    } catch (_) {
      throw const PaymentServiceException(
        'Impossible de récupérer vos paiements. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<Payment> payTransactionSimulated(
    String transactionId, {
    bool succeed = true,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const PaymentServiceException('Utilisateur non authentifié.');
    }
    try {
      final data = await _client.rpc(
        'pay_transaction_simulated',
        params: {'p_transaction_id': transactionId, 'p_succeed': succeed},
      );
      final map = data is List && data.isNotEmpty ? data.first : data;
      if (map is! Map<String, dynamic>) {
        throw const PaymentServiceException('Réponse inattendue du serveur.');
      }
      return Payment.fromMap(map);
    } on PostgrestException catch (error) {
      throw PaymentServiceException(error.message);
    } on PaymentServiceException {
      rethrow;
    } catch (_) {
      throw const PaymentServiceException(
        'Le paiement a échoué. Vérifiez votre connexion.',
      );
    }
  }
}
