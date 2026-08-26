import 'package:butlerly/features/analysis/presentation/analysis_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(
    Future<ApplicationResult<List<RuleExecutionResult>>> Function() load,
  ) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: AnalysisPage(load: load),
  );

  testWidgets('renders an offline all-clear state from application results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(() async => const ApplicationSuccess(<RuleExecutionResult>[])),
    );
    await tester.pumpAndSettle();
    expect(find.text('Analysis'), findsOneWidget);
    expect(find.text('No findings'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Calculated privately on this device and available offline.',
      ),
      findsAtLeastNWidgets(1),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/analysis_empty_390x844.png'),
    );
  });

  testWidgets('distinguishes unavailable calculation from a zero result', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        () async => const ApplicationFailure(
          ApplicationFailureDetail(
            code: ApplicationFailureCode.unavailable,
            operation: 'analysis',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Analysis is unavailable'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });
}
