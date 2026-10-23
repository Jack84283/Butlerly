import 'package:butlerly/features/foundation/presentation/legal_licenses_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app() => MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const LegalLicensesPage(),
  );

  testWidgets('desktop Legal keeps documents and reader side by side', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('desktop-legal-document-list'));
    final reader = find.byKey(const ValueKey('desktop-legal-reader-0'));
    expect(list, findsOneWidget);
    expect(reader, findsOneWidget);
    expect(tester.getRect(list).right, lessThan(tester.getRect(reader).left));
    expect(
      find.byKey(const ValueKey('desktop-legal-document-3')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('desktop-legal-document-1')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-legal-reader-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact Legal retains the existing document navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-legal-document-list')),
      findsNothing,
    );
    expect(find.text('Terms of Use'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
