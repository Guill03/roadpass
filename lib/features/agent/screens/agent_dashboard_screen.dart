import 'package:flutter/material.dart';
import 'package:roadpass/features/agent/screens/agent_verification_screen.dart';
import 'package:roadpass/services/toll_catalog_service.dart';
import '../../../core/widgets/dashboard_shell.dart';
import '../../../services/auth_service.dart';
import '../../../services/passage_service.dart';

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
      contentBuilder: (context, label) {
        switch (label) {
          case 'Tableau de bord':
            return const Center(child: Text('Tableau de bord de l\'agent'));
          case 'Scanner QR':
            return AgentVerificationScreen(
              passageService: PassageService(),
              catalogService: TollCatalogService(),
            );
          case 'Transactions':
            return const Center(child: Text('Liste des transactions'));
          case 'Historique':
            return const Center(child: Text('Historique des passages'));
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }
}
