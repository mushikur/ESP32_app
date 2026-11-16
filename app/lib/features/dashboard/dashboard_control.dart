import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/protocol/device_descriptor.dart';
import '../connection/api_profile.dart';
import 'dashboard_layout.dart';

class DashboardControl {
  const DashboardControl._(
    this.id,
    this.name,
    this.type,
    this.unit,
    this.confirm,
    this.min,
    this.max,
    this.step,
    this.directions,
  );

  factory DashboardControl.universal(DeviceCapability capability) =>
      DashboardControl._(
        capability.id,
        capability.name,
        capability.type,
        capability.unit,
        capability.confirm,
        capability.min,
        capability.max,
        capability.step,
        capability.directions,
      );

  factory DashboardControl.legacy(ProfileControl control) => DashboardControl._(
    control.id,
    control.name,
    control.type,
    control.unit,
    true,
    control.min,
    control.max,
    control.step,
    const [],
  );

  final String id, name, type, unit;
  final bool confirm;
  final num? min, max, step;
  final List<String> directions;
}

IconData tileIcon(TileIcon icon, String type) => switch (icon) {
  TileIcon.automatic => switch (type) {
    'switch' => Icons.power_settings_new_rounded,
    'range' => Icons.tune_rounded,
    'sensor' => Icons.monitor_heart_outlined,
    'action' => Icons.bolt_rounded,
    'motion' => Icons.gamepad_outlined,
    _ => Icons.extension_outlined,
  },
  TileIcon.light => Icons.lightbulb_outline_rounded,
  TileIcon.power => Icons.power_settings_new_rounded,
  TileIcon.speed => Icons.speed_rounded,
  TileIcon.thermometer => Icons.thermostat_rounded,
  TileIcon.tune => Icons.tune_rounded,
  TileIcon.bolt => Icons.bolt_rounded,
};

Color tileColor(TileColor color) => switch (color) {
  TileColor.cyan => AppColors.cyan,
  TileColor.blue => AppColors.blue,
  TileColor.violet => AppColors.violet,
  TileColor.mint => AppColors.mint,
  TileColor.amber => AppColors.amber,
};
