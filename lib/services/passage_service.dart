import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/passage.dart';

class PassageServiceException implements Exception {
  const PassageServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Opérations de l'agent de vérification. Le rôle « agent » est contrôlé par
/// la base (RPC scan_receipt / decide_passage), pas par Flutter.
abstract class PassageServiceBase {
  Future<ScannedReceipt> scanReceipt(String qrCode);

  Future<Passage> decidePassage(
    String qrCode, {
    required bool authorized,
    String? reason,
  });

  Future<List<Passage>> getMyPassages();
}

class PassageService extends PassageServiceBase {
  PassageService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  void _requireSession() {
    if (_client.auth.currentUser == null) {
      throw const PassageServiceException('Utilisateur non authentifié.');
    }
  }

  @override
  Future<ScannedReceipt> scanReceipt(String qrCode) async {
    _requireSession();
    try {
      final data = await _client.rpc(
        'scan_receipt',
        params: {'p_qr_code': qrCode.trim()},
      );
      if (data is! Map<String, dynamic>) {
        throw const PassageServiceException('Réponse inattendue du serveur.');
      }
      return ScannedReceipt.fromMap(data);
    } on PostgrestException catch (error) {
      throw PassageServiceException(error.message);
    } on PassageServiceException {
      rethrow;
    } catch (_) {
      throw const PassageServiceException(
        'La vérification a échoué. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<Passage> decidePassage(
    String qrCode, {
    required bool authorized,
    String? reason,
  }) async {
    _requireSession();
    try {
      final data = await _client.rpc(
        'decide_passage',
        params: {
          'p_qr_code': qrCode.trim(),
          'p_authorized': authorized,
          'p_reason': reason,
        },
      );
      final map = data is List && data.isNotEmpty ? data.first : data;
      if (map is! Map<String, dynamic>) {
        throw const PassageServiceException('Réponse inattendue du serveur.');
      }
      return Passage.fromMap(map);
    } on PostgrestException catch (error) {
      throw PassageServiceException(error.message);
    } on PassageServiceException {
      rethrow;
    } catch (_) {
      throw const PassageServiceException(
        'La décision n’a pas pu être enregistrée. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Future<List<Passage>> getMyPassages() async {
    _requireSession();
    try {
      final userId = _client.auth.currentUser!.id;
      final response = await _client
          .from('passages')
          .select()
          .eq('agent_id', userId)
          .order('created_at', ascending: false);
      return (response as List<dynamic>)
          .map((item) => Passage.fromMap(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (error) {
      throw PassageServiceException(
        'Impossible de récupérer vos vérifications : ${error.message}',
      );
    } catch (_) {
      throw const PassageServiceException(
        'Impossible de récupérer vos vérifications. Vérifiez votre connexion.',
      );
    }
  }
}
