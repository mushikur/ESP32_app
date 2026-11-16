import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/ui/app_motion.dart';
import '../../core/ui/esp_artwork.dart';
import '../../core/ui/status_visuals.dart';
import '../../core/ui/surfaces.dart';
import '../connection/device_connection_screen.dart';
import '../devices/device_card.dart';
import '../devices/device_connections.dart';
import '../devices/device_database.dart';
import '../devices/device_registry.dart';
import '../discovery/discovery_service.dart';
import '../discovery/local_discovery_platform.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final entries = ref.watch(deviceRegistryProvider).value;
    final count = entries?.length;
    final observations = ref.watch(deviceConnectionsProvider);
    final presence = entries
        ?.map((device) => presenceOf(observations, device))
        .toList();
    final history = ref.watch(deviceHistoryProvider);
    final recent = [
      for (final device in entries ?? const <DeviceRegistration>[])
        if (history.value?.usage[device.registrationId]?.lastOpened
            case final opened?)
          (device: device, opened: opened),
    ]..sort((a, b) => b.opened.compareTo(a.opened));
    return ScreenScroll(
      key: const PageStorageKey('home'),
      children: [
        Eyebrow(greetingFor(DateTime.now()).toUpperCase()),
        const SizedBox(height: 8),
        Semantics(
          header: true,
          child: Text('Command center', style: text.headlineLarge),
        ),
        const SizedBox(height: 6),
        Text(
          'Connect and control your ESP32 projects.',
          style: text.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 22),
        MotionReveal(child: _DiscoveryHero(hasDevices: (count ?? 0) > 0)),
        const SizedBox(height: 25),
        const SectionHeading('Device overview'),
        const SizedBox(height: 12),
        MotionReveal(
          delay: const Duration(milliseconds: 45),
          child: _Overview(
            count: count,
            connected: presence
                ?.where((status) => status == DevicePresence.connected)
                .length,
            offline: presence
                ?.where((status) => status == DevicePresence.offline)
                .length,
          ),
        ),
        if (presence?.where((status) => status == DevicePresence.unknown).length
            case final int unchecked when unchecked > 0) ...[
          const SizedBox(height: 8),
          Text(
            '$unchecked ${unchecked == 1 ? 'device has' : 'devices have'} unknown status.',
            style: TextStyle(color: AppColors.muted),
          ),
        ],
        const SizedBox(height: 15),
        const MotionReveal(
          delay: Duration(milliseconds: 90),
          child: _NetworkPanel(),
        ),
        const SizedBox(height: 24),
        const SectionHeading('Recently used'),
        const SizedBox(height: 12),
        if (history.hasError && recent.isEmpty && (count ?? 0) > 0)
          const Panel(child: Text('Recent devices could not be loaded.'))
        else if (recent.isEmpty)
          const EmptyPanel(
            icon: Icons.history_rounded,
            title: 'No recent devices',
            description: 'Open a saved device to find it here next time.',
          )
        else
          for (final item in recent.take(3)) ...[
            Panel(
              padding: const EdgeInsets.all(5),
              child: ListTile(
                leading: IconTile(deviceIcon(item.device), size: 38),
                title: Text(item.device.name),
                subtitle: Text(presenceOf(observations, item.device).label),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => openDeviceConnection(context, item.device),
              ),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 16),
        const MotionReveal(child: _LearnShortcut()),
      ],
    );
  }
}

/// A time-of-day greeting for the page eyebrow.
String greetingFor(DateTime now) => switch (now.hour) {
  >= 5 && < 12 => 'Good morning',
  >= 12 && < 17 => 'Good afternoon',
  >= 17 && < 22 => 'Good evening',
  _ => 'Your ESP32 workspace',
};

class _LearnShortcut extends StatelessWidget {
  const _LearnShortcut();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      padding: const EdgeInsets.all(6),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.well),
        ),
        leading: IconTile(Icons.school_rounded, color: AppColors.violet),
        title: Text('Learn & Build', style: text.titleMedium),
        subtitle: const Text('Guided electronics projects, no board needed.'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.go('/learn'),
      ),
    );
  }
}

class _DiscoveryHero extends StatelessWidget {
  const _DiscoveryHero({required this.hasDevices});

