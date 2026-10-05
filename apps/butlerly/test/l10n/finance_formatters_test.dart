import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:flutter/material.dart';
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
}
