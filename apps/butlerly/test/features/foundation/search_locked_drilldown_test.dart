import 'package:butlerly/features/foundation/presentation/search_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('locked Search shows criteria, hides controls, and navigates back', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => SearchPage(
                      readOnly: true,
                      initialQuery: ListTransactionsQuery(
                        transactionIds: const ['support-1', 'support-2'],
                        from: DateTime(2026, 9, 1),
                        to: DateTime(2026, 9, 5),
                        categoryId: 'category.food',
                      ),
                    ),
                  ),
                ),
                child: const Text('Open locked search'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open locked search'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('locked-search-criteria')), findsOneWidget);
    expect(find.textContaining('2026-09-01'), findsOneWidget);
    expect(find.textContaining('2026-09-05'), findsOneWidget);
    expect(find.textContaining('category.food'), findsOneWidget);
    expect(find.byType(SearchBar), findsNothing);
    expect(find.byKey(const ValueKey('search-submit')), findsNothing);
    expect(find.byIcon(Icons.tune_rounded), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Open locked search'), findsOneWidget);
    expect(find.byKey(const ValueKey('locked-search-criteria')), findsNothing);
  });
}
