import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/auth_provider.dart';
import 'utils/fullscreen_helper.dart';

class AppShell extends ConsumerStatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _isCollapsed = false;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _isFullscreen = FullscreenHelper.isFullscreen();
  }

  int _getSelectedIndex(String location) {
    if (location.startsWith('/home') ||
        location.startsWith('/zone-preview') ||
        location.startsWith('/floor-plan')) {
      return 1;
    }
    if (location.startsWith('/hotel-status')) return 2;
    if (location.startsWith('/alarms')) return 3;
    if (location.startsWith('/service-status')) return 4;
    if (location.startsWith('/reports')) return 5;
    if (location.startsWith('/settings')) return 6;
    return 0; // Dashboard /
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _getSelectedIndex(location);

    final destinations = [
      const _NavDestination(label: 'Dashboard', icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, route: '/'),
      const _NavDestination(label: 'Home', icon: Icons.home_outlined, activeIcon: Icons.home, route: '/home'),
      const _NavDestination(label: 'Hotel Status', icon: Icons.hotel_outlined, activeIcon: Icons.hotel, route: '/hotel-status'),
      const _NavDestination(label: 'Alarms', icon: Icons.notifications_outlined, activeIcon: Icons.notifications, route: '/alarms'),
      const _NavDestination(label: 'Service Status', icon: Icons.room_service_outlined, activeIcon: Icons.room_service, route: '/service-status'),
      const _NavDestination(label: 'Reports', icon: Icons.description_outlined, activeIcon: Icons.description, route: '/reports'),
      if (authState.isAdmin)
        const _NavDestination(label: 'Settings', icon: Icons.settings_outlined, activeIcon: Icons.settings, route: '/settings'),
    ];

    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(context, authState, destinations, selectedIndex),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Column(
              children: [
                _buildHeader(context, authState),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, AuthState authState, List<_NavDestination> destinations, int selectedIndex) {
    return Container(
      width: _isCollapsed ? 76 : 232,
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Logo Area
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/vanpeelogo.png',
                  width: _isCollapsed ? 44 : 68,
                  height: _isCollapsed ? 44 : 68,
                  fit: BoxFit.contain,
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          // Navigation Items
          Expanded(
            child: ListView.builder(
              itemCount: destinations.length,
              itemBuilder: (context, index) {
                final d = destinations[index];
                final isSelected = selectedIndex == index;
                return _SidebarItem(
                  destination: d,
                  isSelected: isSelected,
                  isCollapsed: _isCollapsed,
                  onTap: () {
                    if (!isSelected) {
                      context.go(d.route);
                    }
                  },
                );
              },
            ),
          ),
          // Sidebar Footer
          _buildSidebarFooter(),
        ],
      ),
    );
  }

  Widget _buildSidebarFooter() {
    return Column(
      children: [
        const Divider(height: 1),
        _SidebarItem(
          destination: const _NavDestination(
            label: 'Logout',
            icon: Icons.logout_outlined,
            activeIcon: Icons.logout,
            route: '/logout',
          ),
          isSelected: false,
          isCollapsed: _isCollapsed,
          onTap: () => _handleLogout(),
          color: Colors.redAccent,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, AuthState authState) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.05),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(_isCollapsed ? Icons.menu_open : Icons.menu),
            onPressed: () => setState(() => _isCollapsed = !_isCollapsed),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: 'User menu',
            onSelected: (value) {
              if (value == 'switch-user') {
                _handleLogout();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'switch-user',
                child: Row(
                  children: [
                    Icon(Icons.switch_account_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Switch user'),
                  ],
                ),
              ),
            ],
            child: Row(
              children: [
                // User Info
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      authState.user?.displayName ?? authState.user?.username ?? 'User',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      authState.role.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.person, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: _isFullscreen ? 'Exit fullscreen' : 'Enter fullscreen',
            icon: Icon(
              _isFullscreen
                  ? Icons.fullscreen_exit_outlined
                  : Icons.fullscreen_outlined,
            ),
            onPressed: () async {
              await FullscreenHelper.toggle();
              if (!mounted) return;
              setState(() {
                _isFullscreen = FullscreenHelper.isFullscreen();
              });
            },
          ),
        ],
      ),
    );
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authProvider.notifier).logout();
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final _NavDestination destination;
  final bool isSelected;
  final bool isCollapsed;
  final VoidCallback onTap;
  final Color? color;

  const _SidebarItem({
    required this.destination,
    required this.isSelected,
    required this.isCollapsed,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = color ?? Colors.blue;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              const SizedBox(width: 12),
              Icon(
                isSelected ? destination.activeIcon : destination.icon,
                color: isSelected ? activeColor : theme.colorScheme.onSurface.withOpacity(0.6),
                size: 24,
              ),
              if (!isCollapsed) ...[
                const SizedBox(width: 16),
                Text(
                  destination.label,
                  style: TextStyle(
                    color: isSelected ? activeColor : theme.colorScheme.onSurface.withOpacity(0.8),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NavDestination {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String route;

  const _NavDestination({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.route,
  });
}
