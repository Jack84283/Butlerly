import 'package:butlerly/features/foundation/presentation/settings_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app() => ProviderScope(
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SettingsPage(),
    ),
  );

  testWidgets('More has no duplicate transaction or import entries', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Transactions'), findsNothing);
    expect(find.text('Add transaction'), findsNothing);
    expect(find.text('Import & export'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Optional features'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Optional features'), findsOneWidget);
  });

  testWidgets('More display-name label uses regular font weight', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(find.text('Display name').first);
    expect(label.style?.fontWeight, FontWeight.w400);
  });

  testWidgets('display-name sheet saves and can reopen without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Display name').first);
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('settings-display-name-input'));
    expect(input, findsOneWidget);
    await tester.enterText(input, 'Mia');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Mia'), findsOneWidget);

    await tester.tap(find.text('Display name').first);
    await tester.pumpAndSettle();
    final reopened = tester.widget<TextFormField>(input);
    expect(reopened.initialValue, 'Mia');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('More uses Cupertino symbols for native iOS settings controls', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byIcon(CupertinoIcons.paintbrush), findsOneWidget);
    expect(find.byIcon(Icons.palette_outlined), findsNothing);
    expect(find.byIcon(CupertinoIcons.chevron_down), findsNWidgets(5));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('desktop More follows the two-column card mockup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-more-protection')),
      findsOneWidget,
    );
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Privacy & data'), findsOneWidget);
    expect(find.text('Optional features'), findsOneWidget);
    expect(find.text('About Butlerly'), findsOneWidget);
    expect(find.text('Display name'), findsOneWidget);
    expect(find.text('Base currency'), findsOneWidget);
    expect(find.text('External AI consent'), findsOneWidget);

    final valueColumns = find.byKey(
      const ValueKey('desktop-more-value-column'),
    );
    expect(valueColumns, findsNWidgets(9));
    final firstRight = tester.getRect(valueColumns.at(0)).right;
    for (var index = 0; index < 9; index++) {
      expect(tester.getSize(valueColumns.at(index)).width, 140);
      final valueText = tester.widget<Text>(
        find.descendant(
          of: valueColumns.at(index),
          matching: find.byType(Text),
        ),
      );
      expect(valueText.textAlign, TextAlign.end);
      if (index < 8) {
        expect(
          tester.getRect(valueColumns.at(index)).right,
          closeTo(firstRight, 0.1),
        );
      }
    }

    final preferences = tester.getRect(find.text('Preferences'));
    final privacy = tester.getRect(find.text('Privacy & data'));
    expect(preferences.left, lessThan(privacy.left));
    expect(preferences.top, closeTo(privacy.top, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop More shows the dark protection banner palette', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.dark(),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final banner = tester.widget<Container>(
      find.byKey(const ValueKey('desktop-more-protection')),
    );
    expect(
      (banner.decoration! as BoxDecoration).color,
      const Color(0xFF1E342B),
    );
    expect(tester.takeException(), isNull);
  });
}
