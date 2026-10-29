import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite;
import 'package:test/test.dart';

import 'support/persisted_financial_fixture.dart';

void main() {
  setUpAll(sqflite.sqfliteFfiInit);

  test(
    'file-backed duplicate decisions, provenance, stale state, and overlaps survive restart',
    () async {
      final fixture = await PersistedFinancialFixture.create();
      addTearDown(fixture.dispose);
      final now = DateTime.utc(2026, 9, 1);
      final original = _transaction('canonical-original', '10');
      final selected = _transaction('canonical-selected', '10');
      final unresolvedA = _transaction('unresolved-a', '15');
      final unresolvedB = _transaction('unresolved-b', '15');
      final staleA = _transaction('stale-a', '20');
      final staleB = _transaction('stale-b', '21');
      final overlapA = _transaction('overlap-a', '25');
      final overlapB = _transaction('overlap-b', '25');
      final overlapC = _transaction('overlap-c', '25');
      final malformed = _transaction('malformed-a', '35');
      final receipt = _transaction(
        'receipt',
        '30',
        sourceType: TransactionSourceType.evidenceCapture,
      );
      final payment = _transaction(
        'payment',
        '30',
        sourceType: TransactionSourceType.import,
      );
      final malformedLinkReceipt = _transaction('malformed-link-receipt', '31');
      final values = [
        original,
        selected,
        unresolvedA,
        unresolvedB,
        staleA,
        staleB,
        overlapA,
        overlapB,
        overlapC,
        malformed,
        receipt,
        payment,
        malformedLinkReceipt,
      ];
      for (final value in values) {
        await fixture.saveTransaction(value);
      }
      await fixture.saveReconciliationLink(
        id: 'receipt-link',
        receiptTransactionId: receipt.id,
        paymentTransactionId: payment.id,
        createdAt: now,
      );
      await fixture.database.connection.insert('reconciliation_candidates', {
        'id': 'malformed-link-candidate',
        'receipt_transaction_id': receipt.id.value,
        'payment_transaction_id': malformedLinkReceipt.id.value,
        'score': 1.0,
        'reasons_json': '[]',
        'status': ReconciliationCandidateStatus.confirmed.name,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await fixture.database.connection.insert('reconciliation_links', {
        'id': 'malformed-link',
        'candidate_id': 'malformed-link-candidate',
        'receipt_transaction_id': malformedLinkReceipt.id.value,
        'payment_transaction_id': payment.id.value,
        'created_at': now.toIso8601String(),
      });
      await fixture.saveDuplicateGroup(
        _group(
          'consolidated',
          [original.id, selected.id],
          key: _key('10'),
          status: DuplicateCandidateGroupStatus.consolidated,
          selected: selected.id,
        ),
      );
      await fixture.saveDuplicateGroup(
        _group(
          'unresolved',
          [unresolvedB.id, unresolvedA.id],
          key: _key('15'),
          status: DuplicateCandidateGroupStatus.unresolved,
        ),
      );
      await fixture.saveDuplicateGroup(
        _group(
          'stale',
          [staleA.id, staleB.id],
          key: _key('20'),
          status: DuplicateCandidateGroupStatus.consolidated,
          selected: staleA.id,
        ),
      );
      await fixture.saveDuplicateGroup(
        _group(
          'overlap-a',
          [overlapA.id, overlapB.id, overlapC.id],
          key: _key('25'),
          status: DuplicateCandidateGroupStatus.keepBoth,
        ),
      );
      await fixture.saveDuplicateGroup(
        _group(
          'overlap-b',
          [overlapA.id, overlapB.id, overlapC.id],
          key: _key('25'),
          status: DuplicateCandidateGroupStatus.keepBoth,
        ),
      );
      // A malformed persisted decision must be reconstructed as repair-needed,
      // not discarded or treated as a healthy resolution.
      await fixture.database.connection.insert('duplicate_candidate_groups', {
        'id': 'malformed',
        'transaction_date': '2026-09-01',
        'amount_coefficient': 'not-a-decimal',
        'amount_scale': 2,
        'currency': 'USD',
        'direction': 'expense',
        'status': 'not-a-status',
        'selected_transaction_id': null,
        'statement_rows': '[]',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      await fixture.reopen();

      final groups = await fixture.duplicateGroups.list();
      final byId = {for (final group in groups) group.id: group};
      expect(byId['consolidated']?.status, isNotNull);
      expect(
        byId['consolidated']?.status,
        DuplicateCandidateGroupStatus.consolidated,
      );
      expect(byId['consolidated']?.selectedTransactionId, selected.id);
      expect(
        byId['unresolved']?.status,
        DuplicateCandidateGroupStatus.unresolved,
      );
      expect(byId['stale']?.status, DuplicateCandidateGroupStatus.unresolved);
      expect(byId['stale']?.integrityIssue?.code, 'staleDuplicateGroup');
      expect(byId['overlap-a']?.transactionIds, [
        overlapA.id,
        overlapB.id,
        overlapC.id,
      ]);
      expect(byId['overlap-b']?.transactionIds, [
        overlapA.id,
        overlapB.id,
        overlapC.id,
      ]);
      expect(
        byId['malformed']?.status,
        DuplicateCandidateGroupStatus.unresolved,
      );
      expect(
        byId['malformed']?.integrityIssue?.code,
        'malformedDuplicateGroup',
      );

      final restoredTransactions = await fixture.transactions.listAll();
      expect(
        restoredTransactions
            .firstWhere((value) => value.id == original.id)
            .provenance
            .single
            .id,
        original.provenance.single.id,
      );
      final canonical = selectCanonicalTransactions(
        source: restoredTransactions,
        links: await fixture.reconciliationLinks.listAll(),
        reconciliationCandidates: await fixture.reconciliationCandidates
            .listAll(),
        duplicateGroups: groups,
      );
      expect(canonical.transactions.map((value) => value.id.value), [
        'canonical-selected',
        'malformed-a',
        'malformed-link-receipt',
        'overlap-a',
        'overlap-b',
        'overlap-c',
        'payment',
        'stale-a',
        'stale-b',
        'unresolved-a',
      ]);
      expect(canonical.qualityIssues.map((issue) => issue.code), [
        'malformedDuplicateGroup',
        'malformedReconciliationLink',
        'staleDuplicateGroup',
        'unresolvedDuplicate',
      ]);
    },
  );

  test(
    'editing duplicate facts, adding/removing members, archive restore, and repair preserve source data',
    () async {
      final edits = <String, Transaction Function(Transaction)>{
        'date': (value) => _copy(value, date: '2026-09-02'),
        'amount': (value) => _copy(value, amount: '11'),
        'currency': (value) => _copy(value, currency: 'EUR'),
        'direction': (value) =>
            _copy(value, direction: TransactionDirection.income),
      };

      for (final entry in edits.entries) {
        final fixture = await PersistedFinancialFixture.create();
        final original = _transaction('original', '10');
        final duplicate = _transaction('duplicate', '10');
        await fixture.saveTransaction(original);
        await fixture.saveTransaction(duplicate);
        await fixture.saveDuplicateGroup(
          _group(
            'decision',
            [original.id, duplicate.id],
            key: _key('10'),
            status: DuplicateCandidateGroupStatus.consolidated,
            selected: original.id,
          ),
        );
        await fixture.saveTransaction(entry.value(duplicate));
        await fixture.reopen();

        final group = (await fixture.duplicateGroups.list()).single;
        expect(group.status, DuplicateCandidateGroupStatus.unresolved);
        expect(group.integrityIssue?.code, 'staleDuplicateGroup');
        final canonical = selectCanonicalTransactions(
          source: await fixture.transactions.listAll(),
          duplicateGroups: [group],
        );
        expect(canonical.transactions.map((value) => value.id.value), [
          'duplicate',
          'original',
        ], reason: entry.key);
        expect(
          await fixture.duplicateGroups.list(),
          hasLength(1),
          reason: entry.key,
        );
        await fixture.dispose();
      }

      final fixture = await PersistedFinancialFixture.create();
      addTearDown(fixture.dispose);
      final original = _transaction('original', '10');
      final duplicate = _transaction('duplicate', '10');
      await fixture.saveTransaction(original);
      await fixture.saveTransaction(duplicate);
      await fixture.saveDuplicateGroup(
        _group(
          'decision',
          [original.id, duplicate.id],
          key: _key('10'),
          status: DuplicateCandidateGroupStatus.consolidated,
          selected: original.id,
        ),
      );

      final matching = _transaction('matching', '10');
      await fixture.saveTransaction(matching);
      await fixture.reopen();
      var group = (await fixture.duplicateGroups.list()).single;
      expect(group.transactionIds, [duplicate.id, matching.id, original.id]);
      expect(group.status, DuplicateCandidateGroupStatus.unresolved);
      expect(group.integrityIssue?.code, 'incompleteDuplicateGroup');

      await fixture.transactions.removePermanently(matching.id);
      await fixture.reopen();
      group = (await fixture.duplicateGroups.list()).single;
      expect(group.transactionIds, [duplicate.id, original.id]);
      expect(group.integrityIssue, isNull);

      final archived = duplicate.archive(DateTime.utc(2026, 9, 2));
      await fixture.saveTransaction(archived);
      await fixture.reopen();
      expect(
        await fixture.duplicateGroups.findActiveTransactionIdsForKey(
          _key('10'),
        ),
        [original.id],
      );
      final editedArchived = _copy(archived, amount: '13');
      await fixture.saveTransaction(editedArchived);
      await fixture.reopen();
      group = (await fixture.duplicateGroups.list()).single;
      expect(group.transactionIds, [duplicate.id, original.id]);
      expect(group.integrityIssue?.code, 'staleDuplicateGroup');
      expect(
        (await fixture.transactions.listAll())
            .singleWhere((value) => value.id == duplicate.id)
            .money
            .amount,
        DecimalValue.parse('13'),
      );
      await fixture.saveTransaction(
        editedArchived.restore(DateTime.utc(2026, 9, 3)),
      );
      await fixture.reopen();
      expect(
        await fixture.duplicateGroups.findActiveTransactionIdsForKey(
          _key('10'),
        ),
        [original.id],
      );

      final stale = _copy(duplicate, amount: '12');
      await fixture.saveTransaction(stale);
      await fixture.reopen();
      group = (await fixture.duplicateGroups.list()).single;
      expect(group.integrityIssue?.code, 'staleDuplicateGroup');
      final ordinary = await ResolveDuplicateCandidateGroup(
        fixture.duplicateGroups,
        _Clock(DateTime.utc(2026, 9, 4)),
      )(group.id, DuplicateCandidateGroupStatus.keepBoth);
      expect(ordinary, isA<ApplicationFailure<void>>());

      final repaired = await RepairDuplicateCandidateGroup(
        fixture.duplicateGroups,
        _Clock(DateTime.utc(2026, 9, 5)),
      )(group.id);
      expect(repaired, isA<ApplicationSuccess<void>>());
      await fixture.reopen();
      expect(await fixture.duplicateGroups.list(), isEmpty);
      final sourceAfterRepair = await fixture.transactions.listAll();
      expect(sourceAfterRepair.map((value) => value.id.value), [
        'duplicate',
        'original',
      ]);
      expect(
        sourceAfterRepair.every((value) => value.provenance.isNotEmpty),
        isTrue,
      );
    },
  );

  test(
    'persisted reconciliation role and endpoint conflicts remain repair-needed after restart',
    () async {
      final fixture = await PersistedFinancialFixture.create();
      addTearDown(fixture.dispose);
      final receipt = _transaction(
        'receipt-role',
        '30',
        sourceType: TransactionSourceType.evidenceCapture,
      );
      final payment = _transaction(
        'payment-role',
        '30',
        sourceType: TransactionSourceType.import,
      );
      final otherPayment = _transaction(
        'other-payment-role',
        '30',
        sourceType: TransactionSourceType.import,
      );
      final invalidReceipt = _transaction('invalid-receipt-role', '30');
      for (final value in [receipt, payment, otherPayment, invalidReceipt]) {
        await fixture.saveTransaction(value);
      }
      await fixture.saveReconciliationLink(
        id: 'valid-role-link',
        receiptTransactionId: receipt.id,
        paymentTransactionId: payment.id,
      );
      await fixture.saveReconciliationCandidate(
        ReconciliationCandidate(
          id: 'conflicting-link-candidate',
          receiptTransactionId: receipt.id,
          paymentTransactionId: otherPayment.id,
          score: 1,
          reasons: const [],
          status: ReconciliationCandidateStatus.confirmed,
        ),
      );
      await fixture.saveReconciliationCandidate(
        ReconciliationCandidate(
          id: 'invalid-role-candidate',
          receiptTransactionId: invalidReceipt.id,
          paymentTransactionId: otherPayment.id,
          score: 1,
          reasons: const [],
          status: ReconciliationCandidateStatus.confirmed,
        ),
      );
      final now = DateTime.utc(2026, 9, 1).toIso8601String();
      await fixture.database.connection.insert('reconciliation_links', {
        'id': 'conflicting-link',
        'candidate_id': 'conflicting-link-candidate',
        'receipt_transaction_id': receipt.id.value,
        'payment_transaction_id': otherPayment.id.value,
        'created_at': now,
      });
      await fixture.database.connection.insert('reconciliation_links', {
        'id': 'invalid-role-link',
        'candidate_id': 'invalid-role-candidate',
        'receipt_transaction_id': invalidReceipt.id.value,
        'payment_transaction_id': otherPayment.id.value,
        'created_at': now,
      });

      await fixture.reopen();
      final selection = selectCanonicalTransactions(
        source: await fixture.transactions.listAll(),
        links: await fixture.reconciliationLinks.listAll(),
        reconciliationCandidates: await fixture.reconciliationCandidates
            .listAll(),
      );

      expect(selection.transactions.map((value) => value.id.value), [
        'invalid-receipt-role',
        'other-payment-role',
        'payment-role',
        'receipt-role',
      ]);
      expect(
        selection.qualityIssues.map((issue) => issue.code),
        containsAll([
          'malformedReconciliationLink',
          'conflictingReconciliationLinks',
        ]),
      );
    },
  );

  test(
    'a confirmed manual reconciliation survives payment-source removal and restart',
    () async {
      final fixture = await PersistedFinancialFixture.create();
      addTearDown(fixture.dispose);
      final now = DateTime.utc(2026, 9, 1);
      final paymentSource = PaymentSource(
        id: PaymentSourceId('manual-card'),
        name: 'Manual card',
        type: PaymentSourceType.card,
      );
      final receipt = _transaction(
        'confirmed-receipt',
        '30',
        sourceType: TransactionSourceType.evidenceCapture,
      );
      final payment = _transaction(
        'confirmed-payment',
        '30',
      ).assignPaymentSource(paymentSource.id, now);
      await fixture.savePaymentSource(paymentSource);
      await fixture.saveTransaction(receipt);
      await fixture.saveTransaction(payment);
      await fixture.saveReconciliationLink(
        id: 'confirmed-manual-link',
        receiptTransactionId: receipt.id,
        paymentTransactionId: payment.id,
        createdAt: now,
      );

      final initial = selectCanonicalTransactions(
        source: await fixture.transactions.listAll(),
        links: await fixture.reconciliationLinks.listAll(),
        reconciliationCandidates: await fixture.reconciliationCandidates
            .listAll(),
      );
      expect(initial.transactions.map((value) => value.id.value), [
        'confirmed-payment',
      ]);

      final cleared = await AssignPaymentSource(
        fixture.transactions,
        fixture.paymentSources,
        _Clock(DateTime.utc(2026, 9, 2)),
      )(payment.id.value, null);
      expect(cleared, isA<ApplicationSuccess<TransactionDto>>());
      await fixture.reopen();

      final persistedPayment = await fixture.transactions.findById(payment.id);
      expect(persistedPayment?.paymentSourceId, isNull);
      final afterMetadataChange = selectCanonicalTransactions(
        source: await fixture.transactions.listAll(),
        links: await fixture.reconciliationLinks.listAll(),
        reconciliationCandidates: await fixture.reconciliationCandidates
            .listAll(),
      );
      expect(afterMetadataChange.transactions.map((value) => value.id.value), [
        'confirmed-payment',
      ]);
      expect(
        afterMetadataChange.qualityIssues,
        isNot(
          contains(
            predicate<DataQualityIssue>(
              (issue) => issue.code == 'malformedReconciliationLink',
            ),
          ),
        ),
      );
      expect(await fixture.reconciliationLinks.listAll(), hasLength(1));
      expect(
        (await fixture.reconciliationCandidates.listAll()).single.status,
        ReconciliationCandidateStatus.confirmed,
      );
    },
  );

  test(
    'permanently removing a non-selected member reopens the persisted decision',
    () async {
      final fixture = await PersistedFinancialFixture.create();
      addTearDown(fixture.dispose);
      final selected = _transaction('selected', '10');
      final removed = _transaction('removed', '10');
      final survivor = _transaction('survivor', '10');
      for (final value in [selected, removed, survivor]) {
        await fixture.saveTransaction(value);
      }
      await fixture.saveDuplicateGroup(
        _group(
          'decision',
          [selected.id, removed.id, survivor.id],
          key: _key('10'),
          status: DuplicateCandidateGroupStatus.consolidated,
          selected: selected.id,
        ),
      );

      await fixture.transactions.removePermanently(removed.id);
      await fixture.reopen();

      final group = (await fixture.duplicateGroups.list()).single;
      expect(group.transactionIds, [selected.id, survivor.id]);
      expect(group.status, DuplicateCandidateGroupStatus.unresolved);
      expect(group.selectedTransactionId, isNull);
      expect(
        (await fixture.transactions.listAll()).map((value) => value.id.value),
        ['selected', 'survivor'],
      );
      expect(
        (await fixture.transactions.listAll()).every(
          (value) => value.provenance.isNotEmpty,
        ),
        isTrue,
      );
    },
  );
}

DuplicateCandidateGroup _group(
  String id,
  List<TransactionId> ids, {
  required DuplicateTransactionKey key,
  required DuplicateCandidateGroupStatus status,
  TransactionId? selected,
}) => DuplicateCandidateGroup(
  id: id,
  transactionIds: ids,
  duplicateKey: key,
  status: status,
  selectedTransactionId: selected,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

DuplicateTransactionKey _key(String amount) => DuplicateTransactionKey(
  transactionDate: '2026-09-01',
  amount: DecimalValue.parse(amount),
  currency: 'USD',
  direction: TransactionDirection.expense.name,
);

Transaction _transaction(
  String id,
  String amount, {
  String date = '2026-09-01',
  String currency = 'USD',
  TransactionDirection direction = TransactionDirection.expense,
  TransactionSourceType sourceType = TransactionSourceType.manual,
}) {
  final at = DateTime.utc(2026, 9, 1);
  return Transaction(
    id: TransactionId(id),
    timing: const UnknownTransactionTime(UnknownTransactionTimeReason.unknown),
    money: Money(
      amount: DecimalValue.parse(amount),
      currency: CurrencyCode(currency),
    ),
    direction: direction,
    sourceType: sourceType,
    transactionDate: date,
    provenance: [
      Provenance(
        id: ProvenanceId('$id-provenance'),
        sourceType: ProvenanceSourceType.userEntry,
        capturedAt: at,
        originalRepresentation: id,
      ),
    ],
    createdAt: at,
    updatedAt: at,
  );
}

Transaction _copy(
  Transaction value, {
  String? amount,
  String? date,
  String? currency,
  TransactionDirection? direction,
}) => Transaction(
  id: value.id,
  timing: value.timing,
  money: Money(
    amount: DecimalValue.parse(amount ?? value.money.amount.toString()),
    currency: CurrencyCode(currency ?? value.money.currency.value),
  ),
  direction: direction ?? value.direction,
  sourceType: value.sourceType,
  transactionDate: date ?? value.transactionDate,
  status: value.status,
  provenance: value.provenance,
  createdAt: value.createdAt,
  updatedAt: DateTime.utc(2026, 9, 2),
);

final class _Clock implements ApplicationClock {
  const _Clock(this.value);
  final DateTime value;

  @override
  DateTime now() => value;
}
