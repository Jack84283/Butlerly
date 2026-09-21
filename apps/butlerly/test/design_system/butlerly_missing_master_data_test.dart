import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_controls.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'select field shows canonical value when its label is unavailable',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ButlerlySelectField<String>(
              label: 'Merchant',
              value: 'merchant-missing',
              entries: const [],
              onChanged: (_) {},
              onClear: () {},
              clearTooltip: 'Clear',
            ),
          ),
        ),
      );

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.text, 'merchant-missing');
    },
  );

  testWidgets('subcategory keeps a missing stored reference visible', (
    tester,
  ) async {
    String? changedTo = 'unchanged';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ButlerlySubcategorySelector(
            categories: const [],
            masterData: const TransactionMasterData(),
            parentId: 'category-food',
            value: 'subcategory-missing',
            label: 'Subcategory',
            onChanged: (value) => changedTo = value,
            clearLabel: 'Clear',
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is EditableText &&
            widget.controller.text == 'subcategory-missing',
      ),
      findsWidgets,
    );
    final select = tester.widget<ButlerlySelectField<String>>(
      find.byType(ButlerlySelectField<String>),
    );
    expect(select.onClear, isNotNull);
    select.onClear!();
    expect(changedTo, isNull);
  });
}
