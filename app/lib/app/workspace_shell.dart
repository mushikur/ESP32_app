import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/ui/app_motion.dart';
import '../core/ui/esp_artwork.dart';
import '../core/ui/surfaces.dart';
import 'app_theme.dart';

enum WorkspaceTab {
  home(
    '/',
    'Home',
    'Home',
    Icons.space_dashboard_outlined,
    Icons.space_dashboard_rounded,
  ),
  devices(
    '/devices',
    'Devices',
    'My Devices',
    Icons.developer_board_outlined,
    Icons.developer_board_rounded,
  ),
  discover(
    '/discover',
    'Discover',
    'Discover',
    Icons.radar_rounded,
    Icons.radar_rounded,
  ),
  learn(
    '/learn',
    'Learn',
    'Learn & Build',
    Icons.school_outlined,
    Icons.school_rounded,
  ),
  automations(
    '/automations',
    'Automate',
    'Automations',
    Icons.bolt_outlined,
    Icons.bolt_rounded,
  ),
  activity(
    '/activity',
    'Activity',
    'Activity',
    Icons.insights_outlined,
    Icons.insights_rounded,
  ),
  settings(
    '/settings',
    'Settings',
    'Settings',
    Icons.tune_rounded,
    Icons.tune_rounded,
  );

  const WorkspaceTab(
    this.path,
    this.label,
    this.nameForSpeech,
    this.icon,
    this.selectedIcon,
  );

  final String path;
  final String label;
  final String nameForSpeech;
  final IconData icon;
  final IconData selectedIcon;
}

class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({
    required this.activeTab,
    required this.child,
    super.key,
  });

  final WorkspaceTab activeTab;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion(
      value: AppTheme.overlays,
      child: Scaffold(
        body: ScreenCanvas(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _BrandBar(activeTab: activeTab),
                Expanded(child: child),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _WorkspaceNav(activeTab: activeTab),
      ),
    );
  }
}

class _BrandBar extends StatelessWidget {
  const _BrandBar({required this.activeTab});

  final WorkspaceTab activeTab;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 9),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Row(
          children: [
            AnimatedEspIoTLogo(
              motion: activeTab == WorkspaceTab.home
                  ? EspLogoMotion.entrance
                  : EspLogoMotion.still,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ESP IoT', style: text.titleLarge),
                  const SizedBox(height: 3),
                  Eyebrow('DEVICE CONTROL', color: AppColors.muted),
                ],
              ),
            ),
            if (MediaQuery.textScalerOf(context).scale(12) <= 16)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.tint(AppColors.cyan, .10),
                  border: Border.all(color: AppColors.tintLine(AppColors.cyan, .26)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lan_outlined, color: AppColors.cyan, size: 13),
                    SizedBox(width: 6),
                    Eyebrow('LOCAL MODE'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceNav extends StatelessWidget {
  const _WorkspaceNav({required this.activeTab});

  final WorkspaceTab activeTab;

  @override
  Widget build(BuildContext context) {
    Widget row(Iterable<WorkspaceTab> tabs) {
      return Row(
        children: [
          for (final tab in tabs)
            Expanded(
              child: _NavItem(tab: tab, selected: tab == activeTab),
            ),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.navigation,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(5, 5, 5, 5),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final labelWidth =
                    MediaQuery.textScalerOf(context).scale(10) * 4.5;
                final tabWidth =
                    constraints.maxWidth / WorkspaceTab.values.length;
                if (tabWidth >= 48 && tabWidth >= labelWidth) {
                  return row(WorkspaceTab.values);
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    row(WorkspaceTab.values.take(4)),
                    row(WorkspaceTab.values.skip(4)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.tab, required this.selected});

  final WorkspaceTab tab;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.duration(context, AppMotion.standard);
    final color = selected ? AppColors.cyan : AppColors.muted;
    void select() {
      if (!selected) context.go(tab.path);
    }

    return Semantics(
      button: true,
      selected: selected,
      label: tab.nameForSpeech,
      onTap: select,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey(tab),
          borderRadius: BorderRadius.circular(14),
          onTap: select,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: duration,
                  curve: AppMotion.ease,
                  width: 39,
                  height: 27,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.tint(AppColors.cyan, .20)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: MotionValue(
                      identity: selected,
                      child: Icon(
                        selected ? tab.selectedIcon : tab.icon,
                        color: color,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tab.label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
