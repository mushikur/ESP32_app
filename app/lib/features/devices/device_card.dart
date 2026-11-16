import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/ui/app_motion.dart';
import '../../core/ui/status_visuals.dart';
import '../../core/ui/surfaces.dart';

import 'device_connections.dart';
import 'device_registration.dart';

export 'device_connections.dart' show DevicePresence;

IconData deviceIcon(DeviceRegistration device) => switch (device.icon) {
  DeviceIcon.automatic => switch (device.type) {
    'lighting' => Icons.lightbulb_outline_rounded,
    'relay' => Icons.power_outlined,
    'fan' => Icons.air_rounded,
    'sensor' => Icons.thermostat_rounded,
    'robot' => Icons.smart_toy_outlined,
    _ => Icons.developer_board_outlined,
  },
  DeviceIcon.board => Icons.developer_board_outlined,
  DeviceIcon.light => Icons.lightbulb_outline_rounded,
  DeviceIcon.outlet => Icons.power_outlined,
  DeviceIcon.fan => Icons.air_rounded,
  DeviceIcon.sensor => Icons.thermostat_rounded,
  DeviceIcon.robot => Icons.smart_toy_outlined,
};

class DeviceCard extends StatelessWidget {
  const DeviceCard({
    required this.name,
    required this.category,
    required this.presence,
    this.icon = Icons.developer_board_outlined,
    this.connection,
    this.lastSeen,
    this.quickAction,
    this.onOpen,
    this.onSettings,
    super.key,
  });

  final String name;
  final String category;
  final DevicePresence presence;
  final IconData icon;
  final String? connection;
  final String? lastSeen;
  final Widget? quickAction;
  final VoidCallback? onOpen;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return MotionReveal(
      child: Panel(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onOpen,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          IconTile(icon, color: AppColors.blue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: theme.titleMedium),
                                Text(
                                  category,
                                  style: theme.bodySmall?.copyWith(
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (onSettings != null)
                  IconButton(
                    tooltip: 'Settings for $name',
                    onPressed: onSettings,
                    icon: const Icon(Icons.tune_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  MotionValue(
                    identity: presence,
                    child: StatusChip(
                      tone: presence.tone,
                      label: presence.label,
                    ),
                  ),
                  if (connection != null)
                    Text(
                      connection!,
                      style: theme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  if (lastSeen != null)
                    Text(
                      lastSeen!,
                      style: theme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                ],
              ),
            ),
            if (quickAction != null) ...[
              const SizedBox(height: 12),
              quickAction!,
            ],
          ],
        ),
      ),
    );
  }
}
