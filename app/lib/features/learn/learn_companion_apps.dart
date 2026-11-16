import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart';
import '../../core/ui/surfaces.dart';
import 'learn_catalog.dart';

/// An Arduino-published Android app that is useful alongside these lessons.
typedef CompanionApp = ({
  String applicationId,
  String name,
  LearnText purpose,
  IconData icon,
  Color tint,
});

/// Opens a Google Play listing.
///
/// Only an application id crosses the channel; the platform side builds the
/// store address, so no arbitrary URL can be opened from Dart.
abstract interface class AppListingLauncher {
  Future<void> open(String applicationId);
}

class PlayStoreLauncher implements AppListingLauncher {
  const PlayStoreLauncher();

  static const _channel = MethodChannel('esp_iot/app_listing');

  @override
  Future<void> open(String applicationId) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw const CompanionAppFailure('Google Play is available on Android.');
    }
    try {
      await _channel.invokeMethod<void>('openListing', {
        'applicationId': applicationId,
      });
    } on PlatformException catch (error) {
      throw CompanionAppFailure(
        error.code == 'storeUnavailable'
            ? 'Google Play could not be opened on this device.'
            : 'This app listing could not be opened.',
      );
    } on MissingPluginException {
      throw const CompanionAppFailure(
        'Opening Google Play is unavailable in this build.',
      );
    }
  }
}

class CompanionAppFailure implements Exception {
  const CompanionAppFailure(this.message);
  final String message;
}

final appListingLauncherProvider = Provider<AppListingLauncher>(
  (_) => const PlayStoreLauncher(),
);

/// Arduino's own Android apps, verified published by Arduino on Google Play.
///
/// Neither one compiles or uploads a sketch; that still needs the Arduino IDE
/// on a computer, which the upload steps above describe.
const learnCompanionApps = <CompanionApp>[
  (
    applicationId: 'cc.arduino.cloudiot',
    name: 'Arduino IoT Cloud Remote',
    purpose: (
      en:
          'Watch and control an Arduino Cloud dashboard from your phone once a '
          'board is already running. You build the dashboard on a computer.',
      bn:
          'বোর্ড চালু হয়ে গেলে ফোন থেকে Arduino Cloud ড্যাশবোর্ড দেখা ও '
          'নিয়ন্ত্রণ করা যায়। ড্যাশবোর্ড বানাতে হয় কম্পিউটারে।',
    ),
    icon: Icons.cloud_outlined,
    tint: Color(0xFF67E5F5),
  ),
  (
    applicationId: 'cc.arduino.sciencejournal',
    name: 'Arduino Science Journal',
    purpose: (
      en:
          'Record and graph readings using your phone’s own sensors, a '
          'simple way to get used to how sensor data behaves.',
      bn:
          'ফোনের নিজস্ব সেন্সর দিয়ে পরিমাপ রেকর্ড ও গ্রাফ করা যায়। সেন্সরের '
          'ডেটা কেমন আচরণ করে তা বোঝার সহজ উপায়।',
    ),
    icon: Icons.science_outlined,
    tint: Color(0xFFB8AAFF),
  ),
];

/// Lists Arduino's mobile apps with a direct Google Play link for each.
class LearnCompanionApps extends ConsumerStatefulWidget {
  const LearnCompanionApps({required this.language, super.key});

  final LearnLanguage language;

  @override
  ConsumerState<LearnCompanionApps> createState() => _LearnCompanionAppsState();
}

class _LearnCompanionAppsState extends ConsumerState<LearnCompanionApps> {
  String? _opening;

  Future<void> _open(CompanionApp app) async {
    if (_opening != null) return;
    setState(() => _opening = app.applicationId);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(appListingLauncherProvider).open(app.applicationId);
    } on CompanionAppFailure catch (failure) {
      messenger?.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final text = Theme.of(context).textTheme;
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            language.pick('Arduino’s mobile apps', 'Arduino-এর মোবাইল অ্যাপ'),
            style: text.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            language.pick(
              'Arduino publishes these on Google Play. They are useful alongside '
                  'the lessons, but neither one can upload a sketch — that still '
                  'needs the Arduino IDE on a computer.',
              'Arduino এগুলো Google Play-তে প্রকাশ করে। পাঠের পাশাপাশি কাজে লাগে, '
                  'তবে কোনোটিই স্কেচ আপলোড করতে পারে না — তার জন্য কম্পিউটারে '
                  'Arduino IDE লাগবেই।',
            ),
            style: text.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          for (final app in learnCompanionApps) ...[
            _CompanionTile(
              app: app,
              language: language,
              busy: _opening == app.applicationId,
              onOpen: () => _open(app),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _CompanionTile extends StatelessWidget {
  const _CompanionTile({
    required this.app,
    required this.language,
    required this.busy,
    required this.onOpen,
  });

  final CompanionApp app;
  final LearnLanguage language;
  final bool busy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final label = language.pick(
      'Open ${app.name} on Google Play',
      'Google Play-তে ${app.name} খুলুন',
    );
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: AppColors.tint(app.tint, .07),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: AppColors.tintLine(app.tint, .22)),
          borderRadius: BorderRadius.circular(AppShape.well),
        ),
        child: InkWell(
          onTap: busy ? null : onOpen,
          borderRadius: BorderRadius.circular(AppShape.well),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTile(app.icon, color: app.tint, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(app.name, style: text.titleSmall),
                      const SizedBox(height: 3),
                      Text(
                        language.text(app.purpose),
                        style: text.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox.square(
                  dimension: 22,
                  child: busy
                      ? const Padding(
                          padding: EdgeInsets.all(3),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.open_in_new_rounded,
                          size: 19,
                          color: app.tint,
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
