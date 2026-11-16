import 'package:esp_iot/core/ui/app_motion.dart';
import 'package:esp_iot/core/ui/esp_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('logo entrance moves the existing mark and settles', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: AnimatedEspIoTLogo())),
    );
    expect(find.byType(EspMark), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);

    final mark = find.byType(EspMark);
    final initial = tester.getTopLeft(mark);
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.getTopLeft(mark), isNot(initial));

    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byType(EspMark), findsOneWidget);
  });

  testWidgets('decorative loops stop offstage and with reduced motion', (
    tester,
  ) async {
    Widget app({bool visible = true, bool reduce = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: TickerMode(
          enabled: visible,
          child: DecorativeMotion(
            period: const Duration(seconds: 1),
            repeat: true,
            builder: (animation) =>
                Text(animation == null ? 'Still' : 'Moving'),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app());
    expect(find.text('Moving'), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(app(visible: false));
    expect(find.text('Still'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(app());
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(app(reduce: true));
    expect(find.text('Still'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });
}
