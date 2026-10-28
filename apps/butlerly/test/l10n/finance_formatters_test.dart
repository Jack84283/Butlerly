import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
  });
}
