import 'package:flutter/material.dart';

import '../../../core/widgets/dashboard_shell.dart';
import '../../../services/auth_service.dart';

class AgentDashboardScreen extends StatelessWidget {
  const AgentDashboardScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return DashboardShell(
      authService: authService,
      title: 'Espace agent',
      subtitle: 'Suivez les opérations de votre poste de péage.',
      items: const [
        DashboardItem('Tableau de bord', Icons.dashboard_outlined),
        DashboardItem('Scanner QR', Icons.qr_code_scanner),
        DashboardItem('Transactions', Icons.receipt_long_outlined),
        DashboardItem('Historique', Icons.history),
        DashboardItem('Profil', Icons.person_outline),
      ],
    );
  }
}
