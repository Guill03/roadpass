import 'package:flutter/material.dart';

import '../../../core/widgets/dashboard_shell.dart';
import '../../../services/auth_service.dart';

class UserDashboardScreen extends StatelessWidget {
  const UserDashboardScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return DashboardShell(
      authService: authService,
      title: 'Espace utilisateur',
      subtitle:
          'Retrouvez vos véhicules, paiements et passages au même endroit.',
      items: const [
        DashboardItem('Accueil', Icons.home_outlined),
        DashboardItem('Mes véhicules', Icons.directions_car_outlined),
        DashboardItem('Paiements', Icons.credit_card_outlined),
        DashboardItem('Historique', Icons.history),
        DashboardItem('Profil', Icons.person_outline),
      ],
    );
  }
}
