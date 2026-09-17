import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../models/user.dart';
import 'auth_service.dart';

class SupabaseAuthService implements AuthService {
  SupabaseAuthService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  RoadUser? get currentUser => _currentUser;

  RoadUser? _currentUser;

  @override
  Future<void> initialize() async {
    if (!AppConfig.isConfigured) {
      return;
    }

    final session = _client.auth.currentSession;
    if (session == null) {
      _currentUser = null;
      return;
    }

    final user = await _fetchUserProfile(session.user.id);
    _currentUser = user;
  }

  @override
  Future<RoadUser> login(String email, String password) async {
    if (!AppConfig.isConfigured) {
      throw const RoadPassAuthException('Backend non configuré.');
    }

    final response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );

    if (response.user == null) {
      throw const RoadPassAuthException('Identifiants invalides.');
    }

    _currentUser = await _fetchUserProfile(response.user!.id);
    return _currentUser!;
  }

  @override
  Future<RoadUser> register({
    required String nom,
    required String prenom,
    required String email,
    required String telephone,
    required String password,
  }) async {
    if (!AppConfig.isConfigured) {
      throw const RoadPassAuthException('Backend non configuré.');
    }

    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'nom': nom.trim(),
        'prenom': prenom.trim(),
        'telephone': telephone.trim(),
        'role': 'user',
      },
    );

    final userId = response.user?.id;
    if (userId == null) {
      throw const RoadPassAuthException(
        'Impossible de créer le compte utilisateur.',
      );
    }

    final profile = await _fetchUserProfile(userId);
    _currentUser = profile;
    return profile;
  }

  @override
  Future<RoadUser> professionalLogin(String email, String password) async {
    final user = await login(email, password);
    if (user.role == UserRole.user) {
      throw const RoadPassAuthException(
        'Ce compte n’a pas accès à l’espace professionnel.',
      );
    }
    return user;
  }

  @override
  Future<RoadUser> createAgentAccount({
    required String nom,
    required String prenom,
    required String email,
    required String telephone,
    required String password,
  }) async {
    if (!AppConfig.isConfigured) {
      throw const RoadPassAuthException('Backend non configuré.');
    }

    final currentUser = _currentUser;
    if (currentUser == null || currentUser.role != UserRole.admin) {
      throw const RoadPassAuthException(
        'Seul un administrateur peut créer un compte agent.',
      );
    }

    final response = await _client.functions.invoke(
      'create-agent',
      body: {
        'nom': nom.trim(),
        'prenom': prenom.trim(),
        'email': email.trim(),
        'telephone': telephone.trim(),
        'password': password,
      },
    );

    final data = response.data;
    final userId = data is Map ? data['id']?.toString() : null;
    if (userId == null) {
      throw const RoadPassAuthException(
        'La création du compte agent a échoué.',
      );
    }

    return _fetchUserProfile(userId);
  }

  @override
  Future<RoadUser> updateProfile({
    required String nom,
    required String prenom,
    required String email,
    required String telephone,
    String? password,
  }) async {
    if (!AppConfig.isConfigured) {
      throw const RoadPassAuthException('Backend non configuré.');
    }
    final current = _currentUser;
    if (current == null) {
      throw const RoadPassAuthException('Vous devez vous connecter.');
    }

    final normalizedEmail = email.trim().toLowerCase();

    try {
      // The profile is updated first with the current Auth email. This avoids
      // recording an unconfirmed email when secure email change is enabled.
      await _updateOwnProfile(
        nom: nom,
        prenom: prenom,
        email: current.email,
        telephone: telephone,
      );

      var confirmedEmail = current.email;
      final hasSensitiveChange =
          password?.isNotEmpty == true || normalizedEmail != current.email;
      if (hasSensitiveChange) {
        final authResponse = await _client.auth.updateUser(
          UserAttributes(
            email: normalizedEmail == current.email ? null : normalizedEmail,
            password: password?.isNotEmpty == true ? password : null,
            data: {
              'nom': nom.trim(),
              'prenom': prenom.trim(),
              'telephone': telephone.trim(),
            },
          ),
        );
        if (authResponse.user == null) {
          throw const RoadPassAuthException(
            'La mise à jour du compte a échoué.',
          );
        }
        confirmedEmail = authResponse.user!.email ?? current.email;
      }

      // With email confirmation enabled, confirmedEmail remains the old email
      // until the user validates the link. Otherwise keep both stores aligned.
      if (confirmedEmail != current.email) {
        await _updateOwnProfile(
          nom: nom,
          prenom: prenom,
          email: confirmedEmail,
          telephone: telephone,
        );
      }

      _currentUser = current.copyWith(
        nom: nom.trim(),
        prenom: prenom.trim(),
        email: confirmedEmail,
        telephone: telephone.trim(),
      );
      return _currentUser!;
    } on AuthException catch (error) {
      throw RoadPassAuthException(
        'Erreur d’authentification : ${error.message}',
      );
    } on RoadPassAuthException {
      rethrow;
    } catch (error) {
      throw RoadPassAuthException(
        'Impossible de mettre à jour le profil : $error',
      );
    }
  }

  Future<void> _updateOwnProfile({
    required String nom,
    required String prenom,
    required String email,
    required String telephone,
  }) => _client.rpc(
    'update_own_profile',
    params: {
      'p_nom': nom.trim(),
      'p_prenom': prenom.trim(),
      'p_email': email.trim().toLowerCase(),
      'p_telephone': telephone.trim(),
    },
  );

  @override
  Future<void> logout() async {
    await _client.auth.signOut();
    _currentUser = null;
  }

  Future<RoadUser> _fetchUserProfile(String userId) async {
    final response = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (response == null) {
      final current = _client.auth.currentUser;
      final role = current?.userMetadata?['role'] ?? 'user';
      return RoadUser(
        id: userId,
        nom: (current?.userMetadata?['nom'] ?? 'Utilisateur').toString(),
        prenom: (current?.userMetadata?['prenom'] ?? 'Client').toString(),
        email: current?.email ?? '',
        telephone: (current?.userMetadata?['telephone'] ?? '').toString(),
        role: RoadUser.parseRole(role),
        createdAt: DateTime.now(),
      );
    }

    final role = response['role'] ?? 'user';
    return RoadUser(
      id: userId,
      nom: (response['nom'] ?? 'Utilisateur').toString(),
      prenom: (response['prenom'] ?? 'Client').toString(),
      email: (response['email'] ?? '').toString(),
      telephone: (response['telephone'] ?? '').toString(),
      role: RoadUser.parseRole(role),
      createdAt:
          DateTime.tryParse(
            (response['created_at'] ?? DateTime.now().toIso8601String())
                .toString(),
          ) ??
          DateTime.now(),
    );
  }
}
