import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/features/foundation/presentation/data_integrity_reports_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders grouped findings and refreshes the report', (
    tester,
  ) async {
    final service = _FakeIntegrityReportService();
    services.registerSingleton<DataIntegrityReportService>(service);
    addTearDown(services.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DataIntegrityReportsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Data Integrity Reports'), findsOneWidget);
    expect(find.text('Missing receipts'), findsOneWidget);
    expect(
      find.text(
        'A receipt linked to a transaction could not be found in local storage.',
      ),
      findsOneWidget,
    );
    expect(find.text('Warning'), findsOneWidget);
    await tester.tap(
      find.text(
        'A receipt linked to a transaction could not be found in local storage.',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Recommended action: Attach the original file again from the affected record.',
      ),
      findsOneWidget,
    );
    expect(find.text('Transaction reference: tx-1'), findsOneWidget);

    await tester.tap(find.text('Refresh report'));
    await tester.pumpAndSettle();

    expect(service.runCount, 1);
    expect(find.text('No integrity issues were found.'), findsOneWidget);
  });

  testWidgets('localizes affected record references', (tester) async {
    final service = _FakeIntegrityReportService();
    services.registerSingleton<DataIntegrityReportService>(service);
    addTearDown(services.reset);

    Future<void> pumpFor(Locale locale) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: DataIntegrityReportsPage(key: ValueKey(locale.toString())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();
    }

    await pumpFor(const Locale('en'));
    expect(find.text('Transaction reference: tx-1'), findsOneWidget);

    await pumpFor(const Locale('zh', 'CN'));
    expect(find.text('交易引用：tx-1'), findsOneWidget);

    await pumpFor(const Locale('es'));
    expect(find.text('Referencia de Transacción: tx-1'), findsOneWidget);
  });

  testWidgets('enables contextual actions for supported record types', (
    tester,
  ) async {
    final service = _FakeIntegrityReportService(
      initial: DataIntegrityReport(
        id: 'routing-report',
        scannedAtUtc: DateTime.utc(2026, 11, 3, 12),
        findings: [
          DataIntegrityFinding(
            id: 'routing-finding',
            code: 'missing_referenced_record',
            category: DataIntegrityFindingCategory.missingReferencedRecord,
            severity: DataIntegrityFindingSeverity.error,
            description: 'A related record is unavailable.',
            affectedRecords: [
              for (final record in const [
                DataIntegrityRecordReference(type: 'transaction', id: 'tx-1'),
                DataIntegrityRecordReference(type: 'evidence', id: 'e-1'),
                DataIntegrityRecordReference(type: 'attachment', id: 'a-1'),
                DataIntegrityRecordReference(type: 'budget', id: 'b-1'),
                DataIntegrityRecordReference(type: 'category', id: 'c-1'),
                DataIntegrityRecordReference(type: 'merchant', id: 'm-1'),
                DataIntegrityRecordReference(
                  type: 'analysisRule',
                  id: 'rule-1@1.0.0',
                ),
              ])
                record,
            ],
            context: const {},
            recommendedAction: 'Review the related record.',
            detectedAtUtc: DateTime.utc(2026, 11, 3, 12),
          ),
        ],
      ),
    );
    services.registerSingleton<DataIntegrityReportService>(service);
    addTearDown(services.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DataIntegrityReportsPage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();

    for (final label in const [
      'Transaction reference: tx-1',
      'Evidence reference: e-1',
      'Attachment reference: a-1',
      'Budget reference: b-1',
      'Category reference: c-1',
      'Merchant reference: m-1',
      'Analysis rule reference: rule-1@1.0.0',
    ]) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byType(TextButton),
      );
      expect(button, findsOneWidget);
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    }
  });

  testWidgets('disables evidence actions when no linked transaction exists', (
    tester,
  ) async {
    final service = _FakeIntegrityReportService(
      initial: DataIntegrityReport(
        id: 'orphan-evidence-report',
        scannedAtUtc: DateTime.utc(2026, 11, 3, 12),
        findings: [
          DataIntegrityFinding(
            id: 'orphan-evidence-finding',
            code: 'missing_evidence_file',
            category: DataIntegrityFindingCategory.missingAttachment,
            severity: DataIntegrityFindingSeverity.warning,
            description: 'An evidence file is unavailable.',
            affectedRecords: const [
              DataIntegrityRecordReference(type: 'evidence', id: 'orphan-e-1'),
              DataIntegrityRecordReference(
                type: 'attachment',
                id: 'orphan-a-1',
              ),
            ],
            context: const {},
            recommendedAction: 'Review the affected record.',
            detectedAtUtc: DateTime.utc(2026, 11, 3, 12),
          ),
        ],
      ),
    );
    services.registerSingleton<DataIntegrityReportService>(service);
    addTearDown(services.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DataIntegrityReportsPage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();

    for (final label in const [
      'Evidence reference: orphan-e-1',
      'Attachment reference: orphan-a-1',
    ]) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byType(TextButton),
      );
      expect(button, findsOneWidget);
      expect(tester.widget<TextButton>(button).onPressed, isNull);
    }
  });
}

final class _FakeIntegrityReportService implements DataIntegrityReportService {
  _FakeIntegrityReportService({DataIntegrityReport? initial})
    : _initial = initial ?? _defaultInitial;

  int runCount = 0;

  static final _defaultInitial = DataIntegrityReport(
    id: 'report-1',
    scannedAtUtc: DateTime.utc(2026, 11, 3, 12),
    findings: [
      DataIntegrityFinding(
        id: 'missing_receipt:evidence:e-1|transaction:tx-1',
        code: 'missing_receipt',
        category: DataIntegrityFindingCategory.missingReceipt,
        severity: DataIntegrityFindingSeverity.warning,
        description: 'A receipt linked to a transaction is unavailable.',
        affectedRecords: [
          DataIntegrityRecordReference(type: 'transaction', id: 'tx-1'),
        ],
        context: const {},
        recommendedAction: 'Attach the original file again.',
        detectedAtUtc: DateTime.utc(2026, 11, 3, 12),
      ),
    ],
  );

  final DataIntegrityReport _initial;

  @override
  Future<DataIntegrityReport?> latestReport() async => _initial;

  @override
  Future<List<DataIntegrityReport>> reportHistory({int limit = 20}) async =>
      runCount == 0 ? [_initial] : const [];

  @override
  Future<DataIntegrityReport> runReport() async {
    runCount++;
    return DataIntegrityReport(
      id: 'report-2',
      scannedAtUtc: DateTime.utc(2026, 11, 3, 13),
      findings: const [],
    );
  }
}
