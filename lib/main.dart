import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    );
  } else {
    // Optionnel : Ajouter un log ou lever une alerte en mode développement
    debugPrint('Attention : Supabase n\'a pas pu être configuré.');
  }

  runApp(const RoadPassApp());
}

final supabase = Supabase.instance.client;
