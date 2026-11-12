import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Home previous-period values show missing data and whole counts',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en', 'US'),
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(localizedHomeBaseline(context, null, isCount: false), '-');
      expect(localizedHomeBaseline(context, null, isCount: true), '-');
      expect(localizedHomeBaseline(context, '9.00', isCount: true), '9');
      expect(localizedHomeBaseline(context, '1234.00', isCount: true), '1,234');
      expect(
        localizedHomeBaseline(context, '9', isCount: false, currency: 'USD'),
        '9.00 USD',
      );
      expect(localizedHomeBaseline(context, '0', isCount: false), '0.00');
    },
  );

  testWidgets('Home combines comparison and baseline into one line', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final higher = AnalysisComparison(
      currentValue: DecimalValue.parse('1200'),
      baselineValue: DecimalValue.parse('1000'),
      absoluteChange: DecimalValue.parse('200'),
      percentageChange: DecimalValue.parse('20'),
      availability: AnalysisDataAvailability.sufficient,
    );
    final lower = AnalysisComparison(
      currentValue: DecimalValue.parse('80'),
      baselineValue: DecimalValue.parse('100'),
      absoluteChange: DecimalValue.parse('-20'),
      percentageChange: DecimalValue.parse('-20'),
      availability: AnalysisDataAvailability.sufficient,
    );
    final zero = AnalysisComparison(
      currentValue: DecimalValue.parse('1'),
      baselineValue: DecimalValue.parse('0'),
      absoluteChange: DecimalValue.parse('1'),
      percentageChange: DecimalValue.parse('0'),
      availability: AnalysisDataAvailability.sufficient,
    );

    expect(
      localizedHomeComparisonLine(
        context,
        higher,
        isCount: false,
        currency: 'USD',
      ),
      '↑ 20.0% (vs 1,000.00 USD)',
    );
    expect(
      localizedHomeComparisonLine(context, lower, isCount: true),
      '↓ 20.0% (vs 100)',
    );
    expect(
      localizedHomeComparisonLine(
        context,
        zero,
        isCount: false,
        currency: 'USD',
      ),
      'Comparison unavailable (vs 0.00 USD)',
    );
    expect(
      localizedHomeComparisonLine(context, null, isCount: true),
      'Comparison unavailable',
    );
  });

  testWidgets('Home comparison line respects Chinese and Spanish locale', (
    tester,
  ) async {
    final comparison = AnalysisComparison(
      currentValue: DecimalValue.parse('1388.5'),
      baselineValue: DecimalValue.parse('1234.5'),
      absoluteChange: DecimalValue.parse('154'),
      percentageChange: DecimalValue.parse('12.5'),
      availability: AnalysisDataAvailability.sufficient,
    );
    for (final locale in [const Locale('zh', 'CN'), const Locale('es', 'ES')]) {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final actual = localizedHomeComparisonLine(
        context,
        comparison,
        isCount: false,
        currency: 'USD',
      );
      if (locale.languageCode == 'zh') {
        expect(actual, '↑ 12.5%（较 1,234.50 USD）');
      } else {
        expect(actual, '↑ 12,5% (vs. 1.234,50 USD)');
      }
    }
  });

  testWidgets('transaction amounts always render two decimal places', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(localizedTransactionAmount(context, '10'), '10.00');
    expect(localizedTransactionAmount(context, '10.5'), '10.50');
    expect(localizedTransactionAmount(context, '10.00'), '10.00');
    expect(localizedTransactionAmount(context, '-25'), '-25.00');
  });

  testWidgets('compact Home money and percentages use localized precision', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        supportedLocales: const [Locale('en', 'US'), Locale('es', 'ES')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(localizedCompactMoney(context, '2340.18', 'USD'), r'$2,340.18');
    expect(localizedCompactMoney(context, '-50', 'USD'), r'-$50.00');
    expect(localizedCompactSignedMoney(context, '4150', 'USD'), r'+$4,150.00');
    expect(localizedCompactSignedMoney(context, '-48.32', 'USD'), r'-$48.32');
    expect(localizedCompactPercentage(context, '28'), '28%');
    expect(localizedCompactPercentage(context, '28.5'), '28.5%');
    expect(localizedCompactPercentage(context, '0.43', ratio: true), '43%');
  });

  testWidgets('profile money preserves exact digits and locale separators', (
    tester,
  ) async {
    late BuildContext english;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        supportedLocales: const [
          Locale('en', 'US'),
          Locale('es', 'ES'),
          Locale('zh', 'CN'),
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (value) {
            english = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(
      localizedExactMoney(english, '12345678901234567890.12', 'USD'),
      r'$12,345,678,901,234,567,890.12',
    );
    expect(localizedExactDecimal(english, '750.25'), '750.25');

    late BuildContext spanish;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'ES'),
        supportedLocales: const [
          Locale('en', 'US'),
          Locale('es', 'ES'),
          Locale('zh', 'CN'),
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (value) {
            spanish = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(localizedExactMoney(spanish, '1234.50', 'EUR'), contains('1.234,5'));
    expect(localizedExactDecimal(spanish, '750.25'), '750,25');

    late BuildContext chinese;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [
          Locale('en', 'US'),
          Locale('es', 'ES'),
          Locale('zh', 'CN'),
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (value) {
            chinese = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(
      localizedExactMoney(chinese, '1234.50', 'USD'),
      contains(r'$1,234.5'),
    );
    expect(localizedExactDecimal(chinese, '750.25'), '750.25');
  });

  test('localized decimal parsing rejects cross-locale ambiguity', () {
    expect(parseLocalizedDecimal('750,25', locale: 'es'), '750.25');
    expect(parseLocalizedDecimal('1.234,5', locale: 'es'), '1234.5');
    expect(parseLocalizedDecimal('750.25', locale: 'es'), isNull);
    expect(parseLocalizedDecimal('750,25', locale: 'en'), isNull);
    expect(parseLocalizedDecimal('750.25', locale: 'en'), '750.25');
    expect(parseLocalizedDecimal('750.25', locale: 'zh'), '750.25');
    expect(parseLocalizedDecimal('1.23.4', locale: 'en'), isNull);
  });
}
