enum AuthMode { mock, supabase }

class AppConfig {
  static const String authModeValue = String.fromEnvironment(
    'ROADPASS_AUTH_MODE',
    defaultValue: 'mock',
  );

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static AuthMode get authMode => parseAuthMode(authModeValue);

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
