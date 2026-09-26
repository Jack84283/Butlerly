import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/tools/presentation/rules_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 1, 12);
  late _RulesRepository rules;

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
    services.registerSingleton<FinanceServices>(
      FinanceServices(
        _Transactions(),
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
    expect(find.text('Classify fuel'), findsOneWidget);
    expect(find.text('fuel\nCategory: Transport'), findsOneWidget);

    await tester.tap(find.text('Classify fuel').first);
    await tester.pumpAndSettle();
    expect(find.text('Matching conditions'), findsOneWidget);
    expect(find.text('Resulting actions'), findsOneWidget);
    expect(find.text('Category: Transport'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect((await rules.listAll()).single.enabled, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect((await rules.listAll()).single.enabled, isTrue);
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
        greaterThanOrEqualTo(ButlerlySpacing.small),
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
    'add rule reuses transaction selection fields and preserves values',
    (tester) async {
      await tester.pumpWidget(const _TestApp(child: RulesPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add rule'));
      await tester.pumpAndSettle();

      expect(find.byType(ButlerlySelectField<String>), findsNWidgets(9));
      expect(
        find.byWidgetPredicate((widget) => widget is DropdownMenu<String>),
        findsNWidgets(9),
      );
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
      DropdownMenu<String> merchantMenu() => tester.widget(
        find.descendant(
          of: merchantSelector,
          matching: find.byType(DropdownMenu<String>),
        ),
      );

      merchantMenu().onSelected?.call('merchant.costco');
      await tester.pump();

      final merchantField = find.descendant(
        of: find.byKey(const ValueKey('rule-condition-merchant')),
        matching: find.byType(EditableText),
      );
      expect(
        tester.widget<EditableText>(merchantField).controller.text,
        'Costco',
      );

      merchantMenu().onSelected?.call('');
      await tester.pump();
      expect(
        tester.widget<EditableText>(merchantField).controller.text,
        'Not set',
      );
      _expectNoFlutterError(tester);
    },
  );

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
  const _TestApp({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
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
