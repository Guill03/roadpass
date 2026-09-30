import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../models/user.dart';
import 'auth_service.dart';

class SupabaseAuthService extends AuthService {
  SupabaseAuthService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  StreamSubscription<AuthState>? _authSubscription;
  RoadUser? _currentUser;
  bool _isInitialized = false;
  int _sessionRevision = 0;

  @override
  RoadUser? get currentUser => _currentUser;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize() async {
    if (!AppConfig.isConfigured) {
      _setSessionState(user: null, initialized: true);
      return;
    }
    _authSubscription ??= _client.auth.onAuthStateChange.listen((event) {
      unawaited(_restoreSession(event.session));
    });
    await _restoreSession(_client.auth.currentSession);
  }

  Future<void> _restoreSession(Session? session) async {
    final revision = ++_sessionRevision;
    if (session == null) {
      if (revision == _sessionRevision) {
        _setSessionState(user: null, initialized: true);
      }
      return;
    }
    try {
      final profile = await _fetchUserProfile(session.user.id);
      if (revision == _sessionRevision) {
        _setSessionState(user: profile, initialized: true);
      }
    } catch (_) {
      // A Supabase session without a server profile carries no RoadPass role.
      if (revision == _sessionRevision) {
        _setSessionState(user: null, initialized: true);
      }
    }
  }

  void _setSessionState({required RoadUser? user, required bool initialized}) {
    _currentUser = user;
    _isInitialized = initialized;
    notifyListeners();
  }

  @override
  Future<RoadUser> login(String email, String password) async {
    final user = await _signIn(email, password);
    if (user.role != UserRole.user) {
      await logout();
      throw const RoadPassAuthException(
        'Utilisez l’accès professionnel pour ce compte.',
      );
    }
    return user;
  }

  @override
  Future<RoadUser> professionalLogin(String email, String password) async {
    final user = await _signIn(email, password);
    if (user.role == UserRole.user) {
      await logout();
      throw const RoadPassAuthException(
        'Ce compte n’a pas accès à l’espace professionnel.',
      );
    }
    return user;
  }

  Future<RoadUser> _signIn(String email, String password) async {
    if (!AppConfig.isConfigured) {
      throw const RoadPassAuthException('Backend non configuré.');
    }
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final authUser = response.user;
      if (authUser == null) {
        throw const RoadPassAuthException(
          'Adresse e-mail ou mot de passe incorrect.',
        );
      }
      final profile = await _fetchUserProfile(authUser.id);
      _setSessionState(user: profile, initialized: true);
      return profile;
    } on AuthException catch (error) {
      throw _readableAuthException(error);
    } on RoadPassAuthException {
      rethrow;
    } catch (_) {
      throw const RoadPassAuthException(
        'Connexion impossible. Vérifiez votre connexion Internet puis réessayez.',
      );
    }
  }

  RoadPassAuthException _readableAuthException(AuthException error) {
    switch (error.code) {
      case 'invalid_credentials':
      case 'invalid_grant':
        return const RoadPassAuthException(
          'Adresse e-mail ou mot de passe incorrect.',
        );
      case 'email_not_confirmed':
        return const RoadPassAuthException(
          'Confirmez votre adresse e-mail avant de vous connecter.',
        );
      case 'user_banned':
        return const RoadPassAuthException(
          'Ce compte est temporairement indisponible. Contactez le support.',
        );
      default:
        return RoadPassAuthException('Connexion impossible : ${error.message}');
    }
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
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'nom': nom.trim(),
          'prenom': prenom.trim(),
          'telephone': telephone.trim(),
        },
      );
      final authUser = response.user;
      if (authUser == null) {
        throw const RoadPassAuthException(
          'Impossible de créer le compte utilisateur.',
        );
      }
      final profile = await _fetchUserProfile(authUser.id);
      _setSessionState(user: profile, initialized: true);
      return profile;
    } on AuthException catch (error) {
      throw RoadPassAuthException('Inscription impossible : ${error.message}');
    }
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
    if (_currentUser?.role != UserRole.admin) {
      throw const RoadPassAuthException(
        'Seul un administrateur peut créer un compte agent.',
      );
    }
    try {
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
    } on RoadPassAuthException {
      rethrow;
    } catch (_) {
      throw const RoadPassAuthException(
        'La création du compte agent a échoué.',
      );
    }
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
      await _updateOwnProfile(
        nom: nom,
        prenom: prenom,
        email: current.email,
        telephone: telephone,
      );
      var confirmedEmail = current.email;
      if (password?.isNotEmpty == true || normalizedEmail != current.email) {
        final response = await _client.auth.updateUser(
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
        confirmedEmail = response.user?.email ?? current.email;
      }
      if (confirmedEmail != current.email) {
        await _updateOwnProfile(
          nom: nom,
          prenom: prenom,
          email: confirmedEmail,
          telephone: telephone,
        );
      }
      final updated = current.copyWith(
        nom: nom.trim(),
        prenom: prenom.trim(),
        email: confirmedEmail,
        telephone: telephone.trim(),
      );
      _setSessionState(user: updated, initialized: true);
      return updated;
    } on AuthException catch (error) {
      throw RoadPassAuthException(
        'Erreur d’authentification : ${error.message}',
      );
    } on RoadPassAuthException {
      rethrow;
    } catch (_) {
      throw const RoadPassAuthException(
        'La mise à jour du profil a échoué.',
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
    if (AppConfig.isConfigured) {
      await _client.auth.signOut();
    }
    _setSessionState(user: null, initialized: true);
  }

  Future<RoadUser> _fetchUserProfile(String userId) async {
    final response = await _client
        .from('profiles')
        .select('id, nom, prenom, email, telephone, role, created_at')
        .eq('id', userId)
        .maybeSingle();
    if (response == null) {
      throw const RoadPassAuthException(
        'Votre profil RoadPass est introuvable. Contactez le support.',
      );
    }
    return RoadUser(
      id: userId,
      nom: (response['nom'] ?? '').toString(),
      prenom: (response['prenom'] ?? '').toString(),
      email: (response['email'] ?? '').toString(),
      telephone: (response['telephone'] ?? '').toString(),
      role: RoadUser.parseRole((response['role'] ?? 'user').toString()),
      createdAt: DateTime.tryParse((response['created_at'] ?? '').toString()),
    );
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }
}
