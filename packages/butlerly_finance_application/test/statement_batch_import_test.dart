import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  late _Transactions transactions;
  late _Statements statements;
  late _Groups groups;
  late StatementServices service;
  final now = DateTime.utc(2026, 8, 29);

  setUp(() {
    transactions = _Transactions();
    statements = _Statements(transactions);
    groups = _Groups();
    service = StatementServices(
      statements,
      transactions,
      statements,
      _Clock(now),
      duplicateGroups: groups,
      duplicateChecker: DuplicateTransactionChecker(transactions),
    );
  });

  test(
    'assesses count, invalid rows, aggregate and confidence before import',
    () async {
      final result = await service.assessBatch(_statement(), [
        _row('one', amount: '12', confidence: .49),
        _row('two', amount: '8', confidence: .50),
        _row('invalid', amount: null),
      ], 'source');
      final value =
          (result as ApplicationSuccess<StatementImportAssessment>).value;
      expect(value.candidateCount, 3);
      expect(value.aggregateAmount, '20');
      expect(value.lowConfidenceCount, 2);
      expect(value.invalidCount, 1);
    },
  );

  test(
    'imports valid rows, retains low-confidence review, and tolerates invalid rows',
    () async {
      final result = await service.importBatch(_statement(), [
        _row('low', amount: '12', confidence: .49),
        _row('boundary', amount: '8', confidence: .50),
        _row('high', amount: '4', confidence: .51),
        _row('invalid', amount: null),
      ], 'source');
      final value =
          (result as ApplicationSuccess<StatementImportSummary>).value;
      expect(value.imported, 3);
      expect(value.needsReview, 2);
      expect(value.possibleDuplicates, 0);
      expect(value.failed, 1);
      expect(
        transactions.values['statement-statement-row-low']!.reviewIssues,
        hasLength(1),
      );
      expect(
        transactions.values['statement-statement-row-boundary']!.reviewIssues,
        hasLength(1),
      );
      expect(
        transactions.values['statement-statement-row-high']!.reviewIssues,
        isEmpty,
      );
    },
  );

  test(
    'assesses and persists duplicate candidates without blocking other rows',
    () async {
      transactions.values['existing'] = _transaction('existing', amount: '12');
      final rows = [
        _row('duplicate', amount: '12'),
        _row('other', amount: '7'),
      ];
      final assessment =
          (await service.assessBatch(_statement(), rows, 'source')
                  as ApplicationSuccess<StatementImportAssessment>)
              .value;
      expect(assessment.possibleDuplicateCount, 1);
      final summary =
          (await service.importBatch(_statement(), rows, 'source')
                  as ApplicationSuccess<StatementImportSummary>)
              .value;
      expect(summary.imported, 2);
      expect(summary.possibleDuplicates, 1);
      expect(groups.values, hasLength(1));
      expect(
        groups.values.values.single.status,
        DuplicateCandidateGroupStatus.unresolved,
      );
      expect(
        groups.values.values.single.transactionIds.map((id) => id.value),
        contains('statement-statement-row-duplicate'),
      );
    },
  );

  test(
    'rejects a mismatched statement PaymentSource safely and is idempotent for saved rows',
    () async {
      final statement = _statement(paymentSourceId: 'source-a');
      expect(
        await service.importBatch(statement, [_row('one')], 'source-b'),
        isA<ApplicationFailure<StatementImportSummary>>(),
      );
      final first = await service.importBatch(_statement(), [
        _row('one'),
      ], 'source');
      final second = await service.importBatch(_statement(), [
        _row('one'),
      ], 'source');
      expect((first as ApplicationSuccess).value.imported, 1);
      expect((second as ApplicationSuccess).value.imported, 1);
      expect(transactions.values, hasLength(2));
      expect(statements.rows.single.status, StatementRowStatus.saved);
      final imported = transactions.values['statement-statement-row-one']!;
      expect(imported.provenance.single.sourceId, 'statement');
      expect(
        imported.provenance.single.originalRepresentation,
        contains('Merchant'),
      );
    },
  );

  test('skip and restore toggle the existing statement row', () async {
    for (final previous in [
      StatementRowStatus.pending,
      StatementRowStatus.unresolved,
      StatementRowStatus.deferred,
    ]) {
      final row = _row('toggle-${previous.name}', status: previous);
      statements.rows
        ..clear()
        ..add(row);
      await service.setDisposition(row, StatementRowStatus.skipped);
      expect(statements.rows.single.status, StatementRowStatus.skipped);
      expect(statements.rows.single.statusBeforeSkip, previous);
      await service.setDisposition(statements.rows.single, previous);
      expect(statements.rows, hasLength(1));
      expect(statements.rows.single.status, previous);
      expect(statements.rows.single.statusBeforeSkip, isNull);
      expect(statements.rows.single.originalText, row.originalText);
    }
  });

  test('statement intake defaults missing currency and direction', () async {
    final row = _row('defaults', currency: null, direction: null);
    final result = await service.create(_statement(), [row]);
    expect(result, isA<ApplicationSuccess<void>>());
    expect(statements.rows.single.currency, 'USD');
    expect(statements.rows.single.direction, TransactionDirection.expense.name);
    expect(statements.rows.single.originalText, row.originalText);
    expect(
      statements.rows.single.sourceContext,
      contains('statement intake default applied'),
    );
  });

  test('abandon import cannot remove a protected statement', () async {
    statements.rows.add(
      _row('protected', transactionId: 'existing-transaction'),
    );
    final result = await service.abandonImport('statement');
    expect(result, isA<ApplicationFailure<EvidenceItem?>>());
    expect(statements.rows, hasLength(1));
  });
}

