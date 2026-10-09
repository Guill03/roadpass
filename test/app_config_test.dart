import 'package:flutter_test/flutter_test.dart';
import 'package:roadpass/core/config/app_config.dart';

void main() {
  group('AppConfig.parseAuthMode', () {
    test('reconnaît les modes explicites', () {
      expect(AppConfig.parseAuthMode('mock'), AuthMode.mock);
      expect(AppConfig.parseAuthMode('supabase'), AuthMode.supabase);
    });

    test('refuse une valeur de mode inconnue', () {
      expect(() => AppConfig.parseAuthMode('remote'), throwsArgumentError);
    });
  });
}
