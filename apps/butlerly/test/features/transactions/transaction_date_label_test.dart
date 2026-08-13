import 'package:butlerly/features/foundation/presentation/transaction_date_label.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('en'));
  test('prefers the canonical business date over the exact UTC instant', () {
    final transaction = _transaction(
      occurredAt: DateTime.utc(2026, 8, 10, 1),
      transactionDate: '2026-08-09',
    );

    expect(
      transactionDateLabel(transaction, pendingLabel: 'Date pending'),
      'Aug 9, 2026',
    );
  });

  test('falls back to the exact instant date when no business date exists', () {
    final transaction = _transaction(occurredAt: DateTime.utc(2026, 8, 10, 1));

    expect(
      transactionDateLabel(transaction, pendingLabel: 'Date pending'),
      'Aug 9, 2026',
    );
  });

  test('editor date uses the canonical business calendar date', () {
    final transaction = _transaction(
      occurredAt: DateTime.utc(2026, 8, 11, 4),
      transactionDate: '2026-08-10',
    );

    expect(
      transactionCalendarDate(transaction, fallback: DateTime(2026, 8, 12)),
      DateTime(2026, 8, 10),
    );
  });
}

TransactionDto _transaction({DateTime? occurredAt, String? transactionDate}) =>
    TransactionDto(
      id: 'transaction',
      amount: '12.50',
      currency: 'USD',
      direction: 'expense',
      status: 'active',
      reviewState: 'clear',
      occurredAt: occurredAt,
      transactionDate: transactionDate,
      createdAt: DateTime.utc(2026, 8, 10),
      updatedAt: DateTime.utc(2026, 8, 10),
    );
