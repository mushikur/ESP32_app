import 'package:esp_iot/app/app_theme.dart';
import 'package:esp_iot/core/ui/esp_artwork.dart';
import 'package:esp_iot/core/ui/status_visuals.dart';
import 'package:esp_iot/core/ui/surfaces.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the shared surfaces in both palettes.
///
/// Running with `--update-goldens` writes the images, which is how the light
/// theme gets reviewed without a device.
void main() {
  Widget sample(Brightness brightness) {
    final palette = brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.of(brightness),
      home: AppPaletteScope(
        palette: palette,
        child: Scaffold(
          body: ScreenCanvas(
            child: SafeArea(
              child: ScreenScroll(
                children: [
                  Row(
                    children: [
                      const EspMark(),
                      const SizedBox(width: 10),
                      Builder(
                        builder: (context) => Text(
                          'ESP IoT',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Eyebrow('YOUR ESP32 WORKSPACE'),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (context) => Text(
                      'Command center',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const IconTile(Icons.wifi_rounded),
                            const SizedBox(width: 12),
                            const Expanded(child: Text('Local network')),
                            StatusDot(StatusTone.live),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: const [
                            StatusChip(
                              tone: StatusTone.live,
                              label: 'Connected',
                            ),
                            StatusChip(
                              tone: StatusTone.waiting,
                              label: 'Checking',
                            ),
                            StatusChip(tone: StatusTone.idle, label: 'Offline'),
                            StatusChip(
                              tone: StatusTone.fault,
                              label: 'Needs attention',
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            FilledButton(
                              onPressed: () {},
                              child: const Text('Discover'),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: () {},
                              child: const Text('Settings'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const EmptyPanel(
                    icon: Icons.history_rounded,
                    title: 'No recent devices',
                    description:
                        'Open a saved device to find it here next time.',
                  ),
                  const SizedBox(height: 12),
                  const SkeletonBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('dark palette', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(sample(Brightness.dark));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/palette_dark.png'),
    );
  });

  testWidgets('light palette', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(sample(Brightness.light));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/palette_light.png'),
    );
  });
}
