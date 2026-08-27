import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_controls.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parent = Category(
    id: CategoryId('food'),
    name: 'Food',
    origin: CategoryOrigin.system,
  );
  final child = Category(
    id: CategoryId('groceries'),
    name: 'Groceries',
    origin: CategoryOrigin.system,
    parentId: parent.id,
  );
  final otherChild = Category(
    id: CategoryId('travel'),
    name: 'Travel',
    origin: CategoryOrigin.system,
    parentId: CategoryId('other'),
  );
  final labels = TransactionMasterData(
    categoryNames: {'food': '餐饮', 'groceries': '杂货', 'travel': '旅行'},
    tagNames: {'work': '工作', 'home': '家庭'},
  );

  Future<void> pump(WidgetTester tester, Widget childWidget) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: childWidget),
      ),
    );
  }

  testWidgets('category and subcategory share localized hierarchy filtering', (
    tester,
  ) async {
    String? selected = 'groceries';
    await pump(
      tester,
      Column(
        children: [
          ButlerlyCategorySelector(
            categories: [parent, child, otherChild],
            masterData: labels,
            value: parent.id.value,
            label: 'Category',
            clearLabel: 'Clear category',
            onChanged: (_) {},
          ),
          ButlerlySubcategorySelector(
            categories: [parent, child, otherChild],
            masterData: labels,
            parentId: parent.id.value,
            value: selected,
            label: 'Subcategory',
            clearLabel: 'Clear subcategory',
            onChanged: (value) => selected = value,
          ),
        ],
      ),
    );
    await tester.tap(find.byType(DropdownMenu<String>).last);
    await tester.pumpAndSettle();
    expect(find.text('杂货'), findsWidgets);
    expect(find.text('旅行'), findsNothing);
  });

  testWidgets('shared selectors expose localized clear labels', (tester) async {
    await pump(
      tester,
      ButlerlyPaymentSourceSelector(
        sources: [
          PaymentSource(
            id: PaymentSourceId('cash'),
            name: 'Cash',
            type: PaymentSourceType.cash,
          ),
        ],
        value: 'cash',
        label: 'Payment source',
        clearLabel: '清除支付来源',
        onChanged: (_) {},
      ),
    );
    expect(find.byTooltip('清除支付来源'), findsWidgets);
  });

  testWidgets('tag picker supports localized search and multi-selection', (
    tester,
  ) async {
    final selected = <String>{};
    await pump(
      tester,
      ButlerlyTagPicker(
        tags: [
          Tag(id: TagId('work'), name: 'Work'),
          Tag(id: TagId('home'), name: 'Home'),
          ...List.generate(
            7,
            (index) => Tag(id: TagId('extra-$index'), name: 'Extra $index'),
          ),
        ],
        masterData: labels,
        selected: selected,
        searchLabel: '搜索标签',
        createLabel: '添加标签',
        onChanged: (value) => selected
          ..clear()
          ..addAll(value),
      ),
    );
    expect(find.text('工作'), findsOneWidget);
    await tester.tap(find.text('工作'));
    await tester.pump();
    expect(selected, contains('work'));
  });
}