FinancialStatement _statement({String? paymentSourceId}) => FinancialStatement(
  id: 'statement',
  evidenceId: 'evidence',
  paymentSourceId: paymentSourceId,
  status: StatementStatus.ready,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
  periodStart: DateTime.utc(2026, 8, 1),
  periodEnd: DateTime.utc(2026, 8, 31),
);

StatementRow _row(
  String id, {
  String? amount = '12',
  double confidence = .9,
  String? transactionId,
  StatementRowStatus status = StatementRowStatus.pending,
  String? currency = 'USD',
  String? direction = 'expense',
}) => StatementRow(
  id: 'row-$id',
  statementId: 'statement',
  position: 0,
  originalText: 'Merchant $id',
  transactionDate: DateTime.utc(2026, 8, 20),
  description: 'Merchant $id',
  amount: amount,
  currency: currency,
  direction: direction,
  confidence: confidence,
  transactionId: transactionId,
  status: status,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
);

Transaction _transaction(String id, {required String amount}) => Transaction(
  id: TransactionId(id),
  timing: const UnknownTransactionTime(UnknownTransactionTimeReason.unknown),
  money: Money(
    amount: DecimalValue.parse(amount),
    currency: CurrencyCode('USD'),
  ),
  direction: TransactionDirection.expense,
  sourceType: TransactionSourceType.manual,
  transactionDate: '2026-08-20',
  provenance: [
    Provenance(
      id: ProvenanceId('$id-p'),
      sourceType: ProvenanceSourceType.userEntry,
      capturedAt: DateTime.utc(2026, 8, 20),
      originalRepresentation: id,
    ),
  ],
  createdAt: DateTime.utc(2026, 8, 20),
  updatedAt: DateTime.utc(2026, 8, 20),
);

final class _Clock implements ApplicationClock {
  const _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

final class _Transactions implements TransactionRepository {
  final values = <String, Transaction>{}
    ..addAll({'seed': _transaction('seed', amount: '99')});
  @override
  Future<void> save(Transaction value) async => values[value.id.value] = value;
  @override
  Future<Transaction?> findById(TransactionId id) async => values[id.value];
  @override
  Future<List<Transaction>> listAll() async => values.values.toList();
  @override
  Future<void> removePermanently(TransactionId id) async =>
      values.remove(id.value);
  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async =>
      values.values
          .where(
            (v) =>
                v.status == query.status &&
                v.transactionDate == '2026-08-20' &&
                v.money.currency.value == query.currency &&
                v.money.amount == DecimalValue.parse('12'),
          )
          .toList();
}

final class _Statements
    implements StatementRepository, StatementWorkflowRepository {
  _Statements(this.transactions);
  final _Transactions transactions;
  final rows = <StatementRow>[];
  @override
  Future<void> saveStatement(FinancialStatement value) async {}
  @override
  Future<void> saveRows(List<StatementRow> value) async => rows.addAll(value);
  @override
  Future<FinancialStatement?> findStatement(String id) async => _statement();
  @override
  Future<List<FinancialStatement>> listStatements({
    bool includeArchived = false,
  }) async => [_statement()];
  @override
  Future<List<StatementRow>> listRows(String id) async => rows;
  @override
  Future<void> assignPaymentSource(
    String id,
    String sourceId,
    DateTime updatedAt,
  ) async {}
  @override
  Future<void> updateRow(StatementRow row) async {
    rows.removeWhere((v) => v.id == row.id);
    rows.add(row);
  }

  @override
  Future<bool> canDeleteStatement(String id) async =>
      !rows.any((row) => row.transactionId != null);

  @override
  Future<void> removeStatement(String id) async {}
  @override
  Future<void> saveRowTransaction(
    StatementRow row,
    Transaction transaction,
  ) async {
    await transactions.save(transaction);
    await updateRow(row);
  }

  @override
  Future<void> linkRow(StatementRow row) async => updateRow(row);
}

final class _Groups implements DuplicateCandidateGroupRepository {
  final values = <String, DuplicateCandidateGroup>{};
  @override
  Future<void> save(DuplicateCandidateGroup group) async =>
      values[group.id] = group;
  @override
  Future<List<DuplicateCandidateGroup>> list({
    DuplicateCandidateGroupStatus? status,
  }) async => values.values.toList();
  @override
  Future<List<DuplicateTransactionGroupMatch>>
  findActiveDuplicateGroups() async => [];
  @override
  Future<List<TransactionId>> findActiveTransactionIdsForKey(
    DuplicateTransactionKey key,
  ) async => [];
  @override
  Future<void> remove(String id) async => values.remove(id);
}
