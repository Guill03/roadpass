import 'package:flutter_test/flutter_test.dart';
import 'package:roadpass/core/config/app_config.dart';

void main() {
  group('AppConfig.resolveAuthMode', () {
    test('utilise Supabase quand les deux identifiants sont configurés', () {
      expect(
        AppConfig.resolveAuthMode(
          dartDefine: '',
          dotenvValue: null,
          hasSupabaseCredentials: true,
        ),
        AuthMode.supabase,
      );
    });

    test('reste en mock sans configuration Supabase', () {
      expect(
        AppConfig.resolveAuthMode(
          dartDefine: '',
          dotenvValue: null,
          hasSupabaseCredentials: false,
        ),
        AuthMode.mock,
      );
    });

    test('permet de forcer le mode mock même avec des identifiants', () {
      expect(
        AppConfig.resolveAuthMode(
          dartDefine: '',
          dotenvValue: 'mock',
          hasSupabaseCredentials: true,
        ),
        AuthMode.mock,
      );
    });

    test('la surcharge dart-define a priorité sur dotenv', () {
      expect(
        AppConfig.resolveAuthMode(
          dartDefine: 'mock',
          dotenvValue: 'supabase',
          hasSupabaseCredentials: true,
        ),
        AuthMode.mock,
      );
    });
  });

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
