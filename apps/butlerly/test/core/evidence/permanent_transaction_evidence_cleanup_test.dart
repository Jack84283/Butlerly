import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Directory root;
  late Directory evidenceDirectory;
  late LocalDatabase database;

  setUp(() async {
    await services.reset();
    root = await Directory.systemTemp.createTemp(
      'butlerly-permanent-evidence-',
    );
    evidenceDirectory = Directory(path.join(root.path, 'evidence'));
    database = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: root.path,
    );
    await database.initialize();
    configureDependencies(
      configuration: const AppConfiguration(),
      database: database,
      logger: AppLogger(),
      documentsDirectory: Directory(path.join(root.path, 'documents')),
      localEvidenceDirectory: evidenceDirectory,
    );
  });

  tearDown(() async {
    await services.reset();
    await database.close();
    await root.delete(recursive: true);
  });

  test(
    'permanent delete removes exclusive files and preserves shared files',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final first = _transaction('transaction-evidence-owner', now);
      final second = _transaction('transaction-evidence-shared', now);
      final transactions = SqliteTransactionRepository(
        database.persistenceDatabase,
      );
      final evidence = SqliteEvidenceRepository(database.persistenceDatabase);
      await transactions.save(first);
      await transactions.save(second);

      final exclusive = _evidence('evidence-exclusive', now);
      final shared = _evidence('evidence-shared', now);
      await evidence.save(exclusive);
      await evidence.save(shared);
      await evidence.link(
        AttachmentLink(
          id: AttachmentLinkId('attachment-exclusive'),
          transactionId: first.id,
          evidenceId: exclusive.id,
          createdAt: now,
        ),
      );
      await evidence.link(
        AttachmentLink(
          id: AttachmentLinkId('attachment-shared-first'),
          transactionId: first.id,
          evidenceId: shared.id,
          createdAt: now,
        ),
      );
      await evidence.link(
        AttachmentLink(
          id: AttachmentLinkId('attachment-shared-second'),
          transactionId: second.id,
          evidenceId: shared.id,
          createdAt: now,
        ),
      );
      await evidenceDirectory.create(recursive: true);
      final exclusiveFile = File(
        path.join(evidenceDirectory.path, exclusive.localFileName!),
      );
      final sharedFile = File(
        path.join(evidenceDirectory.path, shared.localFileName!),
      );
      await exclusiveFile.writeAsBytes([1, 2, 3], flush: true);
      await sharedFile.writeAsBytes([4, 5, 6], flush: true);

      final unlinkResult = await services<LocalEvidenceStore>()
          .removeEvidenceFromTransaction(first.id.value, shared.id.value);
      expect(unlinkResult, isA<ApplicationSuccess<bool>>());
      expect((unlinkResult as ApplicationSuccess<bool>).value, isTrue);
      expect(await sharedFile.exists(), isTrue);
      expect(await evidence.findById(shared.id), isNotNull);
      expect(
        (await evidence.listForTransaction(second.id)).single.id,
        shared.id,
      );

      final result = await services<FinanceServices>()
          .deleteTransactionPermanently(first.id.value);

      expect(result, isA<ApplicationSuccess<void>>());
      expect(await exclusiveFile.exists(), isFalse);
      expect(await sharedFile.exists(), isTrue);
      expect(await evidence.findById(exclusive.id), isNull);
      expect(await evidence.findById(shared.id), isNotNull);
      expect(await transactions.findById(first.id), isNull);
      expect(await transactions.findById(second.id), isNotNull);
    },
  );

  test(
    'startup cleanup retains a capture interrupted before specific journaling',
    () async {
      final sourceFile = File(path.join(root.path, 'abandoned-capture.pdf'));
      await sourceFile.writeAsBytes([8, 6, 7, 5], flush: true);
      final store = services<LocalEvidenceStore>();

      final preserved = await store.preserve(
        XFile(sourceFile.path, name: 'abandoned-capture.pdf'),
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      final pendingFile = File(
        path.join(pending.path, preserved.localFileName),
      );
      final genericJournal = File(
        path.join(pending.path, 'capture-${preserved.localFileName}.json'),
      );
      expect(await pendingFile.exists(), isTrue);
      expect(await genericJournal.exists(), isTrue);

      expect(await store.recoverUnclaimedPendingCaptures(), 0);
      expect(await pendingFile.exists(), isTrue);
      expect(await genericJournal.exists(), isTrue);
    },
  );

  test('incomplete generic capture is never offered for import', () async {
    final pending = Directory('${evidenceDirectory.path}.pending');
    await pending.create(recursive: true);
    const localFileName = 'interrupted-source.pdf';
    await File(
      path.join(pending.path, localFileName),
    ).writeAsBytes([1], flush: true);
    final journal = File(
      path.join(pending.path, 'capture-$localFileName.json'),
    );
    await journal.writeAsString(
      jsonEncode({
        'localFileName': localFileName,
        'originalName': localFileName,
        'mediaType': 'application/pdf',
        'captureKind': 'statement',
        'captureState': 'copying',
      }),
      flush: true,
    );

    final store = services<LocalEvidenceStore>();
    expect(
      await store.listPendingGenericCaptures(captureKind: 'statement'),
      isEmpty,
    );
    final issues = await store.listPendingCaptureJournalIssues();
    expect(
      issues.map((issue) => issue.fileName),
      contains(path.basename(journal.path)),
    );
    expect(issues.single.messageKey, 'captureRecoverySourceUnavailable');
    expect(await File(path.join(pending.path, localFileName)).exists(), isTrue);
  });

  test(
    'legacy unjournaled pending evidence is materialized and survives restart',
    () async {
      final pending = Directory('${evidenceDirectory.path}.pending');
      await pending.create(recursive: true);
      const localFileName = 'evidence-0123456789abcdef0123456789abcdef.pdf';
      final pendingFile = File(path.join(pending.path, localFileName));
      await pendingFile.writeAsBytes([3, 1, 4, 1, 5], flush: true);
      final store = services<LocalEvidenceStore>();

      final recovered = await store.listPendingGenericCaptures();
      expect(recovered, hasLength(1));
      expect(recovered.single.source.localFileName, localFileName);
      expect(recovered.single.captureKind, isNull);
      expect(
        await store.listPendingGenericCaptures(captureKind: 'statement'),
        isEmpty,
      );
      final manifest = File(
        path.join(pending.path, 'capture-$localFileName.json'),
      );
      expect(await manifest.exists(), isTrue);

      await database.close();
      await services.reset();
      await database.initialize();
      configureDependencies(
        configuration: const AppConfiguration(),
        database: database,
        logger: AppLogger(),
        documentsDirectory: Directory(path.join(root.path, 'documents')),
        localEvidenceDirectory: evidenceDirectory,
      );
      final afterRestart = services<LocalEvidenceStore>();
      final persisted = await afterRestart.listPendingGenericCaptures();
      expect(persisted, hasLength(1));
      expect(
        await afterRestart.discardPendingGenericCapture(
          persisted.single.source,
        ),
        isTrue,
      );
      expect(await pendingFile.exists(), isFalse);
      expect(await manifest.exists(), isFalse);
    },
  );

  test('staged evidence recovery export preserves source bytes', () async {
    final deleting = Directory('${evidenceDirectory.path}.deleting');
    await deleting.create(recursive: true);
    final staged = File(path.join(deleting.path, 'delete-orphan.bin'));
    await staged.writeAsBytes([9, 8, 7, 6], flush: true);
    final manifest = File('${staged.path}.json');
    await manifest.writeAsString(
      jsonEncode({'evidenceId': 'missing', 'stagedFileName': staged.path}),
      flush: true,
    );

    final exported = await services<LocalEvidenceStore>()
        .exportStagedEvidenceRecovery();
    expect(await staged.readAsBytes(), [9, 8, 7, 6]);
    expect(
      await File(
        path.join(exported.path, 'staged', 'delete-orphan.bin'),
      ).readAsBytes(),
      [9, 8, 7, 6],
    );
    final exportedManifest =
        jsonDecode(
              await File(
                path.join(exported.path, 'recovery-manifest.json'),
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(exportedManifest['format'], 'butlerly-staged-evidence-recovery');
    expect(exportedManifest['files'], hasLength(2));
  });

  test(
    'partial preserved integrity metadata fails closed before publication',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final transaction = _transaction('transaction-partial-integrity', now);
      await SqliteTransactionRepository(
        database.persistenceDatabase,
      ).save(transaction);
      final pending = Directory('${evidenceDirectory.path}.pending');
      await pending.create(recursive: true);
      const localFileName = 'partial-integrity.pdf';
      final pendingFile = File(path.join(pending.path, localFileName));
      await pendingFile.writeAsBytes([2, 7, 1, 8], flush: true);
      final fingerprint = await sha256FileRange(pendingFile);
      final source = PreservedEvidenceSource(
        originalName: localFileName,
        localFileName: localFileName,
        mediaType: 'application/pdf',
        byteLength: null,
        sourceFingerprint: fingerprint,
      );
      final store = services<LocalEvidenceStore>();

      expect(await store.fileForPreserved(source), isNull);
      expect(
        await store.attachPreservedAndReturn(
          transactionId: transaction.id.value,
          source: source,
        ),
        isNull,
      );
      expect(await pendingFile.exists(), isTrue);
      expect(
        await File(path.join(evidenceDirectory.path, localFileName)).exists(),
        isFalse,
      );
    },
  );

  test(
    'malformed unrelated capture journal blocks cleanup explicitly',
    () async {
      final sourceFile = File(path.join(root.path, 'uncertain-capture.pdf'));
      await sourceFile.writeAsBytes([4, 5, 6], flush: true);
      final store = services<LocalEvidenceStore>();
      final preserved = await store.preserve(
        XFile(sourceFile.path, name: 'uncertain-capture.pdf'),
      );
      final unrelatedSourceFile = File(
        path.join(root.path, 'unrelated-capture.pdf'),
      );
      await unrelatedSourceFile.writeAsBytes([9, 9, 9], flush: true);
      final unrelated = await store.preserve(
        XFile(unrelatedSourceFile.path, name: 'unrelated-capture.pdf'),
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      final malformed = File(path.join(pending.path, 'receipt-unrelated.json'));
      await malformed.writeAsString('{not-json', flush: true);
      final malformedWithSource = File(
        path.join(pending.path, 'receipt-partial.json'),
      );
      await malformedWithSource.writeAsString(
        jsonEncode({'localFileName': preserved.localFileName}),
        flush: true,
      );

      await expectLater(
        store.recoverUnclaimedPendingCaptures(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('receipt-'),
          ),
        ),
      );
      expect(
        await File(path.join(pending.path, preserved.localFileName)).exists(),
        isTrue,
      );
      expect(
        await File(
          path.join(pending.path, 'capture-${preserved.localFileName}.json'),
        ).exists(),
        isTrue,
      );
      expect(await malformed.exists(), isTrue);
      expect(await malformedWithSource.exists(), isTrue);
      expect(await store.discardPendingGenericCapture(preserved), isFalse);
      expect(
        await File(path.join(pending.path, preserved.localFileName)).exists(),
        isTrue,
      );
      expect(
        await File(
          path.join(pending.path, 'capture-${preserved.localFileName}.json'),
        ).exists(),
        isTrue,
      );
      final visible = await store.listPendingGenericCaptures();
      expect(visible, hasLength(2));
      expect(
        visible.map((capture) => capture.source.localFileName),
        containsAll([preserved.localFileName, unrelated.localFileName]),
      );
      final issues = await store.listPendingCaptureJournalIssues();
      expect(issues, hasLength(2));
      expect(
        issues.map((issue) => issue.fileName),
        containsAll(['receipt-partial.json', 'receipt-unrelated.json']),
      );
      expect(issues.every((issue) => issue.messageKey.isNotEmpty), isTrue);
      expect(
        await store.resolvePendingCaptureJournalIssue('receipt-partial.json'),
        PendingCaptureJournalResolution.repaired,
      );
      expect(await malformedWithSource.exists(), isFalse);
      expect(
        (await store.listPendingGenericCaptures(
          captureKind: 'receipt',
        )).map((capture) => capture.source.localFileName),
        contains(preserved.localFileName),
      );
      expect(
        await store.dismissPendingCaptureJournalIssue('receipt-unrelated.json'),
        PendingCaptureJournalResolution.dismissed,
      );
      expect(await malformed.exists(), isFalse);
      expect(
        await File(path.join(pending.path, unrelated.localFileName)).exists(),
        isTrue,
      );
    },
  );

  test(
    'repairing a malformed generic journal keeps the source listable',
    () async {
      final sourceFile = File(path.join(root.path, 'generic-repair.pdf'));
      await sourceFile.writeAsBytes([2, 4, 6, 8], flush: true);
      final store = services<LocalEvidenceStore>();
      final source = await store.preserve(
        XFile(sourceFile.path, name: 'generic-repair.pdf'),
        captureKind: 'statement',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      final journal = File(
        path.join(pending.path, 'capture-${source.localFileName}.json'),
      );
      await journal.writeAsString('{not-json', flush: true);

      expect(
        (await store.listPendingCaptureJournalIssues()).map(
          (issue) => issue.fileName,
        ),
        contains(path.basename(journal.path)),
      );
      expect(
        await store.resolvePendingCaptureJournalIssue(
          path.basename(journal.path),
          captureKind: 'statement',
        ),
        PendingCaptureJournalResolution.repaired,
      );
      expect(await journal.exists(), isTrue);
      expect(
        (await store.listPendingGenericCaptures(
          captureKind: 'statement',
        )).single.source.localFileName,
        source.localFileName,
      );

      await database.close();
      await services.reset();
      await database.initialize();
      configureDependencies(
        configuration: const AppConfiguration(),
        database: database,
        logger: AppLogger(),
        documentsDirectory: Directory(path.join(root.path, 'documents')),
        localEvidenceDirectory: evidenceDirectory,
      );
      expect(
        (await services<LocalEvidenceStore>().listPendingGenericCaptures(
          captureKind: 'statement',
        )).single.source.localFileName,
        source.localFileName,
      );
    },
  );

  test(
    'repairing a torn generic journal promotes its complete temporary source',
    () async {
      final sourceFile = File(path.join(root.path, 'torn-repair.pdf'));
      await sourceFile.writeAsBytes([9, 7, 5, 3], flush: true);
      final store = services<LocalEvidenceStore>();
      final source = await store.preserve(
        XFile(sourceFile.path, name: 'torn-repair.pdf'),
        captureKind: 'statement',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      final finalSource = File(path.join(pending.path, source.localFileName));
      final temporary = File('${finalSource.path}.tmp');
      final journal = File(
        path.join(pending.path, 'capture-${source.localFileName}.json'),
      );
      final decoded =
          jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
      decoded['captureState'] = 'copying';
      await journal.writeAsString(jsonEncode(decoded), flush: true);
      await finalSource.rename(temporary.path);

      expect(
        await store.resolvePendingCaptureJournalIssue(
          path.basename(journal.path),
          captureKind: 'statement',
        ),
        PendingCaptureJournalResolution.repaired,
      );
      expect(await finalSource.exists(), isTrue);
      expect(await temporary.exists(), isFalse);
      expect(
        (await store.listPendingGenericCaptures(
          captureKind: 'statement',
        )).single.source.localFileName,
        source.localFileName,
      );
    },
  );

  test(
    'partial temporary capture is retained until persisted integrity matches',
    () async {
      final sourceFile = File(path.join(root.path, 'partial-repair.pdf'));
      await sourceFile.writeAsBytes([1, 2, 3, 4], flush: true);
      final store = services<LocalEvidenceStore>();
      final source = await store.preserve(
        XFile(sourceFile.path, name: 'partial-repair.pdf'),
        captureKind: 'statement',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      final finalSource = File(path.join(pending.path, source.localFileName));
      final temporary = File('${finalSource.path}.tmp');
      final journal = File(
        path.join(pending.path, 'capture-${source.localFileName}.json'),
      );
      final decoded =
          jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
      decoded['captureState'] = 'copying';
      await journal.writeAsString(jsonEncode(decoded), flush: true);
      await finalSource.rename(temporary.path);
      await temporary.writeAsBytes([1], flush: true);

      expect(
        await store.resolvePendingCaptureJournalIssue(
          path.basename(journal.path),
          captureKind: 'statement',
        ),
        PendingCaptureJournalResolution.unavailable,
      );
      expect(await temporary.exists(), isTrue);
      expect(await finalSource.exists(), isFalse);
      expect(
        await store.listPendingGenericCaptures(captureKind: 'statement'),
        isEmpty,
      );
      expect(
        (await store.listPendingCaptureJournalIssues()).map(
          (issue) => issue.fileName,
        ),
        contains(path.basename(journal.path)),
      );
    },
  );

  test(
    'JSON capture sources are diagnosed and dismissed only through their journal',
    () async {
      final sourceFile = File(path.join(root.path, 'pending.json'));
      await sourceFile.writeAsBytes([5, 8, 13], flush: true);
      final store = services<LocalEvidenceStore>();
      final source = await store.preserve(
        XFile(sourceFile.path, name: 'pending.json'),
        captureKind: 'statement',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      final journal = File(
        path.join(pending.path, 'capture-${source.localFileName}.json'),
      );
      await journal.writeAsString('{not-json', flush: true);

      final issues = await store.listPendingCaptureJournalIssues();
      expect(
        issues.map((issue) => issue.fileName),
        contains(path.basename(journal.path)),
      );
      expect(
        issues.map((issue) => issue.fileName),
        isNot(contains(source.localFileName)),
      );
      expect(
        await store.dismissPendingCaptureJournalIssue(
          path.basename(journal.path),
          captureKind: 'statement',
        ),
        PendingCaptureJournalResolution.dismissed,
      );
      expect(
        await File(path.join(pending.path, source.localFileName)).exists(),
        isTrue,
      );
      expect(
        (await store.listPendingGenericCaptures(
          captureKind: 'statement',
        )).single.source.localFileName,
        source.localFileName,
      );
      expect(
        await store.dismissPendingCaptureJournalIssue(source.localFileName),
        PendingCaptureJournalResolution.unavailable,
      );
      expect(
        await File(path.join(pending.path, source.localFileName)).exists(),
        isTrue,
      );
    },
  );

  test(
    'generic journal identity mismatch is reported without re-homing a source',
    () async {
      final firstFile = File(path.join(root.path, 'mismatch-first.pdf'));
      final secondFile = File(path.join(root.path, 'mismatch-second.pdf'));
      await firstFile.writeAsBytes([1, 1, 1], flush: true);
      await secondFile.writeAsBytes([2, 2, 2], flush: true);
      final store = services<LocalEvidenceStore>();
      final first = await store.preserve(
        XFile(firstFile.path, name: 'mismatch-first.pdf'),
        captureKind: 'statement',
      );
      final second = await store.preserve(
        XFile(secondFile.path, name: 'mismatch-second.pdf'),
        captureKind: 'statement',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      final journal = File(
        path.join(pending.path, 'capture-${first.localFileName}.json'),
      );
      final decoded =
          jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
      decoded['localFileName'] = second.localFileName;
      await journal.writeAsString(jsonEncode(decoded), flush: true);

      expect(
        (await store.listPendingCaptureJournalIssues()).map(
          (issue) => issue.fileName,
        ),
        contains(path.basename(journal.path)),
      );
      expect(
        await store.resolvePendingCaptureJournalIssue(
          path.basename(journal.path),
          captureKind: 'statement',
        ),
        PendingCaptureJournalResolution.repaired,
      );
      expect(
        (await store.listPendingGenericCaptures(
          captureKind: 'statement',
        )).map((capture) => capture.source.localFileName),
        containsAll([first.localFileName, second.localFileName]),
      );
    },
  );

  test(
    'dismissing a malformed generic journal keeps its source listable',
    () async {
      final sourceFile = File(path.join(root.path, 'dismiss-repair.pdf'));
      await sourceFile.writeAsBytes([4, 4, 4], flush: true);
      final store = services<LocalEvidenceStore>();
      final source = await store.preserve(
        XFile(sourceFile.path, name: 'dismiss-repair.pdf'),
        captureKind: 'statement',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      final journal = File(
        path.join(pending.path, 'capture-${source.localFileName}.json'),
      );
      await journal.writeAsString('{not-json', flush: true);

      expect(
        await store.dismissPendingCaptureJournalIssue(
          path.basename(journal.path),
          captureKind: 'statement',
        ),
        PendingCaptureJournalResolution.dismissed,
      );
      expect(await journal.exists(), isTrue);
      expect(
        (await store.listPendingGenericCaptures(
          captureKind: 'statement',
        )).single.source.localFileName,
        source.localFileName,
      );
    },
  );

  test('malformed receipt completion retains its journal and source', () async {
    final sourceFile = File(path.join(root.path, 'receipt-corrupt.png'));
    await sourceFile.writeAsBytes([7, 8, 9], flush: true);
    final store = services<LocalEvidenceStore>();
    final source = await store.preserve(
      XFile(sourceFile.path, name: 'receipt-corrupt.png'),
    );
    final captureId = 'receipt-corrupt-capture';
    await store.preparePendingReceiptCapture(
      transactionId: captureId,
      source: source,
    );
    final pending = Directory('${evidenceDirectory.path}.pending');
    final manifest = File(path.join(pending.path, 'receipt-$captureId.json'));
    await manifest.writeAsString('{not-json', flush: true);

    expect(await store.completePendingReceiptCapture(captureId), isFalse);
    expect(await manifest.exists(), isTrue);
    expect(
      await File(path.join(pending.path, source.localFileName)).exists(),
      isTrue,
    );
    expect(
      await File(
        path.join(pending.path, 'capture-${source.localFileName}.json'),
      ).exists(),
      isTrue,
    );
  });

  test(
    'valid receipt recovery remains listable when an unrelated journal is malformed',
    () async {
      final sourceFile = File(path.join(root.path, 'receipt-valid.png'));
      await sourceFile.writeAsBytes([2, 4, 8], flush: true);
      final store = services<LocalEvidenceStore>();
      final source = await store.preserve(
        XFile(sourceFile.path, name: 'receipt-valid.png'),
        captureKind: 'receipt',
      );
      await store.preparePendingReceiptCapture(
        transactionId: 'receipt-valid-capture',
        source: source,
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      final malformed = File(path.join(pending.path, 'receipt-malformed.json'));
      await malformed.writeAsString('{not-json', flush: true);

      final captures = await store.listPendingReceiptCaptures();
      expect(captures, hasLength(1));
      expect(captures.single.captureId, 'receipt-valid-capture');
      expect(await store.hasUnresolvedPendingCaptureJournals(), isTrue);
      expect(await malformed.exists(), isTrue);
    },
  );

  test(
    'valid statement recovery proceeds while malformed statement journal remains',
    () async {
      final sourceFile = File(path.join(root.path, 'statement-valid.pdf'));
      await sourceFile.writeAsBytes([3, 5, 7], flush: true);
      final store = services<LocalEvidenceStore>();
      final source = await store.preserve(
        XFile(sourceFile.path, name: 'statement-valid.pdf'),
        captureKind: 'statement',
      );
      await store.preparePendingStatementCapture(
        statementId: 'statement-valid-capture',
        source: source,
        originalFilename: source.originalName,
        createdAt: DateTime.utc(2026, 8, 9, 20),
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      final malformed = File(
        path.join(pending.path, 'statement-malformed.json'),
      );
      await malformed.writeAsString('{not-json', flush: true);

      await expectLater(
        store.recoverPendingStatementCaptures(),
        throwsA(isA<FormatException>()),
      );
      final statements = await services<FinanceServices>().statementServices!
          .list(includeArchived: true);
      expect(
        statements,
        isA<ApplicationSuccess<List<FinancialStatement>>>().having(
          (value) => value.value.map((item) => item.id).toList(),
          'statement ids',
          contains('statement-valid-capture'),
        ),
      );
      expect(await malformed.exists(), isTrue);
      expect(await store.hasUnresolvedPendingCaptureJournals(), isTrue);
    },
  );

  test(
    'generic capture fallback survives restart and explicit discard',
    () async {
      final sourceFile = File(path.join(root.path, 'generic-statement.pdf'));
      await sourceFile.writeAsBytes([1, 3, 5, 7], flush: true);
      final store = services<LocalEvidenceStore>();
      final source = await store.preserve(
        XFile(sourceFile.path, name: 'generic-statement.pdf'),
        captureKind: 'statement',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      final pendingFile = File(path.join(pending.path, source.localFileName));
      final genericJournal = File(
        path.join(pending.path, 'capture-${source.localFileName}.json'),
      );
      expect(await pendingFile.exists(), isTrue);
      expect(await genericJournal.exists(), isTrue);

      await database.close();
      await services.reset();
      await database.initialize();
      configureDependencies(
        configuration: const AppConfiguration(),
        database: database,
        logger: AppLogger(),
        documentsDirectory: Directory(path.join(root.path, 'documents')),
        localEvidenceDirectory: evidenceDirectory,
      );

      final afterRestart = services<LocalEvidenceStore>();
      final recovered = await afterRestart.listPendingGenericCaptures(
        captureKind: 'statement',
      );
      expect(recovered, hasLength(1));
      expect(recovered.single.source.localFileName, source.localFileName);
      expect(recovered.single.source.sourceFingerprint, isNotNull);
      expect(recovered.single.captureKind, 'statement');
      expect(await afterRestart.hasUnresolvedPendingCaptureJournals(), isFalse);

      expect(
        await afterRestart.discardPendingGenericCapture(
          recovered.single.source,
        ),
        isTrue,
      );
      expect(await pendingFile.exists(), isFalse);
      expect(await genericJournal.exists(), isFalse);
    },
  );

  test(
    'receipt publication works inside an already-owned evidence boundary',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final transaction = _transaction('transaction-receipt-boundary', now);
      final transactions = SqliteTransactionRepository(
        database.persistenceDatabase,
      );
      await transactions.save(transaction);
      final source = File(path.join(root.path, 'receipt.png'));
      await source.writeAsBytes([1, 4, 9], flush: true);
      final store = services<LocalEvidenceStore>();
      final preserved = await store.preserve(
        XFile(source.path, name: 'receipt.png', mimeType: 'image/png'),
      );

      final result = await store.runFinancialEvidenceMutation(
        () => store.attachPreservedAndReturnWithinMutation(
          transactionId: transaction.id.value,
          source: preserved,
        ),
      );
      expect(result, isA<EvidenceItem>());
      final evidence = result as EvidenceItem;
      final published = await store.fileFor(evidence);
      expect(published, isNotNull);
      expect(await published!.readAsBytes(), [1, 4, 9]);

      final deleted = await store.deleteTransactionPermanently(
        transaction.id.value,
      );
      expect(deleted, isA<ApplicationSuccess<void>>());
      expect(await published.exists(), isFalse);
    },
  );

  test(
    'startup recovery removes evidence orphaned by an interrupted delete',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final transaction = _transaction('transaction-interrupted-delete', now);
      final transactions = SqliteTransactionRepository(
        database.persistenceDatabase,
      );
      final evidence = SqliteEvidenceRepository(database.persistenceDatabase);
      final item = _evidence('evidence-interrupted-delete', now);
      await transactions.save(transaction);
      await evidence.save(item);
      await evidence.link(
        AttachmentLink(
          id: AttachmentLinkId('attachment-interrupted-delete'),
          transactionId: transaction.id,
          evidenceId: item.id,
          createdAt: now,
        ),
      );
      await evidenceDirectory.create(recursive: true);
      final file = File(path.join(evidenceDirectory.path, item.localFileName!));
      await file.writeAsBytes([9, 8, 7], flush: true);

      // Model a process ending after the source transaction commit and before
      // the reference-aware evidence cleanup phase.
      await transactions.removePermanently(transaction.id);
      expect(await evidence.findById(item.id), isNotNull);

      await database.close();
      await services.reset();
      await database.initialize();
      configureDependencies(
        configuration: const AppConfiguration(),
        database: database,
        logger: AppLogger(),
        localEvidenceDirectory: evidenceDirectory,
      );

      final repaired = await services<LocalEvidenceStore>()
          .recoverUnreferencedEvidence();
      expect(repaired, 1);
      expect(await file.exists(), isFalse);
      expect(
        await SqliteEvidenceRepository(
          database.persistenceDatabase,
        ).findById(item.id),
        isNull,
      );
    },
  );

  test('staged deletion recovery surfaces an unjournaled binary', () async {
    final deleting = Directory('${evidenceDirectory.path}.deleting');
    await deleting.create(recursive: true);
    final orphan = File(path.join(deleting.path, 'delete-no-manifest.bin'));
    await orphan.writeAsBytes([1, 2, 3], flush: true);

    final store = services<LocalEvidenceStore>();
    await expectLater(
      store.recoverStagedEvidenceDeletions(),
      throwsA(isA<StateError>()),
    );
    expect(await orphan.exists(), isTrue);
  });

  test('database cleanup failure leaves staged evidence recoverable', () async {
    final now = DateTime.utc(2026, 8, 9, 20);
    final transaction = _transaction('transaction-db-cleanup-failure', now);
    final transactions = SqliteTransactionRepository(
      database.persistenceDatabase,
    );
    final evidence = SqliteEvidenceRepository(database.persistenceDatabase);
    final item = _evidence('evidence-db-cleanup-failure', now);
    await transactions.save(transaction);
    await evidence.save(item);
    await evidence.link(
      AttachmentLink(
        id: AttachmentLinkId('attachment-db-cleanup-failure'),
        transactionId: transaction.id,
        evidenceId: item.id,
        createdAt: now,
      ),
    );
    await evidenceDirectory.create(recursive: true);
    final file = File(path.join(evidenceDirectory.path, item.localFileName!));
    await file.writeAsBytes([2, 4, 6], flush: true);
    await database.persistenceDatabase.connection.execute(
      'CREATE TRIGGER fail_evidence_delete '
      'BEFORE DELETE ON evidence_items '
      "BEGIN SELECT RAISE(ABORT, 'forced evidence delete failure'); END",
    );

    final result = await services<FinanceServices>()
        .deleteTransactionPermanently(transaction.id.value);
    expect(result, isA<ApplicationFailure<void>>());
    expect(await file.exists(), isFalse);

    await database.persistenceDatabase.connection.execute(
      'DROP TRIGGER fail_evidence_delete',
    );
    await services<LocalEvidenceStore>().recoverStagedEvidenceDeletions();

    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), [2, 4, 6]);
    expect(await evidence.findById(item.id), isNotNull);
  });

  test(
    'startup recovery completes an interrupted receipt evidence attachment',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final transaction = _transaction('transaction-receipt-recovery', now);
      final transactions = SqliteTransactionRepository(
        database.persistenceDatabase,
      );
      await transactions.save(transaction);
      final store = services<LocalEvidenceStore>();
      final source = const PreservedEvidenceSource(
        originalName: 'receipt-recovery.png',
        localFileName: 'receipt-recovery.png',
        mediaType: 'image/png',
        sourceFingerprint: 'fingerprint-recovery',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      await pending.create(recursive: true);
      await File(
        path.join(pending.path, source.localFileName),
      ).writeAsBytes([7, 8, 9], flush: true);

      await store.preparePendingReceiptCapture(
        transactionId: transaction.id.value,
        source: source,
      );

      final recovered = await store.recoverPendingReceiptCaptures();
      expect(recovered, 1);
      final attached = await SqliteEvidenceRepository(
        database.persistenceDatabase,
      ).listForTransaction(transaction.id);
      expect(attached, hasLength(1));
      final published = await store.fileFor(attached.single);
      expect(published, isNotNull);
      expect(await published!.readAsBytes(), [7, 8, 9]);
    },
  );

  test(
    'receipt recovery retains a journal when its source checksum is corrupted',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final transaction = _transaction('transaction-receipt-corrupt', now);
      await SqliteTransactionRepository(
        database.persistenceDatabase,
      ).save(transaction);
      final store = services<LocalEvidenceStore>();
      const source = PreservedEvidenceSource(
        originalName: 'receipt-corrupt.png',
        localFileName: 'receipt-corrupt.png',
        mediaType: 'image/png',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      await pending.create(recursive: true);
      final pendingFile = File(path.join(pending.path, source.localFileName));
      await pendingFile.writeAsBytes([7, 8, 9], flush: true);
      await store.preparePendingReceiptCapture(
        transactionId: transaction.id.value,
        source: source,
      );
      await pendingFile.writeAsBytes([0], flush: true);

      await expectLater(
        store.recoverPendingReceiptCaptures(),
        throwsA(isA<StateError>()),
      );
      expect(await pendingFile.readAsBytes(), [0]);
      expect(
        await File(
          path.join(pending.path, 'receipt-${transaction.id.value}.json'),
        ).exists(),
        isTrue,
      );
      expect(
        await SqliteEvidenceRepository(
          database.persistenceDatabase,
        ).listForTransaction(transaction.id),
        isEmpty,
      );
    },
  );

  test('tampered receipt recovery is not resumable or listable', () async {
    final store = services<LocalEvidenceStore>();
    final sourceFile = File(path.join(root.path, 'receipt-tampered.png'));
    await sourceFile.writeAsBytes([7, 8, 9], flush: true);
    final source = await store.preserve(
      XFile(sourceFile.path, name: 'receipt-tampered.png'),
      captureKind: 'receipt',
    );
    await store.preparePendingReceiptCapture(
      transactionId: 'transaction-tampered-receipt',
      source: source,
    );
    final pendingFile = File(
      path.join('${evidenceDirectory.path}.pending', source.localFileName),
    );
    await pendingFile.writeAsBytes([0], flush: true);

    expect(await store.fileForPreserved(source), isNull);
    expect(await store.listPendingReceiptCaptures(), isEmpty);
    final issues = await store.listPendingCaptureJournalIssues();
    expect(
      issues.map((issue) => issue.fileName),
      contains('receipt-transaction-tampered-receipt.json'),
    );
    await expectLater(
      store.recoverPendingReceiptCaptures(),
      throwsA(isA<StateError>()),
    );
    expect(await pendingFile.exists(), isTrue);
    expect(
      await File(
        path.join(
          '${evidenceDirectory.path}.pending',
          'receipt-transaction-tampered-receipt.json',
        ),
      ).exists(),
      isTrue,
    );
  });

  test(
    'receipt recovery does not duplicate an attachment committed before cleanup',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final transaction = _transaction('transaction-receipt-duplicate', now);
      final transactions = SqliteTransactionRepository(
        database.persistenceDatabase,
      );
      await transactions.save(transaction);
      final store = services<LocalEvidenceStore>();
      final pending = Directory('${evidenceDirectory.path}.pending');
      await pending.create(recursive: true);
      final sourceFile = File(path.join(pending.path, 'receipt-duplicate.png'));
      await sourceFile.writeAsBytes([3, 3, 3], flush: true);
      final source = PreservedEvidenceSource(
        originalName: 'receipt-duplicate.png',
        localFileName: 'receipt-duplicate.png',
        mediaType: 'image/png',
        byteLength: await sourceFile.length(),
        sourceFingerprint: await sha256FileRange(sourceFile),
      );
      const captureId = 'transaction-receipt-capture';
      final planned = await store.preparePendingReceiptCapture(
        transactionId: captureId,
        source: source,
      );
      expect(
        await store.rebindPendingReceiptCapture(
          captureId: captureId,
          transactionId: transaction.id.value,
        ),
        isTrue,
      );
      final attached = await store.runFinancialEvidenceMutation(
        () => store.attachPreservedAndReturnWithinMutation(
          transactionId: transaction.id.value,
          source: source,
          planned: planned,
        ),
      );
      expect(attached, isNotNull);

      // Model a stop before the normal manifest completion. The planned ID is
      // explicitly reused by the production mutation path.
      final existing = await SqliteEvidenceRepository(
        database.persistenceDatabase,
      ).listForTransaction(transaction.id);
      expect(existing.single.id, planned.id);
      final retried = await store.runFinancialEvidenceMutation(
        () => store.attachPreservedAndReturnWithinMutation(
          transactionId: transaction.id.value,
          source: source,
          planned: planned,
        ),
      );
      expect(retried?.id, planned.id);
      expect(
        await SqliteEvidenceRepository(
          database.persistenceDatabase,
        ).listForTransaction(transaction.id),
        hasLength(1),
      );
      final recovered = await store.recoverPendingReceiptCaptures();
      expect(recovered, 1);
      final after = await SqliteEvidenceRepository(
        database.persistenceDatabase,
      ).listForTransaction(transaction.id);
      expect(after, hasLength(1));
      expect(
        await File(path.join(pending.path, 'receipt-$captureId.json')).exists(),
        isFalse,
      );
    },
  );

  test(
    'receipt attachment retries a source already promoted to live storage',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final transaction = _transaction('transaction-live-retry', now);
      await SqliteTransactionRepository(
        database.persistenceDatabase,
      ).save(transaction);
      final sourceFile = File(path.join(root.path, 'receipt-live-retry.png'));
      await sourceFile.writeAsBytes([1, 7, 4], flush: true);
      final store = services<LocalEvidenceStore>();
      final source = await store.preserve(
        XFile(sourceFile.path, name: 'receipt-live-retry.png'),
        captureKind: 'receipt',
      );
      const captureId = 'receipt-live-retry-capture';
      final planned = await store.preparePendingReceiptCapture(
        transactionId: captureId,
        source: source,
      );
      expect(
        await store.rebindPendingReceiptCapture(
          captureId: captureId,
          transactionId: transaction.id.value,
        ),
        isTrue,
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      final pendingFile = File(path.join(pending.path, source.localFileName));
      final liveFile = File(
        path.join(evidenceDirectory.path, source.localFileName),
      );
      await evidenceDirectory.create(recursive: true);
      await pendingFile.rename(liveFile.path);

      final attached = await store.runFinancialEvidenceMutation(
        () => store.attachPreservedAndReturnWithinMutation(
          transactionId: transaction.id.value,
          source: source,
          planned: planned,
        ),
      );
      expect(attached, isNotNull);
      expect(await liveFile.exists(), isTrue);
      expect(await store.completePendingReceiptCapture(captureId), isTrue);
      expect(
        await SqliteEvidenceRepository(
          database.persistenceDatabase,
        ).listForTransaction(transaction.id),
        hasLength(1),
      );
    },
  );

  test(
    'committed receipt recovery retains its journal when the source is missing',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final transaction = _transaction('transaction-receipt-missing', now);
      await SqliteTransactionRepository(
        database.persistenceDatabase,
      ).save(transaction);
      final store = services<LocalEvidenceStore>();
      final pending = Directory('${evidenceDirectory.path}.pending');
      await pending.create(recursive: true);
      final sourceFile = File(path.join(pending.path, 'receipt-missing.png'));
      await sourceFile.writeAsBytes([6, 6, 6], flush: true);
      final source = PreservedEvidenceSource(
        originalName: 'receipt-missing.png',
        localFileName: 'receipt-missing.png',
        mediaType: 'image/png',
        byteLength: await sourceFile.length(),
        sourceFingerprint: await sha256FileRange(sourceFile),
      );
      const captureId = 'receipt-missing-capture';
      final planned = await store.preparePendingReceiptCapture(
        transactionId: captureId,
        source: source,
      );
      expect(
        await store.rebindPendingReceiptCapture(
          captureId: captureId,
          transactionId: transaction.id.value,
        ),
        isTrue,
      );
      final attached = await store.runFinancialEvidenceMutation(
        () => store.attachPreservedAndReturnWithinMutation(
          transactionId: transaction.id.value,
          source: source,
          planned: planned,
        ),
      );
      expect(attached, isNotNull);
      final live = await store.fileFor(attached!);
      expect(live, isNotNull);
      await live!.delete();

      await expectLater(
        store.recoverPendingReceiptCaptures(),
        throwsA(isA<StateError>()),
      );
      expect(
        await File(path.join(pending.path, 'receipt-$captureId.json')).exists(),
        isTrue,
      );
      expect(
        await SqliteEvidenceRepository(
          database.persistenceDatabase,
        ).listForTransaction(transaction.id),
        hasLength(1),
      );
    },
  );

  test(
    'receipt recovery rejects traversal paths and preserves the journal',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final transaction = _transaction('transaction-receipt-traversal', now);
      await SqliteTransactionRepository(
        database.persistenceDatabase,
      ).save(transaction);
      final store = services<LocalEvidenceStore>();
      final source = const PreservedEvidenceSource(
        originalName: 'receipt-traversal.png',
        localFileName: 'receipt-traversal.png',
        mediaType: 'image/png',
        sourceFingerprint: 'fingerprint-traversal',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      await pending.create(recursive: true);
      await File(
        path.join(pending.path, source.localFileName),
      ).writeAsBytes([5, 4, 3], flush: true);
      await store.preparePendingReceiptCapture(
        transactionId: transaction.id.value,
        source: source,
      );
      final manifest = File(
        path.join(pending.path, 'receipt-${transaction.id.value}.json'),
      );
      final prepared =
          jsonDecode(
                await File(
                  path.join(
                    pending.path,
                    'receipt-${transaction.id.value}.json',
                  ),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      prepared['localFileName'] = '../outside-receipt.png';
      await manifest.writeAsString(jsonEncode(prepared), flush: true);
      final outside = File(path.join(root.path, 'outside-receipt.png'));
      await outside.writeAsBytes([9, 9, 9], flush: true);

      await expectLater(
        store.recoverPendingReceiptCaptures(),
        throwsA(isA<FormatException>()),
      );
      expect(await outside.readAsBytes(), [9, 9, 9]);
      expect(await manifest.exists(), isTrue);
      expect(
        await SqliteEvidenceRepository(
          database.persistenceDatabase,
        ).listForTransaction(transaction.id),
        isEmpty,
      );
    },
  );

  test(
    'receipt recovery retains an uncommitted source across SQLite restart',
    () async {
      final store = services<LocalEvidenceStore>();
      final source = const PreservedEvidenceSource(
        originalName: 'receipt-deleted.png',
        localFileName: 'receipt-deleted.png',
        mediaType: 'image/png',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      await pending.create(recursive: true);
      final pendingFile = File(path.join(pending.path, source.localFileName));
      await pendingFile.writeAsBytes([1, 1, 1], flush: true);
      await store.preparePendingReceiptCapture(
        transactionId: 'transaction-already-deleted',
        source: source,
      );

      await database.close();
      await services.reset();
      await database.initialize();
      configureDependencies(
        configuration: const AppConfiguration(),
        database: database,
        logger: AppLogger(),
        documentsDirectory: Directory(path.join(root.path, 'documents')),
        localEvidenceDirectory: evidenceDirectory,
      );

      final afterRestart = services<LocalEvidenceStore>();
      expect(await afterRestart.recoverPendingReceiptCaptures(), 0);
      expect(await pendingFile.exists(), isTrue);
      expect(
        await File(
          path.join(pending.path, 'receipt-transaction-already-deleted.json'),
        ).readAsString().then((value) => jsonDecode(value)['captureState']),
        'awaitingTransaction',
      );
      final pendingCaptures = await afterRestart.listPendingReceiptCaptures();
      expect(pendingCaptures, hasLength(1));
      expect(pendingCaptures.single.captureId, 'transaction-already-deleted');
      expect(pendingCaptures.single.source.localFileName, source.localFileName);
      expect(
        await afterRestart.cancelPendingReceiptCapture(
          'transaction-already-deleted',
        ),
        isTrue,
      );
      expect(await pendingFile.exists(), isFalse);
      expect(
        await File(
          path.join(pending.path, 'receipt-transaction-already-deleted.json'),
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'post-commit receipt attachment failure retains recovery across restart',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final transaction = _transaction('transaction-post-commit', now);
      final transactions = SqliteTransactionRepository(
        database.persistenceDatabase,
      );
      await transactions.save(transaction);
      final sourceFile = File(path.join(root.path, 'receipt-post-commit.png'));
      await sourceFile.writeAsBytes([4, 6, 8], flush: true);
      final store = services<LocalEvidenceStore>();
      final source = await store.preserve(
        XFile(sourceFile.path, name: sourceFile.uri.pathSegments.last),
        captureKind: 'receipt',
      );
      const captureId = 'receipt-post-commit-capture';
      await store.preparePendingReceiptCapture(
        transactionId: captureId,
        source: source,
      );
      expect(
        await store.markPendingReceiptCaptureTransactionCommitted(
          captureId: captureId,
          transactionId: transaction.id.value,
        ),
        isTrue,
      );

      await database.close();
      await services.reset();
      await database.initialize();
      configureDependencies(
        configuration: const AppConfiguration(),
        database: database,
        logger: AppLogger(),
        documentsDirectory: Directory(path.join(root.path, 'documents')),
        localEvidenceDirectory: evidenceDirectory,
      );
      await database.persistenceDatabase.connection.execute(
        '''CREATE TRIGGER fail_post_commit_receipt_attach
           BEFORE INSERT ON evidence_items
           BEGIN SELECT RAISE(ABORT, 'injected receipt attach failure'); END;''',
      );

      final afterRestart = services<LocalEvidenceStore>();
      await expectLater(
        afterRestart.recoverPendingReceiptCaptures(),
        throwsA(isA<StateError>()),
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      final manifest = File(path.join(pending.path, 'receipt-$captureId.json'));
      expect(await manifest.exists(), isTrue);
      final pendingCapture =
          (await afterRestart.listPendingReceiptCaptures()).single;
      expect(
        await afterRestart.fileForPreserved(pendingCapture.source),
        isNotNull,
      );

      await database.persistenceDatabase.connection.execute(
        'DROP TRIGGER fail_post_commit_receipt_attach',
      );
      expect(await afterRestart.recoverPendingReceiptCaptures(), 1);
      expect(await manifest.exists(), isFalse);
      expect(
        await SqliteEvidenceRepository(
          database.persistenceDatabase,
        ).listForTransaction(transaction.id),
        hasLength(1),
      );
    },
  );

  test(
    'unresolved receipt journal protects orphan evidence across restart',
    () async {
      final sourceFile = File(path.join(root.path, 'receipt-orphan.png'));
      await sourceFile.writeAsBytes([6, 5, 4], flush: true);
      final store = services<LocalEvidenceStore>();
      final source = await store.preserve(
        XFile(sourceFile.path, name: 'receipt-orphan.png'),
        captureKind: 'receipt',
      );
      const captureId = 'receipt-orphan-capture';
      final planned = await store.preparePendingReceiptCapture(
        transactionId: captureId,
        source: source,
      );
      final liveFile = File(
        path.join(evidenceDirectory.path, source.localFileName),
      );
      await evidenceDirectory.create(recursive: true);
      await liveFile.writeAsBytes([6, 5, 4], flush: true);
      await SqliteEvidenceRepository(
        database.persistenceDatabase,
      ).save(planned);

      await database.close();
      await services.reset();
      await database.initialize();
      configureDependencies(
        configuration: const AppConfiguration(),
        database: database,
        logger: AppLogger(),
        documentsDirectory: Directory(path.join(root.path, 'documents')),
        localEvidenceDirectory: evidenceDirectory,
      );

      final afterRestart = services<LocalEvidenceStore>();
      expect(await afterRestart.recoverPendingReceiptCaptures(), 0);
      expect(await afterRestart.recoverUnreferencedEvidence(), 0);
      expect(await liveFile.exists(), isTrue);
      expect(
        await SqliteEvidenceRepository(
          database.persistenceDatabase,
        ).findById(planned.id),
        isNotNull,
      );
    },
  );

  test(
    'statement capture journal is recoverable before evidence publication',
    () async {
      final store = services<LocalEvidenceStore>();
      final now = DateTime.utc(2026, 8, 9, 20);
      await SqliteTransactionRepository(
        database.persistenceDatabase,
      ).save(_transaction('transaction-mixed-recovery', now));
      final source = const PreservedEvidenceSource(
        originalName: 'statement-before-ocr.pdf',
        localFileName: 'statement-before-ocr.pdf',
        mediaType: 'application/pdf',
        sourceFingerprint: 'fingerprint-before-ocr',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      await pending.create(recursive: true);
      await File(
        path.join(pending.path, source.localFileName),
      ).writeAsBytes([5, 4, 3], flush: true);
      const receiptSource = PreservedEvidenceSource(
        originalName: 'receipt-mixed-recovery.png',
        localFileName: 'receipt-mixed-recovery.png',
        mediaType: 'image/png',
      );
      await File(
        path.join(pending.path, receiptSource.localFileName),
      ).writeAsBytes([2, 2, 2], flush: true);
      await store.preparePendingReceiptCapture(
        transactionId: 'transaction-mixed-recovery',
        source: receiptSource,
      );

      final planned = await store.preparePendingStatementCapture(
        statementId: 'statement-before-ocr',
        source: source,
        originalFilename: source.originalName,
        createdAt: DateTime.utc(2026, 8, 9, 20),
      );
      expect(planned.localFileName, source.localFileName);
      expect(
        await File(
          path.join(pending.path, 'statement-statement-before-ocr.json'),
        ).exists(),
        isTrue,
      );

      final recovered = await store.recoverPendingStatementCaptures();
      expect(recovered, 1);
      final statements = await services<FinanceServices>().statementServices!
          .list(includeArchived: true);
      expect(
        statements,
        isA<ApplicationSuccess<List<FinancialStatement>>>().having(
          (value) => value.value.single.id,
          'statement id',
          'statement-before-ocr',
        ),
      );
      expect(
        await SqliteEvidenceRepository(
          database.persistenceDatabase,
        ).findById(planned.id),
        isNotNull,
      );
      expect(
        await File(
          path.join(pending.path, 'receipt-transaction-mixed-recovery.json'),
        ).exists(),
        isTrue,
      );
    },
  );

  test(
    'statement recovery retains its journal when the evidence source is missing',
    () async {
      final store = services<LocalEvidenceStore>();
      const source = PreservedEvidenceSource(
        originalName: 'statement-missing-source.pdf',
        localFileName: 'statement-missing-source.pdf',
        mediaType: 'application/pdf',
        sourceFingerprint: 'fingerprint-missing-source',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      await pending.create(recursive: true);
      final pendingFile = File(path.join(pending.path, source.localFileName));
      await pendingFile.writeAsBytes([4, 5, 6], flush: true);
      final planned = await store.preparePendingStatementCapture(
        statementId: 'statement-missing-source',
        source: source,
        originalFilename: source.originalName,
        createdAt: DateTime.utc(2026, 8, 9, 20),
      );
      await pendingFile.delete();
      await SqliteEvidenceRepository(
        database.persistenceDatabase,
      ).save(planned);

      await expectLater(
        store.recoverPendingStatementCaptures(),
        throwsA(isA<StateError>()),
      );
      final statements = await services<FinanceServices>().statementServices!
          .list(includeArchived: true);
      expect(
        statements,
        isA<ApplicationSuccess<List<FinancialStatement>>>().having(
          (value) => value.value,
          'statements',
          isEmpty,
        ),
      );
      expect(
        await File(
          path.join(
            '${evidenceDirectory.path}.pending',
            'statement-statement-missing-source.json',
          ),
        ).exists(),
        isTrue,
      );
    },
  );

  test(
    'statement recovery retains a journal when its source checksum is corrupted',
    () async {
      final store = services<LocalEvidenceStore>();
      const source = PreservedEvidenceSource(
        originalName: 'statement-corrupt-source.pdf',
        localFileName: 'statement-corrupt-source.pdf',
        mediaType: 'application/pdf',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      await pending.create(recursive: true);
      final pendingFile = File(path.join(pending.path, source.localFileName));
      await pendingFile.writeAsBytes([1, 2, 3, 4], flush: true);
      final planned = await store.preparePendingStatementCapture(
        statementId: 'statement-corrupt-source',
        source: source,
        originalFilename: source.originalName,
        createdAt: DateTime.utc(2026, 8, 9, 20),
      );
      await pendingFile.writeAsBytes([4], flush: true);

      final issues = await store.listPendingCaptureJournalIssues();
      expect(
        issues.map((issue) => issue.fileName),
        contains('statement-statement-corrupt-source.json'),
      );

      await expectLater(
        store.recoverPendingStatementCaptures(),
        throwsA(isA<StateError>()),
      );
      expect(await pendingFile.readAsBytes(), [4]);
      expect(
        await File(
          path.join(pending.path, 'statement-statement-corrupt-source.json'),
        ).exists(),
        isTrue,
      );
      expect(
        await SqliteEvidenceRepository(
          database.persistenceDatabase,
        ).findById(planned.id),
        isNull,
      );
    },
  );

  test(
    'statement recovery retains an inconsistent journal and source',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final store = services<LocalEvidenceStore>();
      const source = PreservedEvidenceSource(
        originalName: 'statement-inconsistent-source.pdf',
        localFileName: 'statement-inconsistent-source.pdf',
        mediaType: 'application/pdf',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      await pending.create(recursive: true);
      await File(
        path.join(pending.path, source.localFileName),
      ).writeAsBytes([8, 8, 8], flush: true);
      final planned = await store.preparePendingStatementCapture(
        statementId: 'statement-inconsistent-journal',
        source: source,
        originalFilename: source.originalName,
        createdAt: now,
      );
      final existingEvidence = _evidence('evidence-existing-statement', now);
      await SqliteEvidenceRepository(
        database.persistenceDatabase,
      ).save(existingEvidence);
      await SqliteStatementRepository(
        database.persistenceDatabase,
      ).saveStatement(
        FinancialStatement(
          id: 'statement-inconsistent-journal',
          evidenceId: existingEvidence.id.value,
          status: StatementStatus.needsSource,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await expectLater(
        store.recoverPendingStatementCaptures(),
        throwsA(isA<FormatException>()),
      );
      expect(
        await File(
          path.join(
            pending.path,
            'statement-statement-inconsistent-journal.json',
          ),
        ).exists(),
        isTrue,
      );
      expect(
        await File(path.join(pending.path, planned.localFileName!)).exists(),
        isTrue,
      );
    },
  );

  test(
    'cancelled statement journal reconciles an existing statement on restart',
    () async {
      final now = DateTime.utc(2026, 8, 9, 21);
      final store = services<LocalEvidenceStore>();
      const source = PreservedEvidenceSource(
        originalName: 'statement-cancelled-source.pdf',
        localFileName: 'statement-cancelled-source.pdf',
        mediaType: 'application/pdf',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      await pending.create(recursive: true);
      await File(
        path.join(pending.path, source.localFileName),
      ).writeAsBytes([4, 2, 4], flush: true);
      final planned = await store.preparePendingStatementCapture(
        statementId: 'statement-cancelled-restart',
        source: source,
        originalFilename: source.originalName,
        createdAt: now,
      );
      final manifest = File(
        path.join(pending.path, 'statement-statement-cancelled-restart.json'),
      );
      final decoded =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      decoded['captureState'] = 'cancelled';
      await manifest.writeAsString(jsonEncode(decoded), flush: true);
      await SqliteEvidenceRepository(
        database.persistenceDatabase,
      ).save(planned);
      await SqliteStatementRepository(
        database.persistenceDatabase,
      ).saveStatement(
        FinancialStatement(
          id: 'statement-cancelled-restart',
          evidenceId: planned.id.value,
          status: StatementStatus.needsSource,
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(await store.recoverPendingStatementCaptures(), 0);
      expect(
        (await store.finance.statementServices!.list(includeArchived: true)
                as ApplicationSuccess<List<FinancialStatement>>)
            .value
            .map((item) => item.id),
        contains('statement-cancelled-restart'),
      );
      final live = await store.fileFor(planned);
      expect(live, isNotNull);
      expect(await live!.exists(), isTrue);
      expect(await manifest.exists(), isFalse);
    },
  );

  test(
    'statement publication failure retains its journal for restart recovery',
    () async {
      final store = services<LocalEvidenceStore>();
      final source = const PreservedEvidenceSource(
        originalName: 'statement-publication-failure.pdf',
        localFileName: 'statement-publication-failure.pdf',
        mediaType: 'application/pdf',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      await pending.create(recursive: true);
      await File(
        path.join(pending.path, source.localFileName),
      ).writeAsBytes([6, 5, 4], flush: true);
      final planned = await store.preparePendingStatementCapture(
        statementId: 'statement-publication-failure',
        source: source,
        originalFilename: source.originalName,
        createdAt: DateTime.utc(2026, 8, 9, 20),
      );
      await database.persistenceDatabase.connection.execute(
        '''CREATE TRIGGER fail_statement_evidence_insert
           BEFORE INSERT ON evidence_items
           BEGIN SELECT RAISE(ABORT, 'injected evidence failure'); END;''',
      );
      final published = await store.storePreservedStatement(
        source,
        pendingStatementId: 'statement-publication-failure',
        pendingOriginalFilename: source.originalName,
        pendingCreatedAt: DateTime.utc(2026, 8, 9, 20),
        planned: planned,
      );
      expect(published, isNull);
      expect(
        await File(path.join(pending.path, source.localFileName)).exists(),
        isTrue,
      );
      expect(
        await File(
          path.join(
            pending.path,
            'statement-statement-publication-failure.json',
          ),
        ).exists(),
        isTrue,
      );
      await database.persistenceDatabase.connection.execute(
        'DROP TRIGGER fail_statement_evidence_insert',
      );

      await database.close();
      await services.reset();
      await database.initialize();
      configureDependencies(
        configuration: const AppConfiguration(),
        database: database,
        logger: AppLogger(),
        documentsDirectory: Directory(path.join(root.path, 'documents')),
        localEvidenceDirectory: evidenceDirectory,
      );

      final afterRestart = services<LocalEvidenceStore>();
      expect(await afterRestart.recoverPendingStatementCaptures(), 1);
      final statements = await services<FinanceServices>().statementServices!
          .list(includeArchived: true);
      expect(
        statements,
        isA<ApplicationSuccess<List<FinancialStatement>>>().having(
          (value) => value.value.single.id,
          'statement id',
          'statement-publication-failure',
        ),
      );
    },
  );

  test(
    'statement recovery preserves its journal when evidence lookup fails',
    () async {
      final source = const PreservedEvidenceSource(
        originalName: 'statement-transient-evidence-failure.pdf',
        localFileName: 'statement-transient-evidence-failure.pdf',
        mediaType: 'application/pdf',
      );
      final pending = Directory('${evidenceDirectory.path}.pending');
      await pending.create(recursive: true);
      await File(
        path.join(pending.path, source.localFileName),
      ).writeAsBytes([3, 1, 4], flush: true);

      final store = LocalEvidenceStore(
        LocalDataManager(database, localEvidenceDirectory: evidenceDirectory),
        _financeWithFailingEvidenceLookup(database),
      );
      await store.preparePendingStatementCapture(
        statementId: 'statement-transient-evidence-failure',
        source: source,
        originalFilename: source.originalName,
        createdAt: DateTime.utc(2026, 8, 9, 20),
      );

      await expectLater(
        store.recoverPendingStatementCaptures(),
        throwsA(isA<StateError>()),
      );
      expect(
        await File(
          path.join(
            pending.path,
            'statement-statement-transient-evidence-failure.json',
          ),
        ).exists(),
        isTrue,
      );
      expect(
        await File(path.join(pending.path, source.localFileName)).exists(),
        isTrue,
      );
    },
  );

  test(
    'statement fingerprint lookup failure blocks a duplicate import',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final item = _evidence('evidence-fingerprint-failure', now);
      await SqliteEvidenceRepository(database.persistenceDatabase).save(item);
      await SqliteStatementRepository(
        database.persistenceDatabase,
      ).saveStatement(
        FinancialStatement(
          id: 'statement-fingerprint-failure',
          evidenceId: item.id.value,
          status: StatementStatus.needsSource,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final store = LocalEvidenceStore(
        LocalDataManager(database, localEvidenceDirectory: evidenceDirectory),
        _financeWithFailingEvidenceLookup(database),
      );

      await expectLater(
        store.findStatementBySourceFingerprint('fingerprint-to-check'),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'startup recovery restores staged statement evidence after interruption',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final item = _evidence('evidence-staged-statement', now);
      final evidence = SqliteEvidenceRepository(database.persistenceDatabase);
      await evidence.save(item);
      await SqliteStatementRepository(
        database.persistenceDatabase,
      ).saveStatement(
        FinancialStatement(
          id: 'statement-staged-evidence',
          evidenceId: item.id.value,
          status: StatementStatus.needsSource,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final deleting = Directory('${evidenceDirectory.path}.deleting');
      await deleting.create(recursive: true);
      final staged = File(path.join(deleting.path, 'delete-recovery-token'));
      final manifest = File('${staged.path}.json');
      await staged.writeAsBytes([6, 5, 4], flush: true);
      await manifest.writeAsString(
        jsonEncode({
          'evidenceId': item.id.value,
          'localFileName': item.localFileName,
          'stagedFileName': path.basename(staged.path),
          'byteLength': 3,
          'sourceFingerprint':
              'da4932954f3027acbbf40518b867d1fdb5a3ed2238d3c806adf1be3c11ef080f',
        }),
        flush: true,
      );

      await database.close();
      await services.reset();
      await database.initialize();
      configureDependencies(
        configuration: const AppConfiguration(),
        database: database,
        logger: AppLogger(),
        localEvidenceDirectory: evidenceDirectory,
      );
      await services<LocalEvidenceStore>().recoverStagedEvidenceDeletions();

      final live = File(path.join(evidenceDirectory.path, item.localFileName!));
      expect(await live.readAsBytes(), [6, 5, 4]);
      expect(await staged.exists(), isFalse);
      expect(await manifest.exists(), isFalse);
    },
  );

  test(
    'staged deletion recovery rejects traversal in an interrupted manifest',
    () async {
      final outside = File(path.join(evidenceDirectory.path, 'outside.bin'));
      await outside.parent.create(recursive: true);
      await outside.writeAsBytes([1, 2, 3], flush: true);
      final deleting = Directory('${evidenceDirectory.path}.deleting');
      await deleting.create(recursive: true);
      final manifest = File(path.join(deleting.path, 'malformed.json'));
      await manifest.writeAsString(
        jsonEncode({
          'evidenceId': 'missing-evidence',
          'localFileName': 'missing.png',
          'stagedFileName': '../outside.bin',
        }),
        flush: true,
      );

      await expectLater(
        services<LocalEvidenceStore>().recoverStagedEvidenceDeletions(),
        throwsA(isA<FormatException>()),
      );

      expect(await outside.readAsBytes(), [1, 2, 3]);
      expect(await manifest.exists(), isTrue);
    },
  );

  test(
    'staged deletion recovery rejects cross-referenced manifests without deleting either artifact',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final first = _evidence('evidence-cross-reference-first', now);
      final second = _evidence('evidence-cross-reference-second', now);
      final evidence = SqliteEvidenceRepository(database.persistenceDatabase);
      await evidence.save(first);
      await evidence.save(second);
      final store = services<LocalEvidenceStore>();
      final liveRoot = evidenceDirectory;
      await liveRoot.create(recursive: true);
      await File(
        path.join(liveRoot.path, first.localFileName!),
      ).writeAsBytes([1, 2, 3], flush: true);
      await File(
        path.join(liveRoot.path, second.localFileName!),
      ).writeAsBytes([4, 5, 6, 7], flush: true);

      await store.deletePublishedFile(first);
      await store.deletePublishedFile(second);
      final deleting = Directory('${evidenceDirectory.path}.deleting');
      final manifests = await deleting
          .list(followLinks: false)
          .where((entity) => entity is File && entity.path.endsWith('.json'))
          .cast<File>()
          .toList();
      expect(manifests, hasLength(2));
      final decoded = <File, Map<String, dynamic>>{
        for (final manifest in manifests)
          manifest:
              jsonDecode(await manifest.readAsString()) as Map<String, dynamic>,
      };
      final firstManifest = decoded.entries
          .singleWhere((entry) => entry.value['evidenceId'] == first.id.value)
          .key;
      final secondManifest = decoded.entries
          .singleWhere((entry) => entry.value['evidenceId'] == second.id.value)
          .key;
      final firstDecoded = decoded[firstManifest]!;
      final secondDecoded = decoded[secondManifest]!;
      final firstStagedFileName = firstDecoded['stagedFileName'];
      final secondStagedFileName = secondDecoded['stagedFileName'];
      firstDecoded['stagedFileName'] = secondStagedFileName;
      secondDecoded['stagedFileName'] = firstStagedFileName;
      await firstManifest.writeAsString(jsonEncode(firstDecoded), flush: true);
      await secondManifest.writeAsString(
        jsonEncode(secondDecoded),
        flush: true,
      );

      await expectLater(
        store.recoverStagedEvidenceDeletions(),
        throwsA(isA<FormatException>()),
      );
      for (final manifest in manifests) {
        expect(await manifest.exists(), isTrue);
        final value =
            jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
        expect(
          await File(
            path.join(deleting.path, value['stagedFileName'] as String),
          ).exists(),
          isTrue,
        );
      }
    },
  );

  test(
    'staged deletion recovery retains metadata when its artifact is missing',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final item = _evidence('evidence-missing-staged-artifact', now);
      await SqliteEvidenceRepository(database.persistenceDatabase).save(item);
      final live = File(path.join(evidenceDirectory.path, item.localFileName!));
      await live.parent.create(recursive: true);
      await live.writeAsBytes([9, 8, 7], flush: true);
      final store = services<LocalEvidenceStore>();

      await store.deletePublishedFile(item);
      final deleting = Directory('${evidenceDirectory.path}.deleting');
      final manifests = await deleting
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.json'))
          .cast<File>()
          .toList();
      expect(manifests, hasLength(1));
      final manifest = manifests.single;
      final decoded = jsonDecode(await manifest.readAsString()) as Map;
      final staged = File(
        path.join(deleting.path, decoded['stagedFileName'] as String),
      );
      await staged.delete();

      await expectLater(
        store.recoverStagedEvidenceDeletions(),
        throwsA(isA<StateError>()),
      );
      expect(await manifest.exists(), isTrue);
      expect(await live.exists(), isFalse);
      expect(
        await SqliteEvidenceRepository(
          database.persistenceDatabase,
        ).findById(item.id),
        isNotNull,
      );
    },
  );

  test(
    'staged deletion recovery retains artifacts for mismatched evidence metadata',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final item = _evidence('evidence-staged-mismatch', now);
      final evidence = SqliteEvidenceRepository(database.persistenceDatabase);
      await evidence.save(item);
      final live = File(path.join(evidenceDirectory.path, item.localFileName!));
      await live.parent.create(recursive: true);
      await live.writeAsBytes([9, 8, 7], flush: true);
      final store = services<LocalEvidenceStore>();

      await store.deletePublishedFile(item);
      final deleting = Directory('${evidenceDirectory.path}.deleting');
      final manifest =
          (await deleting
                  .list()
                  .where(
                    (entity) => entity is File && entity.path.endsWith('.json'),
                  )
                  .cast<File>()
                  .toList())
              .single;
      final decoded =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      final staged = File(
        path.join(deleting.path, decoded['stagedFileName'] as String),
      );
      decoded['localFileName'] = 'different-source.png';
      await manifest.writeAsString(jsonEncode(decoded), flush: true);

      await expectLater(
        store.recoverStagedEvidenceDeletions(),
        throwsA(isA<StateError>()),
      );
      expect(await staged.exists(), isTrue);
      expect(await manifest.exists(), isTrue);
      expect(await evidence.findById(item.id), isNotNull);
    },
  );

  test(
    'restart recovery finalizes prepared deletion when the row is missing',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final item = _evidence('evidence-staged-missing-row', now);
      final evidence = SqliteEvidenceRepository(database.persistenceDatabase);
      await evidence.save(item);
      final live = File(path.join(evidenceDirectory.path, item.localFileName!));
      await live.parent.create(recursive: true);
      await live.writeAsBytes([3, 2, 1], flush: true);
      final store = services<LocalEvidenceStore>();

      await store.deletePublishedFile(item);
      final deleting = Directory('${evidenceDirectory.path}.deleting');
      final manifest =
          (await deleting
                  .list()
                  .where(
                    (entity) => entity is File && entity.path.endsWith('.json'),
                  )
                  .cast<File>()
                  .toList())
              .single;
      final decoded =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      final staged = File(
        path.join(deleting.path, decoded['stagedFileName'] as String),
      );
      await evidence.remove(item.id);

      await database.close();
      await services.reset();
      await database.initialize();
      configureDependencies(
        configuration: const AppConfiguration(),
        database: database,
        logger: AppLogger(),
        documentsDirectory: Directory(path.join(root.path, 'documents')),
        localEvidenceDirectory: evidenceDirectory,
      );
      await services<LocalEvidenceStore>().recoverStagedEvidenceDeletions();

      expect(await staged.exists(), isFalse);
      expect(await manifest.exists(), isFalse);
      expect(
        await SqliteEvidenceRepository(
          database.persistenceDatabase,
        ).findById(item.id),
        isNull,
      );
    },
  );

  test(
    'staged deletion recovery retains a corrupted committed artifact',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final item = _evidence('evidence-staged-corrupt-committed', now);
      final evidence = SqliteEvidenceRepository(database.persistenceDatabase);
      await evidence.save(item);
      final live = File(path.join(evidenceDirectory.path, item.localFileName!));
      await live.parent.create(recursive: true);
      await live.writeAsBytes([3, 2, 1], flush: true);
      final store = services<LocalEvidenceStore>();

      await store.deletePublishedFile(item);
      final deleting = Directory('${evidenceDirectory.path}.deleting');
      final manifest =
          (await deleting
                  .list()
                  .where(
                    (entity) => entity is File && entity.path.endsWith('.json'),
                  )
                  .cast<File>()
                  .toList())
              .single;
      final decoded =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      decoded['deletionState'] = 'committed';
      await manifest.writeAsString(jsonEncode(decoded), flush: true);
      final staged = File(
        path.join(deleting.path, decoded['stagedFileName'] as String),
      );
      await staged.writeAsBytes([0], flush: true);
      await evidence.remove(item.id);

      await expectLater(
        store.recoverStagedEvidenceDeletions(),
        throwsA(isA<StateError>()),
      );
      expect(await staged.exists(), isTrue);
      expect(await manifest.exists(), isTrue);
    },
  );

  test(
    'restart recovery handles evidence whose source extension is json',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final item = _evidence(
        'evidence-staged-json',
        now,
        localFileName: 'evidence-staged-json.json',
        originalName: 'evidence-staged-json.json',
        mediaType: 'application/json',
      );
      final evidence = SqliteEvidenceRepository(database.persistenceDatabase);
      await evidence.save(item);
      final live = File(path.join(evidenceDirectory.path, item.localFileName!));
      await live.parent.create(recursive: true);
      await live.writeAsString(
        jsonEncode({'evidenceId': item.id.value}),
        flush: true,
      );
      final store = services<LocalEvidenceStore>();

      await store.deletePublishedFile(item);
      await evidence.remove(item.id);
      await database.close();
      await services.reset();
      await database.initialize();
      configureDependencies(
        configuration: const AppConfiguration(),
        database: database,
        logger: AppLogger(),
        documentsDirectory: Directory(path.join(root.path, 'documents')),
        localEvidenceDirectory: evidenceDirectory,
      );

      await services<LocalEvidenceStore>().recoverStagedEvidenceDeletions();

      expect(await live.exists(), isFalse);
      expect(
        await Directory('${evidenceDirectory.path}.deleting').list().toList(),
        isEmpty,
      );
      expect(
        await SqliteEvidenceRepository(
          database.persistenceDatabase,
        ).findById(item.id),
        isNull,
      );
    },
  );

  test(
    'restart recovery retires a committed deletion journal without its artifact',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final item = _evidence('evidence-staged-committed-missing', now);
      final evidence = SqliteEvidenceRepository(database.persistenceDatabase);
      await evidence.save(item);
      final live = File(path.join(evidenceDirectory.path, item.localFileName!));
      await live.parent.create(recursive: true);
      await live.writeAsBytes([6, 5, 4], flush: true);
      final store = services<LocalEvidenceStore>();

      await store.deletePublishedFile(item);
      final deleting = Directory('${evidenceDirectory.path}.deleting');
      final manifest =
          (await deleting
                  .list()
                  .where(
                    (entity) => entity is File && entity.path.endsWith('.json'),
                  )
                  .cast<File>()
                  .toList())
              .single;
      final decoded =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      decoded['deletionState'] = 'committed';
      await manifest.writeAsString(jsonEncode(decoded), flush: true);
      await File(
        path.join(deleting.path, decoded['stagedFileName'] as String),
      ).delete();
      await evidence.remove(item.id);

      await database.close();
      await services.reset();
      await database.initialize();
      configureDependencies(
        configuration: const AppConfiguration(),
        database: database,
        logger: AppLogger(),
        documentsDirectory: Directory(path.join(root.path, 'documents')),
        localEvidenceDirectory: evidenceDirectory,
      );
      await services<LocalEvidenceStore>().recoverStagedEvidenceDeletions();

      expect(await manifest.exists(), isFalse);
    },
  );

  test(
    'evidence finalization retains a staged artifact with invalid identity',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final item = _evidence('evidence-finalize-invalid', now);
      await SqliteEvidenceRepository(database.persistenceDatabase).save(item);
      final live = File(path.join(evidenceDirectory.path, item.localFileName!));
      await live.parent.create(recursive: true);
      await live.writeAsBytes([8, 7, 6], flush: true);
      final store = services<LocalEvidenceStore>();

      await store.deletePublishedFile(item);
      final deleting = Directory('${evidenceDirectory.path}.deleting');
      final manifest =
          (await deleting
                  .list()
                  .where(
                    (entity) => entity is File && entity.path.endsWith('.json'),
                  )
                  .cast<File>()
                  .toList())
              .single;
      final decoded =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      decoded['localFileName'] = 'different-source.png';
      await manifest.writeAsString(jsonEncode(decoded), flush: true);
      final staged = File(
        path.join(deleting.path, decoded['stagedFileName'] as String),
      );

      await expectLater(
        store.finalizeDeletedEvidenceFile(item),
        throwsA(isA<FormatException>()),
      );
      expect(await staged.exists(), isTrue);
      expect(await manifest.exists(), isTrue);

      decoded['localFileName'] = item.localFileName;
      decoded['sourceFingerprint'] = 'not-the-staged-file';
      await manifest.writeAsString(jsonEncode(decoded), flush: true);
      await expectLater(
        store.finalizeDeletedEvidenceFile(item),
        throwsA(isA<StateError>()),
      );
      expect(await staged.exists(), isTrue);
      expect(await manifest.exists(), isTrue);
    },
  );

  test('erase all removes the staged evidence deletion tree', () async {
    final deleting = Directory('${evidenceDirectory.path}.deleting');
    await deleting.create(recursive: true);
    await File(
      path.join(deleting.path, 'delete-recovery.bin'),
    ).writeAsBytes([4, 5, 6], flush: true);

    await services<LocalDataManager>().eraseAll();

    expect(await deleting.exists(), isFalse);
  });

  test(
    'shared evidence filenames are retained for the remaining owner',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final first = _transaction('transaction-shared-file-first', now);
      final second = _transaction('transaction-shared-file-second', now);
      final transactions = SqliteTransactionRepository(
        database.persistenceDatabase,
      );
      final evidence = SqliteEvidenceRepository(database.persistenceDatabase);
      final firstEvidence = _evidence('evidence-shared-file-first', now);
      final secondEvidence = EvidenceItem(
        id: EvidenceId('evidence-shared-file-second'),
        type: EvidenceType.receiptImage,
        originalName: 'second.png',
        mediaType: 'image/png',
        localFileName: firstEvidence.localFileName,
        provenance: Provenance(
          id: ProvenanceId('evidence-shared-file-second-provenance'),
          sourceType: ProvenanceSourceType.scan,
          capturedAt: now,
          originalRepresentation: 'second.png',
        ),
        createdAt: now,
      );
      await transactions.save(first);
      await transactions.save(second);
      await evidence.save(firstEvidence);
      await evidence.save(secondEvidence);
      await evidence.link(
        AttachmentLink(
          id: AttachmentLinkId('attachment-shared-file-first'),
          transactionId: first.id,
          evidenceId: firstEvidence.id,
          createdAt: now,
        ),
      );
      await evidence.link(
        AttachmentLink(
          id: AttachmentLinkId('attachment-shared-file-second'),
          transactionId: second.id,
          evidenceId: secondEvidence.id,
          createdAt: now,
        ),
      );
      await evidenceDirectory.create(recursive: true);
      final file = File(
        path.join(evidenceDirectory.path, firstEvidence.localFileName!),
      );
      await file.writeAsBytes([8, 8, 8], flush: true);

      final result = await services<FinanceServices>()
          .deleteTransactionPermanently(first.id.value);
      expect(result, isA<ApplicationSuccess<void>>());
      expect(await file.exists(), isTrue);
      expect(await evidence.findById(firstEvidence.id), isNull);
      expect(await evidence.findById(secondEvidence.id), isNotNull);
    },
  );

  test(
    'unprocessed statement deletion retains a shared evidence filename',
    () async {
      final now = DateTime.utc(2026, 8, 9, 20);
      final transaction = _transaction(
        'transaction-shared-statement-file',
        now,
      );
      final transactions = SqliteTransactionRepository(
        database.persistenceDatabase,
      );
      final evidence = SqliteEvidenceRepository(database.persistenceDatabase);
      final statements = SqliteStatementRepository(
        database.persistenceDatabase,
      );
      final firstEvidence = _evidence('evidence-shared-statement-first', now);
      final secondEvidence = EvidenceItem(
        id: EvidenceId('evidence-shared-statement-second'),
        type: EvidenceType.document,
        originalName: 'statement-second.pdf',
        mediaType: 'application/pdf',
        localFileName: firstEvidence.localFileName,
        provenance: Provenance(
          id: ProvenanceId('evidence-shared-statement-second-provenance'),
          sourceType: ProvenanceSourceType.scan,
          capturedAt: now,
          originalRepresentation: 'statement-second.pdf',
        ),
        createdAt: now,
      );
      await transactions.save(transaction);
      await evidence.save(firstEvidence);
      await evidence.save(secondEvidence);
      await statements.saveStatement(
        FinancialStatement(
          id: 'statement-shared-file',
          evidenceId: firstEvidence.id.value,
          status: StatementStatus.needsSource,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await evidence.link(
        AttachmentLink(
          id: AttachmentLinkId('attachment-shared-statement-second'),
          transactionId: transaction.id,
          evidenceId: secondEvidence.id,
          createdAt: now,
        ),
      );
      await evidenceDirectory.create(recursive: true);
      final file = File(
        path.join(evidenceDirectory.path, firstEvidence.localFileName!),
      );
      await file.writeAsBytes([9, 8, 7], flush: true);

      expect(
        await services<LocalEvidenceStore>().removeUnprocessedStatement(
          'statement-shared-file',
        ),
        isTrue,
      );
      expect(await file.exists(), isTrue);
      expect(await evidence.findById(firstEvidence.id), isNull);
      expect(await evidence.findById(secondEvidence.id), isNotNull);
    },
  );
}

Transaction _transaction(String id, DateTime now) => Transaction(
  id: TransactionId(id),
  timing: KnownTransactionTime(now),
  money: Money(
    amount: DecimalValue.parse('12.50'),
    currency: CurrencyCode('USD'),
  ),
  direction: TransactionDirection.expense,
  sourceType: TransactionSourceType.manual,
  transactionDate: '2026-08-09',
  provenance: [
    Provenance(
      id: ProvenanceId('$id-provenance'),
      sourceType: ProvenanceSourceType.userEntry,
      capturedAt: now,
    ),
  ],
  createdAt: now,
  updatedAt: now,
);

EvidenceItem _evidence(
  String id,
  DateTime now, {
  String? localFileName,
  String? originalName,
  String? mediaType,
}) => EvidenceItem(
  id: EvidenceId(id),
  type: EvidenceType.receiptImage,
  originalName: originalName ?? '$id.png',
  mediaType: mediaType ?? 'image/png',
  localFileName: localFileName ?? '$id.png',
  provenance: Provenance(
    id: ProvenanceId('$id-provenance'),
    sourceType: ProvenanceSourceType.scan,
    capturedAt: now,
    originalRepresentation: originalName ?? '$id.png',
  ),
  createdAt: now,
);

FinanceServices _financeWithFailingEvidenceLookup(LocalDatabase database) {
  final persistence = database.persistenceDatabase;
  return FinanceServices(
    SqliteTransactionRepository(persistence),
    SqlitePaymentSourceRepository(persistence),
    SqliteMerchantRepository(persistence),
    SqliteCategoryRepository(persistence),
    SqliteTagRepository(persistence),
    _FailingEvidenceRepository(SqliteEvidenceRepository(persistence)),
    SqliteUserPreferenceRepository(persistence),
    statements: SqliteStatementRepository(persistence),
    duplicateGroups: SqliteDuplicateCandidateGroupRepository(persistence),
  );
}

final class _FailingEvidenceRepository implements EvidenceRepository {
  _FailingEvidenceRepository(this.delegate);

  final EvidenceRepository delegate;

  @override
  Future<void> save(EvidenceItem evidence) => delegate.save(evidence);

  @override
  Future<void> saveExtraction(Extraction extraction) =>
      delegate.saveExtraction(extraction);

  @override
  Future<void> link(AttachmentLink link) => delegate.link(link);

  @override
  Future<void> unlinkFromTransaction(
    TransactionId transactionId,
    EvidenceId evidenceId,
  ) => delegate.unlinkFromTransaction(transactionId, evidenceId);

  @override
  Future<EvidenceItem?> findById(EvidenceId id) => Future<EvidenceItem?>.error(
    StateError('injected transient evidence lookup failure'),
  );

  @override
  Future<List<EvidenceItem>> listForTransaction(TransactionId id) =>
      delegate.listForTransaction(id);

  @override
  Future<void> remove(EvidenceId id) => delegate.remove(id);
}
