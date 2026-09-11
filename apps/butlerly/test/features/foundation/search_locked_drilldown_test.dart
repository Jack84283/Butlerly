import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'production router keeps locked Search as a back-navigable detail route',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: appRouter,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      );

      appRouter.go('/insights');
      await tester.pumpAndSettle();
      expect(find.text('Insights'), findsOneWidget);

      appRouter.push(
        '/search?locked=true&from=2026-09-01&to=2026-09-05&uncategorized=true',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('locked-search-criteria')),
        findsOneWidget,
      );
      expect(find.textContaining('2026-09-01'), findsOneWidget);
      expect(find.textContaining('2026-09-05'), findsOneWidget);
      expect(find.textContaining('Uncategorized'), findsOneWidget);
      expect(find.byType(SearchBar), findsNothing);
      expect(find.byKey(const ValueKey('search-submit')), findsNothing);
      expect(find.byIcon(Icons.tune_rounded), findsNothing);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Insights'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('locked-search-criteria')),
        findsNothing,
      );
    },
  );
}
