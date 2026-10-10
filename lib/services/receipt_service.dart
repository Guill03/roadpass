import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/receipt.dart';

class ReceiptServiceException implements Exception {
  const ReceiptServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class ReceiptServiceBase {
  Future<List<Receipt>> getMyReceipts();
}

class ReceiptService extends ReceiptServiceBase {
  ReceiptService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<Receipt>> getMyReceipts() async {
    if (_client.auth.currentUser == null) {
      throw const ReceiptServiceException('Utilisateur non authentifié.');
    }
    try {
      // La RLS ne renvoie que les justificatifs des transactions de l'usager.
      final response = await _client
          .from('receipts')
          .select()
          .order('generated_at', ascending: false);
      return (response as List<dynamic>)
          .map((item) => Receipt.fromMap(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (error) {
      throw ReceiptServiceException(
        'Impossible de récupérer vos justificatifs : ${error.message}',
      );
    } catch (_) {
      throw const ReceiptServiceException(
        'Impossible de récupérer vos justificatifs. Vérifiez votre connexion.',
      );
    }
  }
}
