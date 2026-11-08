import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('desktop text scale increases reading roles without mutating base', () {
    final base = ThemeData(useMaterial3: true).textTheme;
    final desktop = ButlerlyTypography.desktopTextTheme(base);

    expect(desktop.bodyMedium!.fontSize, base.bodyMedium!.fontSize! + 1);
    expect(desktop.bodySmall!.fontSize, base.bodySmall!.fontSize! + 1);
    expect(desktop.titleLarge!.fontSize, base.titleLarge!.fontSize! + 2);
    expect(desktop.labelLarge!.fontSize, base.labelLarge!.fontSize! + 1);
    expect(base.bodyMedium!.fontSize, 14);
    expect(base.bodySmall!.fontSize, 12);
    expect(desktop.bodyMedium!.fontFamily, base.bodyMedium!.fontFamily);
  });

  for (final width in [390.0, 1400.0]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('desktop font increase is wide-only at $width, $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final original = ThemeData(useMaterial3: true, brightness: brightness);
        await tester.pumpWidget(
          MaterialApp(
            theme: original,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: AdaptiveShell(
              location: '/',
              child: Builder(
                builder: (context) => Text(
                  'Readability probe',
                  key: const ValueKey('desktop-font-probe'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final actual = tester.widget<Text>(
          find.byKey(const ValueKey('desktop-font-probe')),
        );
        final baseSize = original.textTheme.bodyMedium!.fontSize!;
        expect(actual.style?.fontSize, width >= 1024 ? baseSize + 1 : baseSize);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
