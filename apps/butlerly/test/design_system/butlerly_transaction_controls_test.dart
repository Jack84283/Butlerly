import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_controls.dart';
import 'package:butlerly/design_system/theme/butlerly_button_palette.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
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

  Future<void> pumpAtWidth(
    WidgetTester tester,
    double width,
    Widget childWidget,
  ) async {
    tester.view.physicalSize = Size(width, 220);
    tester.view.devicePixelRatio = 1;
    await pump(tester, childWidget);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'compact search controls stay accessible without overflow at narrow widths',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController();

      for (final width in [80.0, 88.0, 100.0, 140.0]) {
        controller.clear();
        await pumpAtWidth(
          tester,
          width,
          ButlerlyTransactionSearchControls(
            controller: controller,
            activeFilterCount: 0,
            onSearch: () {},
            onChanged: (_) {},
            onClear: controller.clear,
            onFilter: () {},
          ),
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'narrow search controls overflow at $width px',
        );
        expect(find.byType(SearchBar), findsNothing);
        expect(
          find.byKey(const ValueKey('compact-search-button')),
          findsOneWidget,
        );
        final searchRect = tester.getRect(
          find.byKey(const ValueKey('compact-search-button')),
        );
        expect(searchRect.width, ButlerlySize.minimumTarget);
        expect(searchRect.height, ButlerlySize.minimumTarget);
        if (width < 96) {
          expect(
            find.byKey(const ValueKey('transaction-search-filter')),
            findsNothing,
          );
        } else {
          expect(
            find.byKey(const ValueKey('transaction-search-filter')),
            findsOneWidget,
          );
          final filterRect = tester.getRect(
            find.byKey(const ValueKey('transaction-search-filter')),
          );
          expect(filterRect.width, ButlerlySize.minimumTarget);
          expect(filterRect.top, closeTo(searchRect.top, 0.1));
        }
      }
    },
  );

  testWidgets(
    'ultra-compact search keeps search and filter actions in one target',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      var filterRequests = 0;

      await pumpAtWidth(
        tester,
        88,
        ButlerlyTransactionSearchControls(
          controller: controller,
          activeFilterCount: 2,
          onSearch: () {},
          onChanged: (_) {},
          onClear: controller.clear,
          onFilter: () => filterRequests++,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('compact-search-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('compact-search-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('compact-filter-action')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      final compactFilterAction = find.byKey(
        const ValueKey('compact-filter-action'),
      );
      await tester.ensureVisible(compactFilterAction);
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -40),
      );
      await tester.pumpAndSettle();
      await tester.tap(compactFilterAction);
      await tester.pumpAndSettle();
      expect(filterRequests, 1);
      expect(find.byKey(const ValueKey('compact-search-field')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pinned search header keeps ultra-narrow controls inside its fixed extent',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController();

      for (final width in [80.0, 88.0]) {
        controller.clear();
        await pumpAtWidth(
          tester,
          width,
          ButlerlyPage(
            title: 'Transactions',
            pinnedSpacing: ButlerlyPinnedPageSpacing.tightHeader,
            pinnedHeaderExtent: ButlerlySize.searchPinnedHeaderHeight,
            pinnedHeader: ButlerlyTransactionSearchControls(
              controller: controller,
              activeFilterCount: 0,
              onSearch: () {},
              onChanged: (_) {},
              onClear: controller.clear,
              onFilter: () {},
            ),
            children: const [SizedBox(height: ButlerlySize.minimumTarget)],
          ),
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'pinned search header overflowed at $width px',
        );
        final controlsRect = tester.getRect(
          find.byKey(const ValueKey('search-pinned-controls')),
        );
        expect(
          controlsRect.height,
          closeTo(ButlerlySize.searchPinnedHeaderHeight, 0.1),
        );
        expect(
          find.byKey(const ValueKey('compact-search-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('transaction-search-filter')),
          findsNothing,
        );
      }
    },
  );

  testWidgets('compact search opens an accessible text-entry surface', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    var changed = '';
    var searches = 0;

    await pumpAtWidth(
      tester,
      140,
      ButlerlyTransactionSearchControls(
        controller: controller,
        activeFilterCount: 0,
        onSearch: () => searches++,
        onChanged: (value) => changed = value,
        onClear: controller.clear,
        onFilter: () {},
      ),
    );
    await tester.tap(find.byKey(const ValueKey('compact-search-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('compact-search-field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('compact-search-field')),
      'coffee',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(changed, 'coffee');
    expect(searches, 1);
    expect(find.byKey(const ValueKey('compact-search-field')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full SearchBar remains usable at mobile and desktop widths', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();

    for (final width in [390.0, 1200.0]) {
      controller.clear();
      var changed = '';
      var searches = 0;
      await pumpAtWidth(
        tester,
        width,
        ButlerlyTransactionSearchControls(
          controller: controller,
          activeFilterCount: 1,
          searchFieldKey: const ValueKey('normal-search-field'),
          onSearch: () => searches++,
          onChanged: (value) => changed = value,
          onClear: controller.clear,
          onFilter: () {},
        ),
      );

      expect(find.byType(SearchBar), findsOneWidget);
      expect(find.byKey(const ValueKey('compact-search-button')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('normal-search-field')),
        'coffee',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(changed, 'coffee');
      expect(searches, 1);
      expect(
        find.byKey(const ValueKey('transaction-search-filter')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

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

  testWidgets('subcategory clear emits null instead of its parent category', (
    tester,
  ) async {
    String? clearedValue = 'groceries';
    await pump(
      tester,
      ButlerlySubcategorySelector(
        categories: [parent, child],
        masterData: labels,
        parentId: parent.id.value,
        value: clearedValue,
        label: 'Subcategory',
        clearLabel: 'Clear subcategory',
        onChanged: (value) => clearedValue = value,
      ),
    );

    await tester.tap(find.byTooltip('Clear subcategory').first);
    expect(clearedValue, isNull);
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

  testWidgets('merchant selector exposes create and clear actions', (
    tester,
  ) async {
    String? value = 'merchant';
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => ButlerlyMerchantSelector(
          merchants: [Merchant(id: MerchantId('merchant'), name: 'Shop')],
          value: value,
          label: 'Merchant',
          clearLabel: '清除商户',
          createTooltip: '添加商户',
          onChanged: (next) => setState(() => value = next),
          onCreate: () {},
        ),
      ),
    );
    expect(find.byTooltip('添加商户'), findsWidgets);
    expect(find.byTooltip('清除商户'), findsWidgets);
    await tester.tap(find.byTooltip('清除商户').first);
    expect(value, isNull);
  });

  testWidgets('tag search follows available chips with consistent spacing', (
    tester,
  ) async {
    final tags = List.generate(
      9,
      (index) => Tag(id: TagId('tag-$index'), name: 'Tag $index'),
    );
    await pump(
      tester,
      ButlerlyTagPicker(
        tags: tags,
        masterData: labels,
        selected: const {'tag-0'},
        searchLabel: 'Search tags',
        createLabel: 'Add tag',
        onChanged: (_) {},
      ),
    );

    final selected = tester.getRect(find.byType(InputChip).first);
    final search = tester.getRect(find.byType(TextField));
    final available = tester.getRect(find.byType(FilterChip).first);

    expect(
      available.top - selected.bottom,
      greaterThanOrEqualTo(ButlerlySpacing.small),
    );
    expect(
      search.top - tester.getRect(find.byType(FilterChip).last).bottom,
      greaterThanOrEqualTo(ButlerlySpacing.small),
    );
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
    expect(find.text('工作'), findsWidgets);
    await tester.enterText(find.byType(TextField), '工作');
    await tester.pump();
    expect(find.text('家庭'), findsNothing);
    expect(find.text('工作'), findsWidgets);
    await tester.tap(find.widgetWithText(FilterChip, '工作'));
    await tester.pump();
    expect(selected, contains('work'));
  });

  testWidgets(
    'shared filters support nullable values and localized direction',
    (tester) async {
      String? currency = 'USD';
      TransactionDirection? direction = TransactionDirection.expense;
      await pump(
        tester,
        Column(
          children: [
            ButlerlyCurrencyFilter(
              currencies: const ['USD', 'INR'],
              value: currency,
              label: 'Currency',
              anyLabel: 'Any currency',
              onChanged: (value) => currency = value,
            ),
            ButlerlyDirectionFilter(
              value: direction,
              label: 'Direction',
              anyLabel: 'Any direction',
              onChanged: (value) => direction = value,
            ),
          ],
        ),
      );
      expect(find.byTooltip('Any currency'), findsWidgets);
      expect(find.byTooltip('Any direction'), findsWidgets);
      await tester.tap(find.byTooltip('Any currency').first);
      expect(currency, isNull);
    },
  );

  testWidgets('filter sheet shows Apply and secondary Clear side by side', (
    tester,
  ) async {
    await pump(
      tester,
      ButlerlyTransactionFilterSheet(
        value: const ButlerlyTransactionFilterValue(),
        currencies: Future.value(const <String>[]),
        masterData: Future.value(
          const TransactionMasterDataSnapshot(
            presentation: TransactionMasterData(),
            merchants: [],
            categories: [],
            tags: [],
            paymentSources: [],
          ),
        ),
        formatDate: (value) => value.toIso8601String(),
        onApply: (_) {},
        onClear: () {},
      ),
    );
    await tester.pumpAndSettle();

    final apply = find.byKey(const ValueKey('apply-search-filters'));
    final clear = find.byKey(const ValueKey('clear-search-filters'));
    expect(clear, findsOneWidget);
    expect(tester.widget(clear), isA<OutlinedButton>());
    expect(find.byType(ButlerlyCard), findsOneWidget);

    final applyRect = tester.getRect(apply);
    final clearRect = tester.getRect(clear);
    expect(applyRect.center.dy, closeTo(clearRect.center.dy, 1));
    expect(applyRect.right, lessThan(clearRect.left));
    final theme = Theme.of(tester.element(clear));
    final buttons = ButlerlyButtonPalette.resolve(
      colors: theme.extension<ButlerlySemanticColors>()!,
      brightness: theme.brightness,
    );
    expect(
      theme.outlinedButtonTheme.style?.backgroundColor?.resolve({}),
      buttons.secondaryFill,
    );
    expect(
      theme.outlinedButtonTheme.style?.side?.resolve({}),
      BorderSide(color: buttons.secondaryBorder),
    );
  });

  testWidgets('read-only tags localize, wrap, and expose overflow accessibly', (
    tester,
  ) async {
    await pump(
      tester,
      ButlerlyReadOnlyTagList(
        tagIds: const ['work', 'home', 'missing'],
        masterData: labels,
        label: 'Tags',
        unavailableLabel: 'Unavailable',
        maxVisible: 2,
      ),
    );
    expect(find.text('工作'), findsOneWidget);
    expect(find.text('家庭'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(find.bySemanticsLabel('Tags'), findsOneWidget);
  });

  testWidgets(
    'duplicate confirmation preselects one candidate and returns it',
    (tester) async {
      ButlerlyDuplicateConfirmationResult? result;
      await pump(
        tester,
        ButlerlyDuplicateTransactionConfirmation(
          proposed: _duplicateDto('proposed', paymentSourceId: 'source-id'),
          candidates: [
            DuplicateTransactionCandidate(
              transaction: _duplicateDto(
                'candidate',
                paymentSourceId: 'source-id',
              ),
              confidence: 0.75,
              matchingReasons: const [],
            ),
          ],
          paymentSourceLabels: const {'source-id': 'Visa ••••1234'},
          onDecision: (value) => result = value,
        ),
      );
      expect(find.text('Possible duplicate'), findsOneWidget);
      expect(find.textContaining('Visa'), findsWidgets);
      expect(find.text('source-id'), findsNothing);
      expect(find.bySemanticsLabel('Possible duplicate'), findsOneWidget);
      await tester.tap(find.text('Use existing'));
      expect(result?.decision, ButlerlyDuplicateDecision.useExisting);
      expect(result?.selectedTransactionId, 'candidate');
    },
  );

  testWidgets('multiple candidates require and preserve explicit selection', (
    tester,
  ) async {
    ButlerlyDuplicateConfirmationResult? result;
    final candidates = [
      DuplicateTransactionCandidate(
        transaction: _duplicateDto('first'),
        confidence: 0.75,
        matchingReasons: const [],
      ),
      DuplicateTransactionCandidate(
        transaction: _duplicateDto('second'),
        confidence: 0.75,
        matchingReasons: const [],
      ),
    ];
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) =>
            ButlerlyDuplicateTransactionConfirmation(
              proposed: _duplicateDto('proposed'),
              candidates: candidates,
              onDecision: (value) => setState(() => result = value),
            ),
      ),
    );
    final useExisting = find.text('Use existing');
    final button = tester.widget<FilledButton>(
      find.ancestor(of: useExisting, matching: find.byType(FilledButton)),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.byType(RadioListTile<String>).at(1));
    await tester.pump();
    await tester.tap(useExisting);
    await tester.pump();
    expect(result?.selectedTransactionId, 'second');
  });

  testWidgets('continue and cancel carry no selected transaction', (
    tester,
  ) async {
    final results = <ButlerlyDuplicateConfirmationResult>[];
    await pump(
      tester,
      ButlerlyDuplicateTransactionConfirmation(
        proposed: _duplicateDto('proposed'),
        candidates: [
          DuplicateTransactionCandidate(
            transaction: _duplicateDto('candidate'),
            confidence: 0.75,
            matchingReasons: const [],
          ),
        ],
        onDecision: results.add,
      ),
    );
    await tester.tap(find.text('Continue anyway'));
    expect(results.single.selectedTransactionId, isNull);
    results.clear();
    await tester.tap(find.text('Use existing'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    expect(results.last.decision, ButlerlyDuplicateDecision.cancel);
    expect(results.last.selectedTransactionId, isNull);
  });
}

TransactionDto _duplicateDto(String id, {String? paymentSourceId}) =>
    TransactionDto(
      id: id,
      amount: '25.00',
      currency: 'USD',
      direction: 'expense',
      status: 'active',
      reviewState: 'clear',
      transactionDate: '2026-08-20',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      paymentSourceId: paymentSourceId,
      description: id,
    );
