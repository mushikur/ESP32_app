import 'package:esp_iot/app/app_theme.dart';
import 'package:esp_iot/features/workspace/workspace_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('choosing Light switches the palette and the rendered theme', (
    tester,
  ) async {
    late BuildContext inner;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ref.watch(themeModeProvider),
            builder: (context, child) => AppPaletteScope(
              palette: Theme.of(context).brightness == Brightness.dark
                  ? AppPalette.dark
                  : AppPalette.light,
              child: Builder(
                builder: (context) {
                  inner = context;
                  return child ?? const SizedBox.shrink();
                },
              ),
            ),
            home: const Scaffold(body: SettingsScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(Theme.of(inner).brightness, Brightness.dark);
    expect(AppColors.isDark, isTrue);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(Theme.of(inner).brightness, Brightness.light);
    expect(AppColors.isDark, isFalse);
    expect(AppColors.background, AppPalette.light.background);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isTrue);
  });
}
