import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_data_integrity_report_service.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/local_operation_diagnostics_store.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Directory root;
  late Directory databaseDirectory;
  late Directory evidenceDirectory;
  late LocalDatabase database;
  late LocalDataIntegrityReportService service;
  late LocalOperationDiagnosticsStore operationDiagnostics;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('butlerly-integrity-report-');
    databaseDirectory = Directory(path.join(root.path, 'database'))
      ..createSync(recursive: true);
    evidenceDirectory = Directory(path.join(root.path, 'evidence'))
      ..createSync(recursive: true);
    database = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: databaseDirectory.path,
    );
    await database.initialize();
    service = LocalDataIntegrityReportService(
      database,
      LocalDataManager(database, localEvidenceDirectory: evidenceDirectory),
      clock: () => DateTime.utc(2026, 11, 3, 12),
    );
    operationDiagnostics = LocalOperationDiagnosticsStore(
      database,
      clock: () => DateTime.utc(2026, 11, 3, 12),
    );
  });

  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });

  test(
    'scans without mutating source rows and persists stable history',
    () async {
      await database.database.insert('provenances', {
        'id': 'integrity-provenance',
        'source_type': 'userEntry',
        'captured_at': '2026-11-03T12:00:00.000Z',
        'source_id': null,
        'original_representation': null,
        'source_language': null,
      });
      await database.database.insert('evidence_items', {
        'id': 'integrity-missing-receipt',
        'type': 'receiptImage',
        'original_name': 'receipt.jpg',
        'media_type': 'image/jpeg',
        'provenance_id': 'integrity-provenance',
        'created_at': '2026-11-03T12:00:00.000Z',
        'source_language': null,
        'local_file_name': 'receipts/missing.jpg',
      });
      await database.database.insert('analysis_rule_configurations', {
        'rule_id': 'custom.integrity-rule',
        'configuration': '{invalid',
        'updated_at': '2026-11-03T12:00:00.000Z',
      });
      await database.database.insert('analysis_rule_definitions', {
        'rule_id': 'custom.non-string-rule',
        'rule_version': '1.0.0',
        'schema_version': '1',
        'source_type': 'user',
        'definition': '{}',
        'canonical_definition': '{}',
        'definition_hash': 'invalid-hash',
        'validation_status': 'invalid',
        'validation_diagnostics': null,
        'installed_at': '2026-11-03T12:00:00.000Z',
        'retired_at': null,
      });
      await database.database.insert('analysis_rule_configurations', {
        'rule_id': 'custom.non-string-rule',
        'configuration': 42,
        'updated_at': '2026-11-03T12:00:00.000Z',
      });
      for (final version in ['1.0.0', '2.0.0']) {
        await database.database.insert('analysis_rule_definitions', {
          'rule_id': 'custom.multi-version-rule',
          'rule_version': version,
          'schema_version': '1',
          'source_type': 'user',
          'definition': '{}',
          'canonical_definition': '{}',
          'definition_hash': 'invalid-hash',
          'validation_status': 'invalid',
          'validation_diagnostics': null,
          'installed_at': '2026-11-03T12:00:00.000Z',
          'retired_at': null,
        });
      }
      await database.database.insert('analysis_rule_configurations', {
        'rule_id': 'custom.multi-version-rule',
        'configuration': '{invalid',
        'updated_at': '2026-11-03T12:00:00.000Z',
      });
      await database.database.insert('analysis_rule_definitions', {
        'rule_id': 'custom.source-type-rule',
        'rule_version': '1.0.0',
        'schema_version': '1',
        'source_type': 'user',
        'definition': '{}',
        'canonical_definition': '{}',
        'definition_hash': 'same-definition-hash',
        'validation_status': 'valid',
        'validation_diagnostics': null,
        'installed_at': '2026-11-03T12:00:00.000Z',
        'retired_at': null,
      });
      await database.database.insert('analysis_rule_definitions', {
        'rule_id': 'ANL-R998',
        'rule_version': '1.0.0',
        'schema_version': '1.0.0',
        'source_type': 'user',
        'definition': '{}',
        'canonical_definition': '{}',
        'definition_hash': sha256.convert(utf8.encode('{}')).toString(),
        'validation_status': 'valid',
        'validation_diagnostics': null,
        'installed_at': '2026-11-03T12:00:00.000Z',
        'retired_at': null,
      });
      await database.database.insert('analysis_rule_provenance', {
        'rule_id': 'custom.source-type-rule',
        'rule_version': '1.0.0',
        'source_type': 'bundled',
        'definition_hash': 'same-definition-hash',
        'recorded_at': '2026-11-03T12:00:00.000Z',
      });
      final evidenceBefore = await database.database.query('evidence_items');

      final first = await service.runReport();
      expect(
        first.findings.map((finding) => finding.category),
        containsAll(<DataIntegrityFindingCategory>[
          DataIntegrityFindingCategory.missingReceipt,
          DataIntegrityFindingCategory.analysisInconsistency,
          DataIntegrityFindingCategory.invalidCustomConfiguration,
        ]),
      );
      expect(
        first.findings
            .where(
              (finding) =>
                  finding.code == 'invalid_analysis_rule_configuration',
            )
            .where(
              (finding) => finding.affectedRecords.any(
                (record) => record.id == 'custom.multi-version-rule',
              ),
            ),
        hasLength(1),
      );
      expect(
        first.findings
            .where(
              (finding) => finding.code == 'analysis_rule_provenance_mismatch',
            )
            .single
            .affectedRecords
            .single
            .id,
        'custom.source-type-rule@1.0.0',
      );
      expect(
        first.findings
            .where(
              (finding) => finding.code == 'invalid_analysis_rule_definition',
            )
            .any(
              (finding) => finding.affectedRecords.any(
                (record) => record.id == 'ANL-R998@1.0.0',
              ),
            ),
        isTrue,
      );
      expect(await database.database.query('evidence_items'), evidenceBefore);

      final second = await service.runReport();
      expect(
        second.findings.map((finding) => finding.id).toSet(),
        first.findings.map((finding) => finding.id).toSet(),
      );
      expect(await service.reportHistory(limit: 2), hasLength(2));

      await database.close();
      database = LocalDatabase(
        logger: AppLogger(),
        factory: databaseFactoryFfi,
        databaseDirectory: databaseDirectory.path,
      );
      await database.initialize();
      final reopenedService = LocalDataIntegrityReportService(
        database,
        LocalDataManager(database, localEvidenceDirectory: evidenceDirectory),
      );
      final latest = await reopenedService.latestReport();
      expect(latest?.id, second.id);
      expect(
        latest?.findings.map((finding) => finding.id),
        containsAll(second.findings.map((finding) => finding.id)),
      );
    },
  );

  test(
    'persists operation diagnostics with privacy-safe record references',
    () async {
      await operationDiagnostics.record(
        operation: 'backup',
        findings: [
          DataIntegrityFinding(
            id: 'missing:evidence-1',
            code: 'missing_evidence',
            category: DataIntegrityFindingCategory.missingAttachment,
            severity: DataIntegrityFindingSeverity.warning,
            description: 'An attachment is unavailable.',
            affectedRecords: const [
              DataIntegrityRecordReference(type: 'evidence', id: 'evidence-1'),
            ],
            context: const {'count': '1'},
            recommendedAction: 'Attach the original file again.',
            detectedAtUtc: DateTime.utc(2026, 11, 3, 12),
          ),
        ],
      );

      await database.close();
      database = LocalDatabase(
        logger: AppLogger(),
        factory: databaseFactoryFfi,
        databaseDirectory: databaseDirectory.path,
      );
      await database.initialize();
      final reopened = LocalOperationDiagnosticsStore(database);
      final diagnostics = await reopened.recent();

      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.operation, 'backup');
      expect(diagnostics.single.finding.code, 'missing_evidence');
      expect(
        diagnostics.single.finding.affectedRecords.single.id,
        'evidence-1',
      );
    },
  );

  test(
    'serializes report scans behind the analysis consistency gate',
    () async {
      final gate = AnalysisConsistencyGate();
      final entered = Completer<void>();
      final release = Completer<void>();
      final blocker = gate.runExclusive(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;

      var completed = false;
      final gatedService = LocalDataIntegrityReportService(
        database,
        LocalDataManager(database, localEvidenceDirectory: evidenceDirectory),
        consistencyGate: gate,
        clock: () => DateTime.utc(2026, 11, 3, 12),
      );
      final reportFuture = gatedService.runReport().then((report) {
        completed = true;
        return report;
      });
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      release.complete();
      await blocker;
      expect((await reportFuture).findings, isEmpty);
    },
  );

  test('persists stable record references for foreign-key findings', () async {
    await database.database.execute('PRAGMA foreign_keys = OFF');
    await database.database.insert('attachment_links', {
      'id': 'integrity-orphan-attachment',
      'transaction_id': 'integrity-missing-transaction',
      'evidence_id': 'integrity-missing-evidence',
      'created_at': '2026-11-03T12:00:00.000Z',
    });
    await database.database.execute('PRAGMA foreign_keys = ON');

    final report = await service.runReport();
    final finding = report.findings.singleWhere(
      (value) => value.code == 'missing_referenced_record',
    );
    expect(
      finding.affectedRecords.any(
        (record) =>
            record.type == 'attachment' &&
            record.id == 'integrity-orphan-attachment',
      ),
      isTrue,
    );

    await database.close();
    database = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: databaseDirectory.path,
    );
    await database.initialize();
    final reopenedService = LocalDataIntegrityReportService(
      database,
      LocalDataManager(database, localEvidenceDirectory: evidenceDirectory),
    );
    final persisted = await reopenedService.latestReport();
    final persistedFinding = persisted!.findings.singleWhere(
      (value) => value.code == 'missing_referenced_record',
    );
    expect(
      persistedFinding.affectedRecords.any(
        (record) =>
            record.type == 'attachment' &&
            record.id == 'integrity-orphan-attachment',
      ),
      isTrue,
    );
  });

  test(
    'persists budget hierarchy findings through report reconstruction',
    () async {
      const capturedAt = '2026-11-03T12:00:00.000Z';
      await database.database.insert('categories', {
        'id': 'integrity-budget-parent',
        'name': 'Budget parent',
        'origin': 'user',
        'parent_id': null,
        'status': 'active',
        'created_at': capturedAt,
        'updated_at': capturedAt,
      });
      await database.database.insert('categories', {
        'id': 'integrity-budget-child',
        'name': 'Budget child',
        'origin': 'user',
        'parent_id': 'integrity-budget-parent',
        'status': 'active',
        'created_at': capturedAt,
        'updated_at': capturedAt,
      });
      await database.database.insert('categories', {
        'id': 'integrity-budget-nested',
        'name': 'Budget nested',
        'origin': 'user',
        'parent_id': 'integrity-budget-child',
        'status': 'active',
        'created_at': capturedAt,
        'updated_at': capturedAt,
      });
      await database.database.insert('budgets', {
        'id': 'integrity-invalid-subcategory-budget',
        'scope': 'subcategory',
        'scope_id': 'integrity-budget-parent',
        'currency': 'USD',
        'amount': '100.00',
        'created_at': capturedAt,
        'updated_at': capturedAt,
      });
      await database.database.insert('budgets', {
        'id': 'integrity-invalid-category-budget',
        'scope': 'category',
        'scope_id': 'integrity-budget-child',
        'currency': 'USD',
        'amount': '50.00',
        'created_at': capturedAt,
        'updated_at': capturedAt,
      });
      await database.database.insert('budgets', {
        'id': 'integrity-invalid-nested-subcategory-budget',
        'scope': 'subcategory',
        'scope_id': 'integrity-budget-nested',
        'currency': 'USD',
        'amount': '25.00',
        'created_at': capturedAt,
        'updated_at': capturedAt,
      });

      final report = await service.runReport();
      expect(
        report.findings
            .where(
              (finding) => finding.code == 'invalid_budget_scope_reference',
            )
            .map((finding) => finding.affectedRecords.first.id),
        containsAll(<String>[
          'integrity-invalid-subcategory-budget',
          'integrity-invalid-category-budget',
          'integrity-invalid-nested-subcategory-budget',
        ]),
      );

      await database.close();
      database = LocalDatabase(
        logger: AppLogger(),
        factory: databaseFactoryFfi,
        databaseDirectory: databaseDirectory.path,
      );
      await database.initialize();
      final reopenedService = LocalDataIntegrityReportService(
        database,
        LocalDataManager(database, localEvidenceDirectory: evidenceDirectory),
      );
      final persisted = await reopenedService.latestReport();
      final persistedFindings = persisted!.findings
          .where((finding) => finding.code == 'invalid_budget_scope_reference')
          .toList();
      expect(persistedFindings, hasLength(3));
      expect(
        persistedFindings
            .expand((finding) => finding.affectedRecords)
            .map((record) => '${record.type}:${record.id}'),
        containsAll(<String>[
          'budget:integrity-invalid-subcategory-budget',
          'budget:integrity-invalid-category-budget',
          'budget:integrity-invalid-nested-subcategory-budget',
          'category:integrity-budget-parent',
          'category:integrity-budget-child',
          'category:integrity-budget-nested',
        ]),
      );
    },
  );
}
