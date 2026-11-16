import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/ui/surfaces.dart';

class AutomationsScreen extends StatelessWidget {
  const AutomationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _WorkspaceSection(
      eyebrow: 'DEVICE ROUTINES',
      title: 'Automations',
      description: 'A place for routines that work with compatible devices.',
      children: [
        EmptyPanel(
          icon: Icons.bolt_rounded,
          title: 'No automations',
          description:
              'Automation setup will become available in a later phase.',
        ),
      ],
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _WorkspaceSection(
      eyebrow: 'APP PREFERENCES',
      title: 'Settings',
      description: 'Get to know your ESP IoT workspace.',
      children: [
        _AppearanceCard(),
        SizedBox(height: 12),
        _ReplayTourTile(),
        SizedBox(height: 12),
        _MethodTile(
          Icons.motion_photos_on_outlined,
          'Animation preferences',
          'ESP IoT follows the system setting for reduced motion.',
        ),
        SizedBox(height: 12),
        _MethodTile(
          Icons.info_outline_rounded,
          'ESP IoT',
          'Local device management and connection history.',
        ),
        SizedBox(height: 12),
        _PrivacyTile(),
      ],
    );
  }
}

class _ReplayTourTile extends StatelessWidget {
  const _ReplayTourTile();

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(6),
    child: ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShape.well),
      ),
      leading: IconTile(Icons.auto_awesome_rounded, color: AppColors.violet),
      title: const Text('Replay introduction'),
      subtitle: const Text('See the welcome tour again.'),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.push('/welcome?replay=1'),
    ),
  );
}

class _PrivacyTile extends StatelessWidget {
  const _PrivacyTile();

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(6),
    child: ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShape.well),
      ),
      leading: const IconTile(Icons.privacy_tip_outlined),
      title: const Text('Privacy and permissions'),
      subtitle: const Text('See what ESP IoT accesses and saves.'),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(builder: (_) => const _PrivacyScreen()),
      ),
    ),
  );
}

/// Lets the user pick the dark, light, or system appearance.
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final text = Theme.of(context).textTheme;
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(
                AppColors.isDark
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
                color: AppColors.blue,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Appearance', style: text.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      'ESP IoT is designed for its dark workspace.',
                      style: text.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode_outlined, size: 17),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode_outlined, size: 17),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('System'),
                icon: Icon(Icons.phone_android_rounded, size: 17),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (choice) =>
                ref.read(themeModeProvider.notifier).choose(choice.first),
          ),
        ],
      ),
    );
  }
}

class _PrivacyScreen extends StatelessWidget {
  const _PrivacyScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: const ScreenCanvas(
        child: SafeArea(
          child: _WorkspaceSection(
            eyebrow: 'ESP IOT',
            title: 'Privacy and permissions',
            description: 'ESP IoT has no account or cloud service.',
            children: [
              _PrivacyNote(
                'Local network',
                'Android allows the app to check your Wi-Fi connection and discover compatible devices. '
                    'Status and commands go directly to the device. Use unencrypted legacy connections only '
                    'on a Wi-Fi network you trust, and keep private information out of those requests.',
              ),
              SizedBox(height: 12),
              _PrivacyNote(
                'QR camera access',
                'Android may ask for camera access when you open the pairing scanner. If you skip or deny '
                    'camera access, use Manual address in Discover. QR images are processed on your device. '
                    'Google ML Kit can send scanner diagnostics and usage metrics to Google.',
              ),
              SizedBox(height: 12),
              _PrivacyNote(
                'Saved data and exports',
                'ESP IoT saves devices, activity and learning progress on your phone. It encrypts saved '
                    'API credentials and pairing tokens. Sketch exports go to the location you choose in '
                    'Android’s file picker, which can include a cloud storage provider.',
              ),
              SizedBox(height: 12),
              _PrivacyNote(
                'Remove saved data',
                'Use Remove device in device settings to delete its local registration and history. '
                    'To revoke a secure token on the board, use Remove pairing while it is reachable. '
                    'Clear ESP IoT storage in Android Settings to erase saved app data, including learning progress.',
              ),
              SizedBox(height: 12),
              _PrivacyNote(
                'Safe device use',
                'Control only devices you own or have permission to operate. Verify wiring and physical outputs. '
                    'Use a physical cutoff for hazardous hardware. The app’s Stop action depends on the device and connection.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote(this.title, this.body);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 4),
          Text(body),
        ],
      ),
    );
  }
}

class _WorkspaceSection extends StatelessWidget {
  const _WorkspaceSection({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.children,
  });

  final String eyebrow;
  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ScreenScroll(
      key: PageStorageKey(title),
      children: [
        Eyebrow(eyebrow),
        const SizedBox(height: 8),
        Semantics(header: true, child: Text(title, style: text.headlineLarge)),
        const SizedBox(height: 6),
        Text(
          description,
          style: text.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 22),
        ...children,
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile(this.icon, this.title, this.description);

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconTile(icon, color: AppColors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: text.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
