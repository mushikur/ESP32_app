import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/ui/app_motion.dart';
import '../features/devices/device_activity_screen.dart';
import '../features/devices/devices_screen.dart';
import '../features/discovery/discover_screen.dart';
import '../features/home/home_screen.dart';
import '../features/learn/learn_home_screen.dart';
import '../features/learn/learn_project_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/workspace/workspace_screens.dart';
import 'workspace_shell.dart';

final appRouterProvider = Provider.family<GoRouter, bool>((
  ref,
  onboardingComplete,
) {
  final router = GoRouter(
    initialLocation: onboardingComplete ? WorkspaceTab.home.path : '/welcome',
    routes: [
      GoRoute(
        path: '/welcome',
        builder: (context, state) => OnboardingScreen(
          replay: state.uri.queryParameters['replay'] == '1',
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => WorkspaceShell(
          activeTab: WorkspaceTab.values.firstWhere(
            (tab) =>
                tab.path == state.uri.path ||
                (tab != WorkspaceTab.home &&
                    state.uri.path.startsWith('${tab.path}/')),
            orElse: () => WorkspaceTab.home,
          ),
          child: child,
        ),
        routes: WorkspaceTab.values
            .map(
              (tab) => GoRoute(
                path: tab.path,
                pageBuilder: (context, state) =>
                    _sectionPage(context, state, tab),
                routes: [
                  if (tab == WorkspaceTab.learn)
                    GoRoute(
                      path: ':projectId',
                      pageBuilder: (context, state) => _motionPage(
                        context,
                        state,
                        LearnProjectScreen(
                          id: state.pathParameters['projectId']!,
                        ),
                      ),
                    ),
                ],
              ),
            )
            .toList(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

Page<void> _sectionPage(
  BuildContext context,
  GoRouterState state,
  WorkspaceTab tab,
) {
  final screen = switch (tab) {
    WorkspaceTab.home => const HomeScreen(),
    WorkspaceTab.devices => const DevicesScreen(),
    WorkspaceTab.discover => const DiscoverScreen(),
    WorkspaceTab.learn => const LearnHomeScreen(),
    WorkspaceTab.automations => const AutomationsScreen(),
    WorkspaceTab.activity => const ActivityScreen(),
    WorkspaceTab.settings => const SettingsScreen(),
  };
  return _motionPage(context, state, screen);
}

Page<void> _motionPage(
  BuildContext context,
  GoRouterState state,
  Widget screen,
) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: reduced ? Duration.zero : AppMotion.standard,
    reverseTransitionDuration: reduced ? Duration.zero : AppMotion.reverse,
    child: screen,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        MediaQuery.disableAnimationsOf(context)
        ? child
        : AppMotion.page(animation, child),
  );
}
