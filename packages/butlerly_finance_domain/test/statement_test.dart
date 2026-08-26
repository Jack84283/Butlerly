import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test('completed statement rows require a canonical transaction link', () {
    expect(
      () => StatementRow(
        id: 'row',
        statementId: 'statement',
        position: 0,
        originalText: 'source row',
        status: StatementRowStatus.saved,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      throwsA(isA<DomainValidationException>()),
    );
  });

  test('statement period cannot be partial or reversed', () {
    expect(
      () => FinancialStatement(
        id: 'statement',
        evidenceId: 'evidence',
        status: StatementStatus.ready,
        periodStart: DateTime.utc(2026, 2),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      throwsA(isA<DomainValidationException>()),
    );
  });
}
