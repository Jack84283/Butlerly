import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_inner_card.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/master_data_page.dart';
import 'package:butlerly/features/tools/presentation/rules_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 1, 12);
  late _RulesRepository rules;
  late _Transactions transactions;

  setUp(() async {
    await services.reset();
    rules = _RulesRepository([
      TransactionRule(
        id: TransactionRuleId('rule.fuel'),
        name: 'Classify fuel',
        priority: 1,
        descriptionContains: 'fuel',
        assignCategoryId: CategoryId('category.transport'),
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    transactions = _Transactions();
    services.registerSingleton<FinanceServices>(
      FinanceServices(
        transactions,
        _PaymentSources(),
        _Merchants(),
        _Categories(),
        _Tags(),
        _Evidence(),
        _Preferences(),
        transactionRules: rules,
      ),
    );
  });

  tearDown(() => services.reset());

  testWidgets('lists rule details and persists enable/disable changes', (
    tester,
  ) async {
    await tester.pumpWidget(const _TestApp(child: RulesPage()));
    await tester.pumpAndSettle();

    expect(find.text('Rules'), findsOneWidget);
    expect(
      find.textContaining('Rules help you automatically organize'),
      findsOneWidget,
    );
    expect(
      find.textContaining('You can test a rule against existing transactions'),
      findsOneWidget,
    );
    expect(find.text('Classify fuel'), findsOneWidget);
    expect(find.text('fuel\nCategory: Transport'), findsOneWidget);

    await tester.tap(find.text('Classify fuel').first);
    await tester.pumpAndSettle();
    expect(find.text('Matching conditions'), findsOneWidget);
    expect(find.text('Resulting actions'), findsOneWidget);
    expect(find.text('Category: Transport'), findsOneWidget);
    expect(find.byType(ButlerlySheet), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktop-rule-details-panel')),
      findsNothing,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect((await rules.listAll()).single.enabled, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect((await rules.listAll()).single.enabled, isTrue);
  });

  testWidgets('desktop Rules uses full width and an actionable table', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _TestApp(child: RulesPage()));
    await tester.pumpAndSettle();

    final page = tester.widget<ButlerlyPage>(find.byType(ButlerlyPage));
    expect(page.fullWidth, isTrue);
    expect(find.byKey(const ValueKey('desktop-rules-table')), findsOneWidget);
    expect(find.text('Matching conditions'), findsOneWidget);
    expect(find.text('Resulting actions'), findsOneWidget);
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Classify fuel'), findsOneWidget);
    expect(find.text('Category: Transport'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktop-rules-table-horizontal-scroll')),
      findsNothing,
    );

    // The Home/Transactions desktop table uses compact, single-line rows.
    // Default 48px actions must not dictate the Rules row height.
    final ruleRow = find.byKey(const ValueKey('desktop-rule-row-rule.fuel'));
    final editAction = find.byKey(
      const ValueKey('desktop-rule-edit-rule.fuel'),
    );
    final deleteAction = find.byKey(
      const ValueKey('desktop-rule-delete-rule.fuel'),
    );
    final statusSwitch = find.byKey(
      const ValueKey('desktop-rule-switch-rule.fuel'),
    );
    expect(tester.getSize(ruleRow).height, lessThanOrEqualTo(42));
    expect(tester.widget<IconButton>(editAction).constraints?.maxWidth, 24);
    expect(tester.widget<IconButton>(editAction).constraints?.maxHeight, 24);
    expect(tester.widget<IconButton>(editAction).iconSize, 16);
    expect(tester.widget<IconButton>(deleteAction).constraints?.maxWidth, 24);
    expect(tester.widget<IconButton>(deleteAction).constraints?.maxHeight, 24);
    expect(tester.widget<IconButton>(deleteAction).iconSize, 16);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('desktop-rule-switch-box-rule.fuel')),
          )
          .height,
      20,
    );
    expect(
      tester.widget<Switch>(statusSwitch).materialTapTargetSize,
      MaterialTapTargetSize.shrinkWrap,
    );

    await tester.tap(find.byKey(const ValueKey('desktop-rule-row-rule.fuel')));
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('desktop-rule-details-panel'));
    expect(panel, findsOneWidget);
    expect(find.byType(ButlerlySheet), findsNothing);
    expect(
      find.descendant(of: panel, matching: find.text('Classify fuel')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('Matching conditions')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(panel).dx,
      greaterThan(tester.getTopRight(find.byType(ButlerlyDesktopInnerCard)).dx),
    );
    await tester.tap(find.byKey(const ValueKey('desktop-rule-details-close')));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(find.byKey(const ValueKey('desktop-rules-table')), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('desktop-rule-switch-rule.fuel')),
    );
    await tester.pumpAndSettle();
    expect((await rules.listAll()).single.enabled, isFalse);
    await tester.tap(find.byKey(const ValueKey('desktop-rule-edit-rule.fuel')));
    await tester.pumpAndSettle();
    expect(find.text('Edit rule'), findsOneWidget);
    // The editor's footer actions scroll with its content; use the fixed
    // back button to cancel without tapping an off-screen control.
    await tester.tap(find.byKey(const ValueKey('desktop-rule-editor-back')));
    await tester.pumpAndSettle();
    expect(find.text('Edit rule'), findsNothing);
    // Cancel returns to the selected rule's details panel. Close it before
    // interacting with the table action beneath the split-view panel.
    await tester.tap(find.byKey(const ValueKey('desktop-rule-details-close')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('desktop-rule-delete-rule.fuel')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete rule?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((await rules.listAll()), hasLength(1));
    _expectNoFlutterError(tester);
  });

  testWidgets('desktop rule selection replaces details without modal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await rules.save(
      TransactionRule(
        id: TransactionRuleId('rule.coffee'),
        name: 'Classify coffee',
        description: 'Coffee and cafes',
        priority: 2,
        descriptionContains: 'coffee',
        assignCategoryId: CategoryId('category.transport'),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await tester.pumpWidget(const _TestApp(child: RulesPage()));
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('desktop-rule-details-panel'));
    final table = find.byKey(const ValueKey('desktop-rules-table'));
    final fullTableWidth = tester.getSize(table).width;
    expect(panel, findsNothing);
    await tester.tap(find.byKey(const ValueKey('desktop-rule-row-rule.fuel')));
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(find.byType(ButlerlySheet), findsNothing);
    expect(tester.getSize(table).width, lessThan(fullTableWidth));
    expect(
      find.descendant(of: panel, matching: find.text('Classify fuel')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('desktop-rule-row-rule.coffee')),
    );
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.text('Classify coffee')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('Coffee and cafes')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('Classify fuel')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('desktop-rule-details-close')));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(tester.getSize(table).width, closeTo(fullTableWidth, 0.1));
    _expectNoFlutterError(tester);
  });

  testWidgets('desktop Rules rows match Master Data icon and row geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _TestApp(child: RulesPage()));
    await tester.pumpAndSettle();

    final rulesRow = find.byKey(const ValueKey('desktop-rule-row-rule.fuel'));
    final rulesHeight = tester.getSize(rulesRow).height;
    expect(
      rulesHeight,
      closeTo(20 + 2 * ButlerlyTableTokens.rowVerticalPadding, 0.1),
    );
    expect(find.byType(ButlerlyDesktopTableIconAction), findsNWidgets(2));

    await tester.pumpWidget(const _TestApp(child: MasterDataPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('compact-section-3')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-master-data-table')),
      findsOneWidget,
    );
    final masterRow = find
        .ancestor(of: find.text('Costco'), matching: find.byType(Padding))
        .first;
    expect(tester.getSize(masterRow).height, closeTo(rulesHeight, 0.1));
    expect(find.byType(ButlerlyDesktopTableIconAction), findsNWidgets(2));
    _expectNoFlutterError(tester);
  });

  testWidgets('desktop Rules table scrolls horizontally when constrained', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _TestApp(child: RulesPage()));
    await tester.pumpAndSettle();

    expect(
      tester.widget<ButlerlyPage>(find.byType(ButlerlyPage)).fullWidth,
      isTrue,
    );
    expect(find.byKey(const ValueKey('desktop-rules-table')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktop-rules-table-horizontal-scroll')),
      findsOneWidget,
    );
    _expectNoFlutterError(tester);
  });

  testWidgets('Rules and Master Data share Add header icon at all widths', (
    tester,
  ) async {
    for (final width in [390.0, 1400.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final (page, buttonKey, tooltip) in [
        (const RulesPage(), 'rules-add', 'Add rule'),
        (const MasterDataPage(), 'master-data-add', 'Add'),
      ]) {
        await tester.pumpWidget(_TestApp(child: page));
        await tester.pumpAndSettle();

        final commonButton = find.byType(ButlerlyHeaderAddButton);
        expect(commonButton, findsOneWidget);
        final button = find.byKey(ValueKey(buttonKey));
        expect(button, findsOneWidget);
        expect(
          find.descendant(of: button, matching: find.byIcon(Icons.add)),
          findsOneWidget,
        );
        expect(tester.widget<IconButton>(button).tooltip, tooltip);
        expect(
          tester.widget<IconButton>(button).style?.shape?.resolve({}),
          isA<CircleBorder>(),
        );
        expect(
          tester.widget<IconButton>(button).style?.minimumSize?.resolve({}),
          const Size.square(32),
        );
        expect(
          tester.widget<IconButton>(button).style?.maximumSize?.resolve({}),
          const Size.square(32),
        );
        _expectNoFlutterError(tester);
      }
    }
  });

  testWidgets('Rules introduction is localized in Chinese and Spanish', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _TestApp(locale: Locale('zh'), child: RulesPage()),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('规则可根据您设定的条件'), findsOneWidget);
    expect(find.textContaining('保存规则前使用已有交易进行测试'), findsOneWidget);

    await tester.pumpWidget(
      const _TestApp(locale: Locale('es'), child: RulesPage()),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Las reglas te ayudan'), findsOneWidget);
    expect(find.textContaining('Puedes probar una regla'), findsOneWidget);
  });

  testWidgets('rule list remains usable on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _TestApp(child: RulesPage()));
    await tester.pumpAndSettle();

    final exception = tester.takeException();
    if (exception is FlutterError) fail(exception.toStringDeep());
    expect(exception, isNull);
    expect(find.text('Classify fuel'), findsOneWidget);
  });

  testWidgets('rule editor is reachable for create and edit', (tester) async {
    await tester.pumpWidget(const _TestApp(child: RulesPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add rule'));
    await tester.pumpAndSettle();
    expect(find.text('Rule name'), findsOneWidget);
    expect(find.text('Matching conditions'), findsOneWidget);
    expect(find.text('Resulting actions'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit rule'), findsOneWidget);
    expect(find.text('Classify fuel'), findsAtLeastNWidgets(1));
  });

  testWidgets('add rule form remains usable on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _TestApp(child: RulesPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add rule'));
    await tester.pumpAndSettle();

    _expectNoFlutterError(tester);
    expect(find.text('Rule name'), findsOneWidget);

    final fields = find.byWidgetPredicate(
      (widget) =>
          widget is TextField || widget is DropdownButtonFormField<String?>,
    );
    expect(fields, findsNWidgets(14));
    final fieldRects =
        fields
            .evaluate()
            .map((element) => tester.getRect(find.byWidget(element.widget)))
            .toList()
          ..sort((left, right) => left.top.compareTo(right.top));
    for (var index = 1; index < fieldRects.length; index++) {
      expect(
        fieldRects[index].top - fieldRects[index - 1].bottom,
        greaterThanOrEqualTo(ButlerlySpacing.small - 0.001),
      );
    }

    final formScrollable = find
        .ancestor(of: find.text('Rule name'), matching: find.byType(Scrollable))
        .first;
    final scrollableState = tester.state<ScrollableState>(formScrollable);
    expect(scrollableState.position.maxScrollExtent, greaterThan(0));

    await tester.drag(formScrollable, const Offset(0, -1000));
    await tester.pumpAndSettle();
    final lastActionField = fields.last;
    await tester.ensureVisible(lastActionField);
    await tester.pumpAndSettle();

    expect(tester.getRect(lastActionField).bottom, lessThanOrEqualTo(568));
    expect(tester.getRect(find.text('Cancel')).bottom, lessThanOrEqualTo(568));
    expect(tester.getRect(find.text('Save')).bottom, lessThanOrEqualTo(568));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    _expectNoFlutterError(tester);
    expect(find.text('Rule name'), findsNothing);
  });

  testWidgets(
    'add rule uses the shared selection-field base and preserves nullable values',
    (tester) async {
      await tester.pumpWidget(const _TestApp(child: RulesPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add rule'));
      await tester.pumpAndSettle();

      expect(find.byType(ButlerlySelectField<String>), findsNWidgets(9));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is EditableText && widget.controller.text == 'Not set',
        ),
        findsNWidgets(9),
      );

      final merchantSelector = find.byKey(
        const ValueKey('rule-condition-merchant'),
      );
      ButlerlySelectField<String> merchantFieldControl() =>
          tester.widget(merchantSelector);

      merchantFieldControl().onChanged('merchant.costco');
      await tester.pump();

      final merchantField = find.descendant(
        of: find.byKey(const ValueKey('rule-condition-merchant')),
        matching: find.byType(EditableText),
      );
      expect(
        tester.widget<EditableText>(merchantField).controller.text,
        'Costco',
      );

      merchantFieldControl().onChanged('');
      await tester.pump();
      expect(
        tester.widget<EditableText>(merchantField).controller.text,
        'Not set',
      );
      _expectNoFlutterError(tester);
    },
  );

  testWidgets('add rule category choices preserve the two-level hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(const _TestApp(child: RulesPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add rule'));
    await tester.pumpAndSettle();

    List<String> values(String key) => tester
        .widget<ButlerlySelectField<String>>(find.byKey(ValueKey(key)))
        .entries
        .map((entry) => entry.value)
        .toList();

    expect(values('rule-condition-category'), [
      '',
      'category.transport',
      'category.food',
    ]);
    expect(values('rule-action-category'), [
      '',
      'category.transport',
      'category.food',
    ]);
    expect(values('rule-action-subcategory'), ['']);

    final actionCategory = find.byKey(const ValueKey('rule-action-category'));
    tester
        .widget<ButlerlySelectField<String>>(actionCategory)
        .onChanged('category.transport');
    await tester.pump();
    expect(values('rule-action-subcategory'), ['', 'subcategory.fuel']);
    expect(values('rule-action-subcategory'), isNot(contains('category.food')));

    tester
        .widget<ButlerlySelectField<String>>(
          find.byKey(const ValueKey('rule-action-subcategory')),
        )
        .onChanged('subcategory.fuel');
    await tester.pump();
    expect(
      tester
          .widget<ButlerlySelectField<String>>(
            find.byKey(const ValueKey('rule-action-subcategory')),
          )
          .value,
      'subcategory.fuel',
    );

    tester
        .widget<ButlerlySelectField<String>>(actionCategory)
        .onChanged('category.food');
    await tester.pump();
    expect(
      tester
          .widget<ButlerlySelectField<String>>(
            find.byKey(const ValueKey('rule-action-subcategory')),
          )
          .value,
      '',
    );
    expect(values('rule-action-subcategory'), ['', 'subcategory.groceries']);
    _expectNoFlutterError(tester);
  });

  testWidgets('rule preview is live and dry run never updates transactions', (
    tester,
  ) async {
    Transaction transaction(String id, String description) => Transaction(
      id: TransactionId(id),
      timing: KnownTransactionTime(now),
      money: Money(
        amount: DecimalValue.parse('10.00'),
        currency: CurrencyCode('USD'),
      ),
      direction: TransactionDirection.expense,
      sourceType: TransactionSourceType.import,
      description: description,
      rawCounterparty: description,
      provenance: [
        Provenance(
          id: ProvenanceId('provenance.$id'),
          sourceType: ProvenanceSourceType.import,
          capturedAt: now,
          originalRepresentation: description,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    transactions.values.addAll([
      transaction('tx.fuel', 'Fuel for the car'),
      transaction('tx.coffee', 'Coffee purchase'),
    ]);
    final original = List<Transaction>.of(transactions.values);

    await tester.pumpWidget(const _TestApp(child: RulesPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('IF: Description contains "fuel"'),
      findsOneWidget,
    );
    expect(find.textContaining('THEN: Category = Transport'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('rule-test-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 / 2'), findsOneWidget);
    expect(find.textContaining('Fuel for the car'), findsOneWidget);
    expect(transactions.values, orderedEquals(original));
    expect(await rules.listAll(), hasLength(1));

    // Editing matching text invalidates the previous dry-run result.
    final descriptionField = find.widgetWithText(
      TextField,
      'Description contains (optional)',
    );
    await tester.enterText(descriptionField, 'coffee');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rule-test-result')), findsNothing);
    expect(
      find.textContaining('IF: Description contains "coffee"'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('rule-test-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 / 2'), findsOneWidget);
    expect(find.textContaining('Coffee purchase'), findsOneWidget);
    expect(transactions.values, orderedEquals(original));
    expect((await rules.listAll()).single.descriptionContains, 'fuel');
  });

  testWidgets('delete requires confirmation and removes the persisted rule', (
    tester,
  ) async {
    await tester.pumpWidget(const _TestApp(child: RulesPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete rule?'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(await rules.listAll(), isEmpty);
    expect(find.text('No rules yet'), findsOneWidget);
  });
}

void _expectNoFlutterError(WidgetTester tester) {
  final exception = tester.takeException();
  if (exception is FlutterError) fail(exception.toStringDeep());
  expect(exception, isNull);
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child, this.locale});
  final Widget child;
  final Locale? locale;

  @override
  Widget build(BuildContext context) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: Scaffold(body: child),
  );
}

final class _RulesRepository implements TransactionRuleRepository {
  _RulesRepository(Iterable<TransactionRule> values) : values = values.toList();
  final List<TransactionRule> values;

  @override
  Future<TransactionRule?> findById(TransactionRuleId id) async =>
      values.where((value) => value.id == id).firstOrNull;

  @override
  Future<List<TransactionRule>> listAll() async => List.of(values);

  @override
  Future<void> remove(TransactionRuleId id) async {
    values.removeWhere((value) => value.id == id);
  }

  @override
  Future<void> save(TransactionRule rule) async {
    values.removeWhere((value) => value.id == rule.id);
    values.add(rule);
  }
}

final class _Transactions implements TransactionRepository {
  final values = <Transaction>[];

  @override
  Future<Transaction?> findById(TransactionId id) async =>
      values.where((value) => value.id == id).firstOrNull;

  @override
  Future<List<Transaction>> listAll() async => List.of(values);

  @override
  Future<void> removePermanently(TransactionId id) async {
    values.removeWhere((value) => value.id == id);
  }

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async =>
      List.of(values);

  @override
  Future<void> save(Transaction transaction) async {
    values.removeWhere((value) => value.id == transaction.id);
    values.add(transaction);
  }
}

final class _PaymentSources implements PaymentSourceRepository {
  @override
  Future<PaymentSource?> findById(PaymentSourceId id) async => null;

  @override
  Future<List<PaymentSource>> listAll() async => [
    PaymentSource(
      id: PaymentSourceId('source.visa'),
      name: 'Visa',
      type: PaymentSourceType.card,
    ),
  ];

  @override
  Future<void> save(PaymentSource paymentSource) async {}
}

final class _Merchants implements MerchantRepository {
  @override
  Future<Merchant?> findById(MerchantId id) async => null;

  @override
  Future<List<Merchant>> listAll() async => [
    Merchant(id: MerchantId('merchant.costco'), name: 'Costco'),
  ];

  @override
  Future<void> save(Merchant merchant) async {}
}

final class _Categories implements CategoryRepository {
  @override
  Future<Category?> findById(CategoryId id) async => null;

  @override
  Future<List<Category>> listAll() async => [
    Category(
      id: CategoryId('category.transport'),
      name: 'Transport',
      origin: CategoryOrigin.user,
    ),
    Category(
      id: CategoryId('subcategory.fuel'),
      name: 'Fuel',
      origin: CategoryOrigin.user,
      parentId: CategoryId('category.transport'),
    ),
    Category(
      id: CategoryId('category.food'),
      name: 'Food',
      origin: CategoryOrigin.user,
    ),
    Category(
      id: CategoryId('subcategory.groceries'),
      name: 'Groceries',
      origin: CategoryOrigin.user,
      parentId: CategoryId('category.food'),
    ),
  ];

  @override
  Future<void> save(Category category) async {}
}

final class _Tags implements TagRepository {
  @override
  Future<Tag?> findById(TagId id) async => null;

  @override
  Future<List<Tag>> listAll() async => [
    Tag(id: TagId('tag.vehicle'), name: 'Vehicle'),
  ];

  @override
  Future<void> save(Tag tag) async {}
}

final class _Evidence implements EvidenceRepository {
  @override
  Future<void> link(AttachmentLink link) async {}

  @override
  Future<EvidenceItem?> findById(EvidenceId id) async => null;

  @override
  Future<List<EvidenceItem>> listForTransaction(TransactionId id) async => [];

  @override
  Future<void> remove(EvidenceId id) async {}

  @override
  Future<void> save(EvidenceItem evidence) async {}

  @override
  Future<void> saveExtraction(Extraction extraction) async {}
}

final class _Preferences implements UserPreferenceRepository {
  @override
  Future<UserPreference?> load() async => null;

  @override
  Future<void> save(UserPreference preference) async {}
}
