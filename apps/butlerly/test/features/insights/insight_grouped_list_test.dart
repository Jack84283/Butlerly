import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/insights/presentation/insight_grouped_list.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'maps rule grouping to presentation section without semantic coupling',
    () {
      expect(
        insightPresentationGroup(
          _insight(
            RuleGrouping.transaction,
            semanticType: InsightSemanticType.attention,
          ),
        ),
        InsightPresentationGroup.unusual,
      );
      expect(
        insightPresentationGroup(_insight(RuleGrouping.transaction)),
        InsightPresentationGroup.other,
      );
      expect(
        insightPresentationGroup(
          _insight(
            RuleGrouping.transaction,
            semanticType: InsightSemanticType.positive,
          ),
        ),
        InsightPresentationGroup.other,
      );
      expect(
        insightPresentationGroup(_insight(RuleGrouping.category)),
        InsightPresentationGroup.category,
      );
      expect(
        insightPresentationGroup(_insight(RuleGrouping.subcategory)),
        InsightPresentationGroup.subcategory,
      );
      expect(
        insightPresentationGroup(_insight(RuleGrouping.tag)),
        InsightPresentationGroup.tag,
      );
      expect(
        insightPresentationGroup(_insight(RuleGrouping.merchant)),
        InsightPresentationGroup.merchant,
      );
      expect(
        insightPresentationGroup(_insight(RuleGrouping.paymentSource)),
        InsightPresentationGroup.paymentSource,
      );
      expect(
        insightPresentationGroup(_insight(RuleGrouping.none)),
        InsightPresentationGroup.other,
      );
    },
  );

  test(
    'uses authored presentation role for unusually large purchase section',
    () {
      expect(
        insightPresentationGroup(
          _insight(
            RuleGrouping.transaction,
            role: 'largePurchase',
            operation: RuleOperation.maximum,
            visualizationType: InsightVisualizationType.comparison,
            semanticType: InsightSemanticType.attention,
          ),
        ),
        InsightPresentationGroup.largePurchase,
      );
      expect(
        insightPresentationGroup(
          _insight(
            RuleGrouping.transaction,
            operation: RuleOperation.maximum,
            visualizationType: InsightVisualizationType.comparison,
            semanticType: InsightSemanticType.attention,
          ),
        ),
        InsightPresentationGroup.unusual,
      );
    },
  );

  testWidgets('Home counts the same visible Insight groups as device cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final summaries = insightGroupSummaries(context, [
              _insight(
                RuleGrouping.transaction,
                semanticType: InsightSemanticType.attention,
              ),
              _insight(
                RuleGrouping.transaction,
                semanticType: InsightSemanticType.attention,
              ),
              _insight(
                RuleGrouping.transaction,
                role: 'largePurchase',
                semanticType: InsightSemanticType.attention,
              ),
              _insight(RuleGrouping.category),
              _insight(RuleGrouping.merchant),
              _insight(
                RuleGrouping.paymentSource,
                visualizationType: InsightVisualizationType.pie,
              ),
            ]);
            expect(summaries.map((group) => group.group).toList(), [
              InsightPresentationGroup.unusual,
              InsightPresentationGroup.largePurchase,
              InsightPresentationGroup.category,
              InsightPresentationGroup.merchant,
            ]);
            expect(summaries.map((group) => group.count).toList(), [
              2,
              1,
              1,
              1,
            ]);
            expect(summaries.every((group) => group.title.isNotEmpty), isTrue);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });

  testWidgets('Insights group cards use standard shared padding', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: InsightGroupedList(
              results: [
                _insight(RuleGrouping.category),
                _insight(RuleGrouping.subcategory),
                _insight(RuleGrouping.merchant),
              ],
              visualizationResults: const [],
              masterData: const TransactionMasterData(),
              canViewTransactions: (_) => false,
              onViewTransactions: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final outerCards = tester
        .widgetList<ButlerlyCard>(find.byType(ButlerlyCard))
        .where((card) => card.semanticLabel != null)
        .toList();
    expect(outerCards, hasLength(3));
    for (final card in outerCards) {
      expect(
        card.padding,
        const EdgeInsets.all(ButlerlySpacing.cardPadding),
      );
    }
    expect(tester.takeException(), isNull);
  });

  test('recognizes an all-positive fallback group', () {
    expect(
      insightGroupIsPositiveOnly([
        _insight(RuleGrouping.none, semanticType: InsightSemanticType.positive),
        _insight(RuleGrouping.none, semanticType: InsightSemanticType.positive),
      ]),
      isTrue,
    );
    expect(
      insightGroupIsPositiveOnly([
        _insight(RuleGrouping.none, semanticType: InsightSemanticType.positive),
        _insight(
          RuleGrouping.none,
          semanticType: InsightSemanticType.attention,
        ),
      ]),
      isFalse,
    );
    expect(insightGroupIsPositiveOnly(const []), isFalse);
  });
}

InsightResult _insight(
  RuleGrouping grouping, {
  InsightSemanticType semanticType = InsightSemanticType.neutral,
  RuleOperation operation = RuleOperation.sum,
  InsightVisualizationType visualizationType = InsightVisualizationType.none,
  String? role,
}) {
  final context = AnalysisContext(
    period: AnalysisPeriod(
      startDate: '2026-09-01',
      endDate: '2026-09-10',
      timeZoneId: 'America/Los_Angeles',
    ),
    datasetMode: DatasetMode.allEligible,
    currencyBasis: CurrencyBasis.baseCurrency,
    baseCurrency: CurrencyCode('USD'),
  );
  final rule = AnalysisRuleDefinition(
    identity: RuleIdentity('ANL-R999'),
    version: RuleVersion('1.0.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.insight,
    nameKey: 'analysisSummary',
    descriptionKey: 'analysisSummary',
    enabled: true,
    status: AnalysisRuleStatus.active,
    period: 'selected_period',
    measure: RuleMeasure(
      operation: operation,
      field: 'amount',
      currencyBasis: CurrencyBasis.baseCurrency,
    ),
    grouping: grouping,
    baseline: RuleBaseline.previousEquivalentPeriod,
    condition: const RuleCondition(operator: 'always'),
    severity: RuleSeverity.info,
    definitionHash: RuleDefinitionHash('9' * 64),
    surface: AnalysisSurface.insights,
    role: role,
    presentation: InsightPresentation(
      semanticType: semanticType,
      visualizationType: visualizationType,
      primaryMetric: InsightPrimaryMetric.amount,
    ),
  );
  return InsightResult(
    outputType: InsightOutputType.pattern,
    rule: rule,
    context: context,
    currentValue: DecimalValue.parse('10'),
    currency: CurrencyCode('USD'),
  );
}
