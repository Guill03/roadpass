import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import 'profile_section.dart';

class DashboardItem {
  const DashboardItem(this.label, this.icon);

  final String label;
  final IconData icon;
}

class DashboardShell extends StatefulWidget {
  const DashboardShell({
    super.key,
    required this.authService,
    required this.title,
    required this.subtitle,
    required this.items,
    this.contentBuilder,
  });

  final AuthService authService;
  final String title;
  final String subtitle;
  final List<DashboardItem> items;
  final Widget Function(BuildContext context, String section)? contentBuilder;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  int _selectedIndex = 0;

  RoadUser get _user => widget.authService.currentUser!;

  Future<void> _logout() async {
    await widget.authService.logout();
    if (mounted) {
      context.go('/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < AppConstants.mobileBreakpoint;
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.items[_selectedIndex].label),
            actions: [
              if (!isMobile)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(child: Text(_user.fullName)),
                ),
              IconButton(
                onPressed: _logout,
                tooltip: 'Se déconnecter',
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: isMobile ? _buildMobileBody() : _buildDesktopBody(),
          bottomNavigationBar: isMobile
              ? NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) =>
                      setState(() => _selectedIndex = index),
                  destinations: widget.items
                      .map(
                        (item) => NavigationDestination(
                          icon: Icon(item.icon),
                          label: item.label,
                        ),
                      )
                      .toList(),
                )
              : null,
        );
      },
    );
  }

  Widget _buildDesktopBody() {
    return Row(
      children: [
        Container(
          width: 260,
          color: AppTheme.navy,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.route, color: Colors.white),
                    SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'RoadPass',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.items.length,
                  itemBuilder: (context, index) => _navItem(index),
                ),
              ),
              TextButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Color(0xFFD5E7F4)),
                label: const Text(
                  'Se déconnecter',
                  style: TextStyle(color: Color(0xFFD5E7F4)),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _content()),
      ],
    );
  }

  Widget _navItem(int index) {
    final selected = index == _selectedIndex;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        selected: selected,
        selectedTileColor: const Color(0xFF234C6C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(
          widget.items[index].icon,
          color: selected ? Colors.white : const Color(0xFFB8CCDC),
        ),
        title: Text(
          widget.items[index].label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFFB8CCDC),
          ),
        ),
        onTap: () => setState(() => _selectedIndex = index),
      ),
    );
  }

  Widget _buildMobileBody() => _content();

  Widget _content() {
    final label = widget.items[_selectedIndex].label;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bonjour ${_user.prenom}',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 28),
            label == 'Profil'
                ? ProfileSection(
                    authService: widget.authService,
                    onSaved: () => setState(() {}),
                  )
                : widget.contentBuilder?.call(context, label) ??
                      (_selectedIndex == 0 ? _overview() : _placeholder(label)),
          ],
        ),
      ),
    );
  }

  Widget _overview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppTheme.skyBlue.withAlpha(30),
                  child: const Icon(Icons.route, color: AppTheme.skyBlue),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Votre espace est prêt. Les fonctionnalités métier seront ajoutées progressivement.',
                    style: TextStyle(fontSize: 16, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _statCard('Passages ce mois', '—', Icons.alt_route),
            _statCard(
              'Solde disponible',
              '—',
              Icons.account_balance_wallet_outlined,
            ),
            _statCard('Dernière activité', '—', Icons.schedule),
          ],
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppTheme.skyBlue),
              const SizedBox(height: 18),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(String label) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              label == 'Scanner QR'
                  ? Icons.qr_code_scanner
                  : Icons.construction_outlined,
              size: 42,
              color: AppTheme.skyBlue,
            ),
            const SizedBox(height: 20),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              label == 'Scanner QR'
                  ? 'Le scanner QR sera connecté au parcours de validation des passages.'
                  : 'Cette section est prête à recevoir ses fonctionnalités métier.',
              style: const TextStyle(color: Colors.black54, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
