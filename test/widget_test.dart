// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:roadpass/app.dart';
import 'package:roadpass/services/mock_auth_service.dart';

void main() {
  testWidgets('RoadPass affiche l’accueil d’authentification', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(RoadPassApp(authService: MockAuthService()));

    expect(find.text('RoadPass'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.text('Accès professionnel'), findsOneWidget);
  });
}
