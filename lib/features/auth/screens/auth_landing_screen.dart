import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

class AuthLandingScreen extends StatelessWidget {
  const AuthLandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide =
                constraints.maxWidth >= AppConstants.desktopBreakpoint;
            final content = Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? 72 : 24,
                vertical: 40,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.route, color: AppTheme.navy, size: 52),
                    const SizedBox(height: 24),
                    Text(
                      AppConstants.appName,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: AppTheme.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'La route, simplement.',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: AppTheme.skyBlue),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Gérez vos passages, vos véhicules et vos paiements depuis un seul espace.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.black54,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton.icon(
                      onPressed: () => context.go('/auth/login'),
                      icon: const Icon(Icons.login),
                      label: const Text('Se connecter'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/auth/register'),
                      icon: const Icon(Icons.person_add_outlined),
                      label: const Text('Créer un compte'),
                    ),
                    const SizedBox(height: 28),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => context.go('/auth/professional-login'),
                        icon: const Icon(Icons.badge_outlined),
                        label: const Text('Accès professionnel'),
                      ),
                    ),
                  ],
                ),
              ),
            );
            if (!isWide) {
              return Center(child: SingleChildScrollView(child: content));
            }
            return Row(
              children: [
                Expanded(child: _LandingPanel()),
                Expanded(child: Center(child: content)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LandingPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      color: AppTheme.navy,
      padding: const EdgeInsets.all(72),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.alt_route, color: Color(0xFF65C7BC), size: 80),
          SizedBox(height: 32),
          Text(
            'Chaque trajet compte.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Un socle fiable pour la mobilité de demain.',
            style: TextStyle(
              color: Color(0xFFD5E7F4),
              fontSize: 20,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
