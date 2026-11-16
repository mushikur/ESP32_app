import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart';
import '../../core/ui/surfaces.dart';
import 'device_database.dart';
import 'device_registry.dart';

String formatDeviceTime(BuildContext context, DateTime time) {
  final labels = MaterialLocalizations.of(context);
  final local = time.toLocal();
  return '${labels.formatCompactDate(local)} ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

Future<void> openDeviceHistory(
  BuildContext context,
  DeviceRegistration device,
) => Navigator.of(context, rootNavigator: true).push<void>(
  MaterialPageRoute(
    builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Connection history')),
      body: SafeArea(
        child: ScreenCanvas(child: ActivityScreen(device: device)),
      ),
    ),
  ),
);

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({this.device, super.key});
  final DeviceRegistration? device;

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  int _limit = 40;

  @override
  Widget build(BuildContext context) {
    final saved =
        ref.watch(deviceRegistryProvider).value ?? const <DeviceRegistration>[];
    final devices = {for (final item in saved) item.registrationId: item};
    final history = ref.watch(deviceHistoryProvider);
    final device = widget.device;
    final events = (history.value?.activity ?? const <ActivityEntry>[])
        .where(
          (event) =>
              devices.containsKey(event.registrationId) &&
              (device == null || device.registrationId == event.registrationId),
        )
        .toList();
    return ScreenScroll(
      key: PageStorageKey(device?.registrationId ?? 'activity'),
      children: [
        Semantics(
          header: true,
          child: Text(
            device?.name ?? 'Activity',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Connections and command outcomes saved on this phone.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        if (history.hasError && !history.hasValue)
          EmptyPanel(
            icon: Icons.error_outline,
            title: 'Could not load activity',
            description: 'Try reading the local history again.',
            action: TextButton(
              onPressed: () => ref.invalidate(deviceHistoryProvider),
              child: const Text('Try again'),
            ),
          )
        else if (history.isLoading && !history.hasValue)
          const Panel(child: Text('Loading activity…'))
        else if (events.isEmpty)
          const EmptyPanel(
            icon: Icons.history_rounded,
            title: 'No activity yet',
            description:
                'Open a device or check its connection to start the timeline.',
          )
        else ...[
          for (final event in events.take(_limit))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    IconTile(
                      _eventIcon(event.kind),
                      color:
                          event.kind == ActivityKind.connected ||
                              event.kind == ActivityKind.applied
                          ? AppColors.mint
                          : AppColors.blue,
                      size: 36,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.kind.label,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            [
                              if (device == null)
                                devices[event.registrationId]!.name,
                              formatDeviceTime(context, event.time),
                            ].join(' · '),
                            style: TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (events.length > _limit)
            OutlinedButton(
              onPressed: () => setState(() => _limit += 40),
              child: const Text('Show more'),
            ),
        ],
      ],
    );
  }

  IconData _eventIcon(ActivityKind kind) => switch (kind) {
    ActivityKind.registered || ActivityKind.verified => Icons.verified_outlined,
    ActivityKind.connected => Icons.link_rounded,
    ActivityKind.offline || ActivityKind.disconnected => Icons.link_off_rounded,
    ActivityKind.authorization => Icons.lock_outline_rounded,
    ActivityKind.applied => Icons.check_circle_outline_rounded,
    _ => Icons.info_outline_rounded,
  };
}
