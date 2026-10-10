import 'package:flutter/material.dart';

import '../../../core/widgets/dashboard_shell.dart';
import '../../../services/auth_service.dart';
import '../../../services/payment_service.dart';
import '../../../services/prepaid_service.dart';
import '../../../services/receipt_service.dart';
import '../../../services/toll_catalog_service.dart';
import '../../../services/transaction_service.dart';
import '../../../services/vehicle_service.dart';
import 'payments_screen.dart';
import 'toll_catalog_screen.dart';
import 'transactions_screen.dart';
import 'vehicle_management_screen.dart';

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
        DashboardItem('Postes & tarifs', Icons.sell_outlined),
        DashboardItem('Mes passages', Icons.alt_route),
        DashboardItem('Paiements', Icons.credit_card_outlined),
        DashboardItem('Historique', Icons.history),
        DashboardItem('Profil', Icons.person_outline),
      ],
      contentBuilder: (context, label) {
        switch (label) {
          case 'Mes véhicules':
            return VehicleManagementScreen(
              authService: authService,
              vehicleService: VehicleService(),
              catalogService: TollCatalogService(),
            );
          case 'Postes & tarifs':
            return TollCatalogScreen(catalogService: TollCatalogService());
          case 'Mes passages':
            return TransactionsScreen(
              vehicleService: VehicleService(),
              catalogService: TollCatalogService(),
              transactionService: TransactionService(),
              paymentService: PaymentService(),
              receiptService: ReceiptService(),
              prepaidService: PrepaidService(),
            );
          case 'Paiements':
            return PaymentsScreen(
              paymentService: PaymentService(),
              transactionService: TransactionService(),
            );
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }
}
