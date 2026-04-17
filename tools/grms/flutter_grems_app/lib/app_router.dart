import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pages/dashboard_page.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/hotel_status_page.dart';
import 'pages/zone_preview_page.dart';
import 'pages/floor_plan_page.dart';
import 'pages/alarms_page.dart';
import 'pages/reports_page.dart';
import 'pages/service_status_page.dart';
import 'pages/settings_page.dart';
import 'providers/auth_provider.dart';
import 'app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    redirect: (context, state) {
      if (!authState.isInitialized) return null;

      final isLoggingIn = state.matchedLocation == '/login';
      if (!authState.isAuthenticated) {
        return isLoggingIn ? null : '/login';
      }

      if (isLoggingIn) return '/';

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(path: '/home', builder: (context, state) => const HomePage()),
          GoRoute(
            path: '/hotel-status',
            builder: (context, state) {
              final zone = state.uri.queryParameters['zone'];
              final floor = state.uri.queryParameters['floor'];
              return HotelStatusPage(
                initialZone: zone,
                initialFloor: floor,
              );
            },
          ),
          GoRoute(
            path: '/zone-preview',
            builder: (context, state) {
              final zone = state.uri.queryParameters['zone'];
              return ZonePreviewPage(initialZone: zone);
            },
          ),
          GoRoute(
            path: '/floor-plan',
            builder: (context, state) {
              final zone = state.uri.queryParameters['zone'];
              final floor = state.uri.queryParameters['floor'];
              return FloorPlanPage(initialZone: zone, initialFloor: floor);
            },
          ),
          GoRoute(
            path: '/alarms',
            builder: (context, state) => const AlarmsPage(),
          ),
          GoRoute(
            path: '/service-status',
            builder: (context, state) => const ServiceStatusPage(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportsPage(),
          ),
          GoRoute(
            path: '/settings',
            redirect: (context, state) {
              if (!authState.isAdmin) return '/';
              return null;
            },
            builder: (context, state) => const SettingsPage(),
          ),
        ],
      ),
    ],
  );
});
