import 'package:go_router/go_router.dart';

import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/agent/screens/agent_dashboard_screen.dart';
import '../../features/auth/screens/auth_landing_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/professional_login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/user/screens/user_dashboard_screen.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';

class AppRouter {
  AppRouter(this.authService);

  final AuthService authService;

  late final GoRouter router = GoRouter(
    initialLocation: '/',
    refreshListenable: authService,
    redirect: (context, state) {
      final path = state.uri.path;
      final user = authService.currentUser;
      final isAuthRoute = path == '/' || path.startsWith('/auth');

      if (!authService.isInitialized) {
        return isAuthRoute ? null : '/auth';
      }
      if (user == null && !isAuthRoute) return '/auth';
      if (user != null && isAuthRoute) return _dashboardFor(user.role);

      if (user != null) {
        final expectedPath = _dashboardFor(user.role);
        final isDashboardPath =
            path == '/user' || path == '/agent' || path == '/admin';
        if (isDashboardPath && path != expectedPath) return expectedPath;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const AuthLandingScreen(),
      ),
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthLandingScreen(),
      ),
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => LoginScreen(authService: authService),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (context, state) => RegisterScreen(authService: authService),
      ),
      GoRoute(
        path: '/auth/professional-login',
        builder: (context, state) =>
            ProfessionalLoginScreen(authService: authService),
      ),
      GoRoute(
        path: '/user',
        builder: (context, state) =>
            UserDashboardScreen(authService: authService),
      ),
      GoRoute(
        path: '/agent',
        builder: (context, state) =>
            AgentDashboardScreen(authService: authService),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) =>
            AdminDashboardScreen(authService: authService),
      ),
    ],
  );

  static String _dashboardFor(UserRole role) {
    switch (role) {
      case UserRole.user:
        return '/user';
      case UserRole.agent:
        return '/agent';
      case UserRole.admin:
        return '/admin';
    }
  }
}
