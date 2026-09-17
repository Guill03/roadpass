import '../models/user.dart';
import 'auth_service.dart';

class MockAuthService implements AuthService {
  factory MockAuthService() => instance;

  MockAuthService._();

  static final MockAuthService instance = MockAuthService._();

  RoadUser? _currentUser;

  final Map<String, ({RoadUser user, String password})> _accounts = {
    'user@roadpass.test': (
      user: const RoadUser(
        id: 'user-001',
        nom: 'Diallo',
        prenom: 'Aminata',
        email: 'user@roadpass.test',
        telephone: '+225 07 00 00 00 01',
        role: UserRole.user,
      ),
      password: 'RoadPass123!',
    ),
    'agent@roadpass.test': (
      user: const RoadUser(
        id: 'agent-001',
        nom: 'Kone',
        prenom: 'Moussa',
        email: 'agent@roadpass.test',
        telephone: '+225 07 00 00 00 02',
        role: UserRole.agent,
      ),
      password: 'RoadPass123!',
    ),
    'admin@roadpass.test': (
      user: const RoadUser(
        id: 'admin-001',
        nom: 'Traore',
        prenom: 'Nadia',
        email: 'admin@roadpass.test',
        telephone: '+225 07 00 00 00 03',
        role: UserRole.admin,
      ),
      password: 'RoadPass123!',
    ),
  };

  @override
  RoadUser? get currentUser => _currentUser;

  @override
  Future<void> initialize() async {
    _currentUser = null;
  }

  @override
  Future<RoadUser> login(String email, String password) async {
    final account = _accounts[email.trim().toLowerCase()];
    if (account == null ||
        account.password != password ||
        account.user.role != UserRole.user) {
      throw const RoadPassAuthException(
        'Adresse e-mail ou mot de passe incorrect.',
      );
    }
    _currentUser = account.user;
    return account.user;
  }

  @override
  Future<RoadUser> professionalLogin(String email, String password) async {
    final account = _accounts[email.trim().toLowerCase()];
    if (account == null ||
        account.password != password ||
        account.user.role == UserRole.user) {
      throw const RoadPassAuthException(
        'Identifiants professionnels incorrects.',
      );
    }
    _currentUser = account.user;
    return account.user;
  }

  @override
  Future<RoadUser> register({
    required String nom,
    required String prenom,
    required String email,
    required String telephone,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (_accounts.containsKey(normalizedEmail)) {
      throw const RoadPassAuthException(
        'Cette adresse e-mail est déjà utilisée.',
      );
    }
    final user = RoadUser(
      id: 'user-local-${_accounts.length + 1}',
      nom: nom.trim(),
      prenom: prenom.trim(),
      email: normalizedEmail,
      telephone: telephone.trim(),
      role: UserRole.user,
    );
    _accounts[normalizedEmail] = (user: user, password: password);
    _currentUser = user;
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
    if (_currentUser == null || _currentUser!.role != UserRole.admin) {
      throw const RoadPassAuthException(
        'Seul un administrateur peut créer un compte agent.',
      );
    }

    final normalizedEmail = email.trim().toLowerCase();
    if (_accounts.containsKey(normalizedEmail)) {
      throw const RoadPassAuthException(
        'Cette adresse e-mail est déjà utilisée.',
      );
    }

    final agent = RoadUser(
      id: 'agent-local-${_accounts.length + 1}',
      nom: nom.trim(),
      prenom: prenom.trim(),
      email: normalizedEmail,
      telephone: telephone.trim(),
      role: UserRole.agent,
    );

    _accounts[normalizedEmail] = (user: agent, password: password);
    return agent;
  }

  @override
  Future<RoadUser> updateProfile({
    required String nom,
    required String prenom,
    required String email,
    required String telephone,
    String? password,
  }) async {
    final current = _currentUser;
    if (current == null) {
      throw const RoadPassAuthException('Vous devez vous connecter.');
    }
    final normalizedEmail = email.trim().toLowerCase();
    final existing = _accounts[normalizedEmail];
    if (existing != null && existing.user.id != current.id) {
      throw const RoadPassAuthException('Cette adresse e-mail est déjà utilisée.');
    }

    final updated = current.copyWith(
      nom: nom.trim(),
      prenom: prenom.trim(),
      email: normalizedEmail,
      telephone: telephone.trim(),
    );
    final previousAccount = _accounts.remove(current.email);
    _accounts[normalizedEmail] = (
      user: updated,
      password: password?.isNotEmpty == true
          ? password!
          : previousAccount!.password,
    );
    _currentUser = updated;
    return updated;
  }

  @override
  Future<void> logout() async => _currentUser = null;
}
