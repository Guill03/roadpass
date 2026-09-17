enum UserRole { user, agent, admin }

class RoadUser {
  const RoadUser({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.email,
    required this.telephone,
    required this.role,
    this.createdAt,
    this.accountStatus = 'active',
  });

  final String id;
  final String nom;
  final String prenom;
  final String email;
  final String telephone;
  final UserRole role;
  final DateTime? createdAt;
  final String accountStatus;

  String get fullName => '$prenom $nom';

  RoadUser copyWith({
    String? nom,
    String? prenom,
    String? email,
    String? telephone,
  }) => RoadUser(
    id: id,
    nom: nom ?? this.nom,
    prenom: prenom ?? this.prenom,
    email: email ?? this.email,
    telephone: telephone ?? this.telephone,
    role: role,
    createdAt: createdAt,
    accountStatus: accountStatus,
  );

  static UserRole parseRole(String value) {
    switch (value.toLowerCase()) {
      case 'agent':
        return UserRole.agent;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.user;
    }
  }
}

typedef User = RoadUser;
