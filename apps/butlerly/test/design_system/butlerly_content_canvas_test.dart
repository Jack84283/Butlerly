import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('medium and desktop canvases match their content surface', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(900, 900), const Size(1440, 900)]) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: const Scaffold(
              body: ButlerlyResponsiveBody(child: Center(child: Text('Body'))),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final canvas = tester.widget<ColoredBox>(
          find.byKey(const ValueKey('butlerly-responsive-body-canvas')),
        );
        final surface = tester.widget<Material>(
          find.byKey(
            const ValueKey('butlerly-responsive-body-content-surface'),
          ),
        );
        final expected = brightness == Brightness.dark
            ? ButlerlySemanticColors.dark.background
            : ButlerlySemanticColors.light.background;
        expect(canvas.color, expected);
        expect(surface.color, canvas.color);
        expect(tester.takeException(), isNull);
      }
    }
  });
}
