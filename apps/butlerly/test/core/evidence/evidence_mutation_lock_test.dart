import 'dart:async';

import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('queued evidence mutations retain their caller zone', () async {
    final releaseFirst = Completer<void>();
    final firstEntered = Completer<void>();
    final first = EvidenceMutationLock.runExclusive(() async {
      firstEntered.complete();
      await releaseFirst.future;
    });
    await firstEntered.future;

    final owner = Object();
    final queued = runZoned(
      () => EvidenceMutationLock.runExclusive(() async {
        expect(Zone.current[#evidenceOwner], same(owner));
        return 7;
      }),
      zoneValues: {#evidenceOwner: owner},
    );

    releaseFirst.complete();
    await first;
    expect(await queued.timeout(const Duration(seconds: 5)), 7);
  });

  test('queued evidence mutation preserves the analysis gate owner', () async {
    final releaseFirst = Completer<void>();
    final firstEntered = Completer<void>();
    final first = EvidenceMutationLock.runExclusive(() async {
      firstEntered.complete();
      await releaseFirst.future;
    });
    await firstEntered.future;

    final consistencyGate = AnalysisConsistencyGate();
    final queued = consistencyGate.runExclusive(
      () => EvidenceMutationLock.runExclusive(() async {
        // A queued mutation must not lose the calling analysis gate's zone.
        // If it does, this nested operation queues behind itself forever.
        return consistencyGate.runExclusive(() async => 42);
      }),
    );

    releaseFirst.complete();
    await first;
    expect(await queued.timeout(const Duration(seconds: 5)), 42);
  });
}
