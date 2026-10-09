import 'dart:async';

import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/mock_auth_service.dart';
import 'services/supabase_auth_service.dart';

class RoadPassApp extends StatefulWidget {
  const RoadPassApp({super.key, this.authService});

  final AuthService? authService;

  @override
  State<RoadPassApp> createState() => _RoadPassAppState();
}

class _RoadPassAppState extends State<RoadPassApp> {
  late final AuthService _authService;
  late final AppRouter _appRouter;

  @override
  void initState() {
    super.initState();
    _authService =
        widget.authService ??
        (AppConfig.isSupabaseMode ? SupabaseAuthService() : MockAuthService());
    _appRouter = AppRouter(_authService);
    unawaited(_authService.initialize());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'RoadPass',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: _appRouter.router,
    );
  }
}
