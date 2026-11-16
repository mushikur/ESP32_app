import 'package:esp_iot/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a palette change refreshes colors and preserves form state', (
    tester,
  ) async {
    const preview = _Preview();
    Widget app(AppPalette palette) => MaterialApp(
      home: AppPaletteScope(
        palette: palette,
        child: const Scaffold(body: preview),
      ),
    );

    await tester.pumpWidget(app(AppPalette.dark));
    await tester.enterText(find.byType(TextField), 'Saved input');
    expect(
      tester.widget<ColoredBox>(find.byKey(_Preview.fill)).color,
      AppPalette.dark.surface,
    );

    await tester.pumpWidget(app(AppPalette.light));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<ColoredBox>(find.byKey(_Preview.fill)).color,
      AppPalette.light.surface,
    );
    expect(find.text('Saved input'), findsOneWidget);

    await tester.pumpWidget(app(AppPalette.dark));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Saved input'), findsOneWidget);
  });

  test('light connection status text has sufficient contrast', () {
    const palette = AppPalette.light;
    for (final color in [palette.cyan, palette.mint]) {
      final fill = Color.alphaBlend(
        color.withValues(alpha: .12),
        palette.surface,
      );
      final contrast =
          (fill.computeLuminance() + .05) / (color.computeLuminance() + .05);
      expect(contrast, greaterThanOrEqualTo(4.5));
    }
  });
}

class _Preview extends StatelessWidget {
  const _Preview();

  static const fill = ValueKey('theme-preview-fill');

  @override
  Widget build(BuildContext context) =>
      ColoredBox(key: fill, color: AppColors.surface, child: const TextField());
}
