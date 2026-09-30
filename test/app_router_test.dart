import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:roadpass/core/routing/app_router.dart';
import 'package:roadpass/models/user.dart';
import 'package:roadpass/services/mock_auth_service.dart';

RoadUser userFor(UserRole role) => RoadUser(
  id: role.name,
  nom: 'Test',
  prenom: role.name,
  email: '${role.name}@roadpass.test',
  telephone: '+2250700000000',
  role: role,
);

Future<void> pumpRouter(
  WidgetTester tester,
  MockAuthService service,
  GoRouter router,
) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  await service.initialize();
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('un visiteur est redirigé vers l’authentification', (
    tester,
  ) async {
    final service = MockAuthService();
    final router = AppRouter(service).router;

    await pumpRouter(tester, service, router);
    router.go('/admin');
    await tester.pumpAndSettle();

    expect(find.text('RoadPass'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
  });

  for (final role in UserRole.values) {
    testWidgets('$role rejoint uniquement son dashboard', (tester) async {
      final service = MockAuthService(restoredUser: userFor(role));
      final router = AppRouter(service).router;

      await pumpRouter(tester, service, router);
      router.go('/admin');
      await tester.pumpAndSettle();

      switch (role) {
        case UserRole.user:
          expect(find.textContaining('véhicules, paiements'), findsOneWidget);
        case UserRole.agent:
          expect(
            find.textContaining('opérations de votre poste'),
            findsOneWidget,
          );
        case UserRole.admin:
          expect(find.textContaining('vue structurée'), findsOneWidget);
      }
    });
  }

  final forbiddenRoutes = <({UserRole role, String path, String dashboard})>[
    (role: UserRole.user, path: '/agent', dashboard: '/user'),
    (role: UserRole.user, path: '/admin', dashboard: '/user'),
    (role: UserRole.agent, path: '/admin', dashboard: '/agent'),
    (role: UserRole.admin, path: '/user', dashboard: '/admin'),
  ];

  for (final scenario in forbiddenRoutes) {
    testWidgets('${scenario.role} est refusé sur ${scenario.path}', (
      tester,
    ) async {
      final service = MockAuthService(restoredUser: userFor(scenario.role));
      final router = AppRouter(service).router;

      await pumpRouter(tester, service, router);
      router.go(scenario.path);
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        scenario.dashboard,
      );
    });
  }

  testWidgets('la déconnexion renvoie vers l’authentification', (tester) async {
    final service = MockAuthService(restoredUser: userFor(UserRole.user));
    final router = AppRouter(service).router;

    await pumpRouter(tester, service, router);
    await service.logout();
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.path, '/auth');
  });
}
