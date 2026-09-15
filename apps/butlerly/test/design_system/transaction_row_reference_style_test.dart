import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_transaction_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('canonical transaction row follows reference hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SizedBox(
            width: 390,
            child: ButlerlyRecordRow(
              title: 'Whole Foods Market',
              amount: '82.47',
              currency: 'USD',
              categoryLabel: 'Groceries',
              subcategoryLabel: 'Supermarket',
              paymentSource: 'Visa ••••8421',
              meta: 'Sep 2, 2026',
              showDate: true,
            ),
          ),
        ),
      ),
    );

    final title = find.text('Whole Foods Market');
    final amount = find.text('−82.47 USD');
    final metadata = find.text('Groceries · Supermarket · Visa ••••8421');
    final date = find.text('Sep 2, 2026');
    final leadingIcon = find.byIcon(Icons.receipt_long_outlined);

    expect(title, findsOneWidget);
    expect(amount, findsOneWidget);
    expect(metadata, findsOneWidget);
    expect(date, findsOneWidget);
    expect(leadingIcon, findsOneWidget);

    expect(
      tester.getSize(leadingIcon).width,
      ButlerlyTransactionItemTokens.leadingIconGlyphSize,
    );
    final iconParent = tester.getSize(
      find.ancestor(
        of: leadingIcon,
        matching: find.byType(SizedBox),
      ).first,
    );
    expect(iconParent.width, ButlerlyTransactionItemTokens.leadingIconSize);
    expect(iconParent.height, ButlerlyTransactionItemTokens.leadingIconSize);

    final titleText = tester.widget<Text>(title);
    final amountText = tester.widget<Text>(amount);
    final metadataText = tester.widget<Text>(metadata);
    final dateText = tester.widget<Text>(date);

    expect(
      titleText.style?.fontSize,
      ButlerlyTransactionItemTokens.titleFontSize,
    );
    expect(titleText.style?.fontWeight, FontWeight.w600);
    expect(
      amountText.style?.fontSize,
      ButlerlyTransactionItemTokens.amountFontSize,
    );
    expect(amountText.style?.fontWeight, FontWeight.w600);
    expect(
      metadataText.style?.fontSize,
      ButlerlyTransactionItemTokens.metadataFontSize,
    );
    expect(
      dateText.style?.fontSize,
      ButlerlyTransactionItemTokens.metadataFontSize,
    );

    expect(
      tester.getTopLeft(title).dy,
      closeTo(tester.getTopLeft(amount).dy, 1.0),
    );
    expect(
      tester.getTopLeft(metadata).dy,
      greaterThan(tester.getBottomLeft(title).dy),
    );
    expect(
      tester.getTopLeft(date).dy,
      greaterThan(tester.getBottomLeft(metadata).dy),
    );
  });
}