  final bool hasDevices;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scaled = MediaQuery.textScalerOf(context).scale(16) > 20;
    return LayoutBuilder(
      builder: (context, constraints) {
        final art = constraints.maxWidth >= 300 && !scaled;
        final artWidth = (constraints.maxWidth * .58).clamp(170.0, 258.0);
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.isDark
                  ? const [
                      Color(0xFF173354),
                      Color(0xFF111D34),
                      Color(0xFF191938),
                    ]
                  : [
                      AppColors.tint(AppColors.blue, .16),
                      AppColors.surface,
                      AppColors.tint(AppColors.violet, .13),
                    ],
            ),
            border: Border.all(color: AppColors.tintLine(AppColors.blue, .34)),
            borderRadius: BorderRadius.circular(AppShape.hero),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Stack(
            children: [
              if (art)
                Positioned(
                  top: -4,
                  right: -5,
                  width: artWidth,
                  height: artWidth,
                  child: const OrbitArtwork(animate: true, repeat: false),
                ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('GET STARTED'),
                    const SizedBox(height: 9),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: art
                            ? constraints.maxWidth * .54
                            : double.infinity,
                      ),
                      child: Text(
                        hasDevices
                            ? 'Find more devices'
                            : 'Add your first device',
                        style: text.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => context.go('/discover'),
                      icon: const Icon(Icons.radar_rounded, size: 19),
                      label: const Text('Discover devices'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.count,
    required this.connected,
    required this.offline,
  });

  final int? count, connected, offline;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 278 ||
            MediaQuery.textScalerOf(context).scale(14) > 19;
        final width = compact
            ? constraints.maxWidth
            : (constraints.maxWidth - 16) / 3;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: width,
              child: _CountTile(
                'Registered',
                Icons.grid_view_rounded,
                AppColors.blue,
                count,
              ),
            ),
            SizedBox(
              width: width,
              child: _CountTile(
                'Connected',
                Icons.link_rounded,
                AppColors.mint,
                connected,
                tone: StatusTone.live,
              ),
            ),
            SizedBox(
              width: width,
              child: _CountTile(
                'Offline',
                Icons.portable_wifi_off_rounded,
                AppColors.violet,
                offline,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile(this.label, this.icon, this.tint, this.count, {this.tone});

  final String label;
  final IconData icon;
  final Color tint;
  final int? count;
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: count == null
          ? '$label count unavailable'
          : '$count $label devices',
      excludeSemantics: true,
      child: Panel(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconTile(icon, color: tint, size: 30),
                const Spacer(),
                if (tone != null && (count ?? 0) > 0) StatusDot(tone!, size: 7),
              ],
            ),
            const SizedBox(height: 10),
            if (count == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 5),
                child: SkeletonBox(height: 22, width: 34),
              )
            else
              MotionValue(
                identity: count,
                child: Text('$count', style: text.headlineMedium),
              ),
            const SizedBox(height: 2),
            Text(
              label,
              style: text.bodySmall?.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkPanel extends ConsumerStatefulWidget {
  const _NetworkPanel();

  @override
  ConsumerState<_NetworkPanel> createState() => _NetworkPanelState();
}

class _NetworkPanelState extends ConsumerState<_NetworkPanel> {
  late final AppLifecycleListener _lifecycle;
  Timer? _poll;

  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: _stopPolling,
      onPause: _stopPolling,
      onResume: () {
        _startPolling();
        WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
        WidgetsBinding.instance.ensureVisualUpdate();
      },
    );
    if (_foreground) _startPolling();
  }

  void _startPolling() {
    _poll ??= Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  void _refresh() {
    if (!mounted ||
        !_foreground ||
        !TickerMode.valuesOf(context).enabled ||
        ModalRoute.of(context)?.isCurrent == false ||
        ref.read(wifiSnapshotProvider).isLoading) {
      return;
    }
    ref.invalidate(wifiSnapshotProvider);
  }

  @override
  void dispose() {
    _stopPolling();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final network = ref.watch(wifiSnapshotProvider);
    final scope = network.hasError ? null : network.value;
    final active = scope?.isDefault == true;
    final tone = active
        ? StatusTone.live
        : network.isLoading
        ? StatusTone.waiting
        : StatusTone.fault;
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconTile(
            active ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            color: tone.color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Local network', style: text.titleMedium),
                const SizedBox(height: 3),
                MotionValue(
                  identity: (
                    scope?.address,
                    scope?.prefix,
                    scope?.isDefault,
                    network.isLoading,
                  ),
                  child: Text(
                    scope != null && active
                        ? 'Wi-Fi available · ${scope.address}/${scope.prefix}'
                        : scope != null
                        ? const DiscoveryFailure('wifiNotDefault').message
                        : network.isLoading
                        ? 'Checking Wi-Fi…'
                        : 'Local Wi-Fi is unavailable.',
                    style: text.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
          StatusDot(tone, size: 8),
        ],
      ),
    );
  }
}
