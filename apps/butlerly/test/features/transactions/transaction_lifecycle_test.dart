import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MemoryTransactionRepository repository;

  setUp(() async {
    await services.reset();
    repository = MemoryTransactionRepository();
    services.registerSingleton<FinanceServices>(FinanceServices(repository));
  });

  tearDown(() => services.reset());

  testWidgets('creates, edits, archives, and permanently deletes locally', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: TransactionsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add transaction').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '12.50');
    await tester.enterText(find.byType(TextFormField).at(2), 'Lunch');
    await tester.tap(find.text('Save locally'));
    await tester.pumpAndSettle();

    expect(find.text('Lunch'), findsOneWidget);
    await tester.tap(find.text('Lunch'));
    await tester.pumpAndSettle();
    expect(find.text('Transaction detail'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(2), 'Corrected lunch');
    await tester.tap(find.text('Save locally'));
    await tester.pumpAndSettle();
    expect(find.text('Transactions'), findsOneWidget);

    await tester.tap(find.text('Corrected lunch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive transaction'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Corrected lunch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Permanently delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();

    expect(find.text('No transactions yet'), findsOneWidget);
  });
}

final class MemoryTransactionRepository implements TransactionRepository {
  final values = <String, Transaction>{};

  @override
  Future<Transaction?> findById(TransactionId id) async => values[id.value];

  @override
  Future<List<Transaction>> listAll() async => values.values.toList();

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async =>
      values.values.toList();

  @override
  Future<void> removePermanently(TransactionId id) async {
    values.remove(id.value);
  }

  @override
  Future<void> save(Transaction transaction) async {
    values[transaction.id.value] = transaction;
  }
}
