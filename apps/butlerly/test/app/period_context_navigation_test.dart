import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/features/analysis/presentation/analysis_page.dart';
import 'package:butlerly/features/insights/presentation/insights_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const failure = ApplicationFailureDetail(
    operation: 'test load',
    code: ApplicationFailureCode.unavailable,
  );
  final july = DateTimeRange(
    start: DateTime(2026, 7, 1),
    end: DateTime(2026, 7, 31),
  );
  final julyMonth = DateTime(2026, 7, 1);

  testWidgets('Analysis starts a custom range as selected_period', (
    tester,
  ) async {
    String? requestedPeriod;

    await tester.pumpWidget(
      _host(
        AnalysisPage(
          initialRange: july,
          loadForPeriod: (period) async {
            requestedPeriod = period;
            return const ApplicationFailure<List<RuleExecutionResult>>(failure);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedPeriod, 'selected_period');
  });

  testWidgets('Analysis keeps a Home month as selected_month', (tester) async {
    String? requestedPeriod;

    await tester.pumpWidget(
      _host(
        AnalysisPage(
          initialMonth: julyMonth,
          loadForPeriod: (period) async {
            requestedPeriod = period;
            return const ApplicationFailure<List<RuleExecutionResult>>(failure);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedPeriod, 'selected_month');
  });

  testWidgets('Insights starts a custom range as selected_period', (
    tester,
  ) async {
    String? requestedPeriod;

    await tester.pumpWidget(
      _host(
        InsightsPage(
          initialRange: july,
          loadEvaluation: (period) async {
            requestedPeriod = period;
            return const ApplicationFailure<InsightsEvaluation>(failure);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedPeriod, 'selected_period');
  });

  testWidgets('Insights keeps a Home month as selected_month', (tester) async {
    String? requestedPeriod;

    await tester.pumpWidget(
      _host(
        InsightsPage(
          initialMonth: julyMonth,
          loadEvaluation: (period) async {
            requestedPeriod = period;
            return const ApplicationFailure<InsightsEvaluation>(failure);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedPeriod, 'selected_month');
  });
}

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: child,
);
