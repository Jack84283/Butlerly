import 'package:butlerly/core/evidence/statement_extractor.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts multiple statement rows without inventing header values', () {
    final rows = LocalStatementExtractor.parse('''
Statement for account ****1234
2026-08-12 Grocery Store -42.10 USD
08/13/2026 PAYROLL +1500.00 USD
Balance forward 100.00
''');

    expect(rows, hasLength(2));
    expect(rows.first.description, 'Grocery Store');
    expect(rows.first.amount, '42.1');
    expect(rows.first.direction, TransactionDirection.expense.name);
    expect(rows.last.direction, TransactionDirection.income.name);
  });

  test('preserves unsupported lines only in raw source text', () {
    final rows = LocalStatementExtractor.parse(
      '2026-08-12 unreadable amount USD',
    );
    expect(rows, isEmpty);
  });
}
