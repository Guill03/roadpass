import 'package:flutter_dotenv/flutter_dotenv.dart';

enum AuthMode { mock, supabase }

class AppConfig {
  static const String _authModeDartDefine = String.fromEnvironment(
    'ROADPASS_AUTH_MODE',
  );

  static const String supabaseUrlEnv = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseKeyEnv = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  // Lecture via dotenv si disponible
  static String get supabaseUrl => supabaseUrlEnv.isNotEmpty
      ? supabaseUrlEnv
      : (dotenv.env['SUPABASE_URL'] ?? '');

  static String get supabasePublishableKey => supabaseKeyEnv.isNotEmpty
      ? supabaseKeyEnv
      : (dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ?? '');

  static AuthMode get authMode => resolveAuthMode(
    dartDefine: _authModeDartDefine,
    dotenvValue: dotenv.env['ROADPASS_AUTH_MODE'],
    hasSupabaseCredentials:
        supabaseUrl.trim().isNotEmpty &&
        supabasePublishableKey.trim().isNotEmpty,
  );

  static AuthMode resolveAuthMode({
    required String dartDefine,
    required String? dotenvValue,
    required bool hasSupabaseCredentials,
  }) {
    final configuredMode = dartDefine.trim().isNotEmpty
        ? dartDefine.trim()
        : dotenvValue?.trim();
    if (configuredMode != null && configuredMode.isNotEmpty) {
      return parseAuthMode(configuredMode);
    }
    return hasSupabaseCredentials ? AuthMode.supabase : AuthMode.mock;
  }

  static AuthMode parseAuthMode(String value) {
    switch (value) {
      case 'mock':
        return AuthMode.mock;
      case 'supabase':
        return AuthMode.supabase;
      default:
        throw ArgumentError.value(value, 'ROADPASS_AUTH_MODE');
    }
  }

  static bool get isSupabaseMode => authMode == AuthMode.supabase;

  static bool get isConfigured =>
      isSupabaseMode &&
      supabaseUrl.trim().isNotEmpty &&
      supabasePublishableKey.trim().isNotEmpty;

  static void validate() {
    if (isSupabaseMode && !isConfigured) {
      throw StateError(
        'Le mode Supabase exige SUPABASE_URL et SUPABASE_PUBLISHABLE_KEY.',
      );
    }
  }
}
