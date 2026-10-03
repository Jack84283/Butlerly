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
    expect(find.text('Privacy & data'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Optional features'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Optional features'), findsOneWidget);
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
}
