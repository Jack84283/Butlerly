import 'package:butlerly/features/foundation/presentation/privacy_data_page.dart';
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
      home: const PrivacyDataPage(),
    ),
  );

  testWidgets(
    'Privacy and data uses Cupertino symbols for native iOS actions',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.byIcon(CupertinoIcons.archivebox), findsOneWidget);
      expect(
        find.byIcon(CupertinoIcons.arrow_counterclockwise),
        findsOneWidget,
      );
      expect(find.byIcon(CupertinoIcons.arrow_down_doc), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.trash), findsOneWidget);
      expect(find.byIcon(Icons.backup_outlined), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets('wide Privacy & Data shows real actions in a two-column dashboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    for (final key in const [
      'desktop-privacy-local-banner',
      'desktop-privacy-backup',
      'desktop-privacy-export',
      'desktop-privacy-management',
      'desktop-privacy-danger',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(find.text('Backup & Recovery'), findsOneWidget);
    expect(find.text('Data Export'), findsOneWidget);
    expect(find.text('Data Management'), findsOneWidget);
    expect(find.text('Danger Zone'), findsOneWidget);

    final backup = tester.getRect(
      find.byKey(const ValueKey('desktop-privacy-backup')),
    );
    final export = tester.getRect(
      find.byKey(const ValueKey('desktop-privacy-export')),
    );
    final management = tester.getRect(
      find.byKey(const ValueKey('desktop-privacy-management')),
    );
    expect(backup.left, lessThan(export.left));
    expect(backup.top, closeTo(export.top, 1));
    expect(management.top, greaterThan(backup.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact Privacy & Data preserves its original action list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-privacy-local-banner')),
      findsNothing,
    );
    expect(find.text('Local data controls'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
