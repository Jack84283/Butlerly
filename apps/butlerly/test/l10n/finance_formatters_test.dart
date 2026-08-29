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
}
