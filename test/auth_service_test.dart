import 'package:flutter_test/flutter_test.dart';
import 'package:roadpass/models/user.dart';
import 'package:roadpass/services/auth_service.dart';
import 'package:roadpass/services/mock_auth_service.dart';

void main() {
  group('MockAuthService', () {
    test('restaure une session et notifie un utilisateur connecté', () async {
      const restoredUser = RoadUser(
        id: 'restored-user',
        nom: 'Diallo',
        prenom: 'Aminata',
        email: 'user@roadpass.test',
        telephone: '+2250700000001',
        role: UserRole.user,
      );
      final service = MockAuthService(restoredUser: restoredUser);

      await service.initialize();

      expect(service.isInitialized, isTrue);
      expect(service.currentUser, restoredUser);
    });

    test(
      'connecte un utilisateur puis supprime sa session au logout',
      () async {
        final service = MockAuthService();
        await service.initialize();

        final user = await service.login('user@roadpass.test', 'RoadPass123!');
        expect(user.role, UserRole.user);
        expect(service.currentUser, user);

        await service.logout();
        expect(service.currentUser, isNull);
      },
    );

    test('refuse les identifiants invalides', () async {
      final service = MockAuthService();

      await expectLater(
        service.login('user@roadpass.test', 'invalide'),
        throwsA(isA<RoadPassAuthException>()),
      );
    });

    test('refuse un compte professionnel dans la connexion générale', () async {
      final service = MockAuthService();

      await expectLater(
        service.login('agent@roadpass.test', 'RoadPass123!'),
        throwsA(
          predicate<RoadPassAuthException>(
            (error) => error.message.contains('accès professionnel'),
          ),
        ),
      );
      expect(service.currentUser, isNull);
    });

    test('refuse proprement un user dans l’accès professionnel', () async {
      final service = MockAuthService();

      await expectLater(
        service.professionalLogin('user@roadpass.test', 'RoadPass123!'),
        throwsA(isA<RoadPassAuthException>()),
      );
      expect(service.currentUser, isNull);
    });

    test('autorise agent et admin dans l’accès professionnel', () async {
      final service = MockAuthService();

      final agent = await service.professionalLogin(
        'agent@roadpass.test',
        'RoadPass123!',
      );
      expect(agent.role, UserRole.agent);

      await service.logout();
      final admin = await service.professionalLogin(
        'admin@roadpass.test',
        'RoadPass123!',
      );
      expect(admin.role, UserRole.admin);
    });
  });
}
