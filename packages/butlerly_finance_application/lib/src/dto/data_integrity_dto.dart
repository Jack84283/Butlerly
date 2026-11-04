enum DataIntegrityFindingCategory {
  missingReceipt,
  missingAttachment,
  invalidFileReference,
  missingReferencedRecord,
  analysisInconsistency,
  invalidCustomConfiguration,
  relationshipInconsistency,
}

enum DataIntegrityFindingSeverity { info, warning, error }

final class DataIntegrityRecordReference {
  const DataIntegrityRecordReference({required this.type, required this.id});

  final String type;
  final String id;
}

/// A privacy-safe, stable explanation of one local data inconsistency.
final class DataIntegrityFinding {
  const DataIntegrityFinding({
    required this.id,
    required this.code,
    required this.category,
    required this.severity,
    required this.description,
    required this.affectedRecords,
    required this.context,
    required this.recommendedAction,
    required this.detectedAtUtc,
  });

  /// Stable for the same underlying record and finding code across scans.
  final String id;
  final String code;
  final DataIntegrityFindingCategory category;
  final DataIntegrityFindingSeverity severity;
  final String description;
  final List<DataIntegrityRecordReference> affectedRecords;
  final Map<String, String> context;
  final String recommendedAction;
  final DateTime detectedAtUtc;
}

final class DataIntegrityReport {
  const DataIntegrityReport({
    required this.id,
    required this.scannedAtUtc,
    required this.findings,
  });

  final String id;
  final DateTime scannedAtUtc;
  final List<DataIntegrityFinding> findings;

  bool get hasFindings => findings.isNotEmpty;
}

/// Application-facing port for the read-only integrity reporting workflow.
/// Implementations may persist report history, but must never mutate the
/// source financial records while scanning.
abstract interface class DataIntegrityReportService {
  Future<DataIntegrityReport?> latestReport();

  Future<List<DataIntegrityReport>> reportHistory({int limit = 20});

  Future<DataIntegrityReport> runReport();
}

/// A diagnostic produced by a completed local operation, such as backup or
/// restore. Operation diagnostics are separate from a full integrity scan so
/// an operation can report what it observed without triggering a scan.
final class OperationDiagnostic {
  const OperationDiagnostic({
    required this.id,
    required this.operation,
    required this.finding,
  });

  final String id;
  final String operation;
  final DataIntegrityFinding finding;
}

/// Persistence port for incidental, privacy-safe operation findings.
/// Implementations must not modify financial source tables.
abstract interface class OperationDiagnosticsStore {
  Future<void> record({
    required String operation,
    required List<DataIntegrityFinding> findings,
  });

  Future<List<OperationDiagnostic>> recent({int limit = 20});
}
