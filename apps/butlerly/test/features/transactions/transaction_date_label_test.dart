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

  test('falls back to the UTC instant date when no business date exists', () {
    final transaction = _transaction(occurredAt: DateTime.utc(2026, 8, 10, 1));

    expect(
      transactionDateLabel(transaction, pendingLabel: 'Date pending'),
      'Aug 10, 2026',
    );
  });

  test('uses the application financial date for timezone-aware results', () {
    final transaction = _transaction(
      occurredAt: DateTime.utc(2026, 10, 1, 6, 30),
      financialDate: DateTime.utc(2026, 9, 30),
    );

    expect(
      transactionDateLabel(transaction, pendingLabel: 'Date pending'),
      'Sep 30, 2026',
    );
    expect(
      transactionCalendarDate(transaction, fallback: DateTime(1970)),
      DateTime.utc(2026, 9, 30),
    );
  });

  test('editor fallback uses the UTC instant calendar date', () {
    final transaction = _transaction(occurredAt: DateTime.utc(2026, 8, 10, 1));

    expect(
      transactionCalendarDate(transaction, fallback: DateTime(2026, 8, 12)),
      DateTime(2026, 8, 10),
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

TransactionDto _transaction({
  DateTime? occurredAt,
  String? transactionDate,
  DateTime? financialDate,
}) => TransactionDto(
  id: 'transaction',
  amount: '12.50',
  currency: 'USD',
  direction: 'expense',
  status: 'active',
  reviewState: 'clear',
  occurredAt: occurredAt,
  transactionDate: transactionDate,
  financialDate: financialDate,
  createdAt: DateTime.utc(2026, 8, 10),
  updatedAt: DateTime.utc(2026, 8, 10),
);
