import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_inner_card.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('nested transaction cards share canonical geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: ButlerlyInsetTransactionCard(
            bottomInset: ButlerlySpacing.compact,
            child: SizedBox.square(dimension: 24),
          ),
        ),
      ),
    );

    final inset = tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(ButlerlyInsetTransactionCard),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect(
      inset.padding,
      const EdgeInsets.fromLTRB(
        ButlerlySpacing.compact,
        0,
        ButlerlySpacing.compact,
        ButlerlySpacing.compact,
      ),
    );

    final inner = tester.widget<ButlerlyCard>(
      find.descendant(
        of: find.byType(ButlerlyTransactionInnerCard),
        matching: find.byType(ButlerlyCard),
      ),
    );
    expect(
      inner.padding,
      const EdgeInsets.all(ButlerlySpacing.micro),
    );
    expect(tester.takeException(), isNull);
  });
}
