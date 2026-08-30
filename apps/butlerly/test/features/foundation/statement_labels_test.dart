import 'package:butlerly/features/foundation/presentation/statement_labels.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en_US');
    await initializeDateFormatting('en_GB');
  });
  final source = PaymentSource(
    id: PaymentSourceId('source'),
    name: 'Chase Sapphire',
    type: PaymentSourceType.card,
  );

  FinancialStatement makeStatement({
    String? sourceId = 'source',
    DateTime? statementDate,
    DateTime? periodEnd,
  }) => FinancialStatement(
    id: 'statement-${statementDate?.day ?? periodEnd?.day ?? 1}',
    evidenceId: 'evidence',
    paymentSourceId: sourceId,
    status: StatementStatus.needsSource,
    institution: 'Issuer fallback',
    statementDate: statementDate,
    periodEnd: periodEnd,
    periodStart: periodEnd == null
        ? null
        : DateTime(periodEnd.year, periodEnd.month, 1),
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 1),
  );

  test('derives distinct source and locale-aware best-date titles', () {
    expect(
      statementDisplayTitleForLocale(
        makeStatement(statementDate: DateTime(2026, 8, 15)),
        [source],
        locale: 'en',
        fallback: 'Statement',
      ),
      'Chase Sapphire · Aug 15, 2026',
    );
    expect(
      statementDisplayTitleForLocale(
        makeStatement(statementDate: DateTime(2026, 8, 15)),
        [source],
        locale: 'zh-CN',
        fallback: 'Statement',
      ),
      'Chase Sapphire · 2026年8月15日',
    );
  });

  test('uses period end, created date, and institution fallback', () {
    expect(
      statementDisplayTitleForLocale(
        makeStatement(periodEnd: DateTime(2026, 7, 31)),
        [source],
        locale: 'en',
        fallback: 'Statement',
      ),
      contains('Jul 31, 2026'),
    );
    expect(
      statementDisplayTitleForLocale(
        makeStatement(),
        [source],
        locale: 'en',
        fallback: 'Statement',
      ),
      contains('Jul 1, 2026'),
    );
    expect(
      statementDisplayTitleForLocale(
        makeStatement(sourceId: null, statementDate: DateTime(2026, 8, 1)),
        const [],
        locale: 'en',
        fallback: 'Statement',
      ),
      startsWith('Issuer fallback ·'),
    );
  });

  test('preserves regional date conventions for English locales', () {
    final value = makeStatement(statementDate: DateTime(2026, 8, 15));
    final us = statementDisplayTitleForLocale(
      value,
      [source],
      locale: 'en-US',
      fallback: 'Statement',
    );
    final gb = statementDisplayTitleForLocale(
      value,
      [source],
      locale: 'en-GB',
      fallback: 'Statement',
    );
    expect(us, 'Chase Sapphire · Aug 15, 2026');
    expect(gb, 'Chase Sapphire · 15 Aug 2026');
    expect(us, isNot(gb));
  });
}
