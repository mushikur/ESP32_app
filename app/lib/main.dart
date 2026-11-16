import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_router.dart';
import 'app/app_theme.dart';
import 'core/ui/app_motion.dart';
import 'core/ui/esp_artwork.dart';
import 'core/ui/surfaces.dart';
import 'features/onboarding/onboarding_store.dart';

void main() {
  runApp(const ProviderScope(child: EspIotApp()));
}

class EspIotApp extends ConsumerWidget {
  const EspIotApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarding = ref.watch(onboardingCompleteProvider);
    final mode = ref.watch(themeModeProvider);
    if (onboarding.isLoading) {
      return MaterialApp(
        title: 'ESP IoT',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        debugShowCheckedModeBanner: false,
        builder: _motionBuilder,
        home: const _LaunchScreen(),
      );
    }
    return MaterialApp.router(
      title: 'ESP IoT',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      debugShowCheckedModeBanner: false,
      builder: _motionBuilder,
      routerConfig: ref.watch(appRouterProvider(onboarding.value ?? false)),
    );
  }
}

Widget _motionBuilder(BuildContext context, Widget? child) => AppPaletteScope(
  palette: Theme.of(context).brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light,
  child: MotionLifecycle(child: child ?? const SizedBox.shrink()),
);

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlays,
      child: Scaffold(
        body: ScreenCanvas(
          child: Stack(
            fit: StackFit.expand,
            children: [
              const LaunchParticles(),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AnimatedEspIoTLogo(
                      size: 68,
                      motion: EspLogoMotion.launch,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'ESP IoT',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 18),
                    if (!AppMotion.enabled(context))
                      const Text('Opening workspace')
                    else
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: 'Opening workspace',
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
