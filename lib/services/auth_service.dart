import 'package:flutter/foundation.dart';

import '../models/user.dart';

class RoadPassAuthException implements Exception {
  const RoadPassAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class AuthService extends ChangeNotifier {
  RoadUser? get currentUser;

  bool get isInitialized;

  Future<void> initialize();

  Future<RoadUser> login(String email, String password);

  Future<RoadUser> register({
    required String nom,
    required String prenom,
    required String email,
    required String telephone,
    required String password,
  });

  Future<RoadUser> professionalLogin(String email, String password);

  Future<RoadUser> createAgentAccount({
    required String nom,
    required String prenom,
    required String email,
    required String telephone,
    required String password,
  });

  Future<RoadUser> updateProfile({
    required String nom,
    required String prenom,
    required String email,
    required String telephone,
    String? password,
  });

  Future<void> logout();
}
