import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

enum StatementExtractionOutcome {
  noText,
  textWithoutCandidates,
  unresolvedEvidence,
  reconstructedCandidates,
}

final class StatementExtractionDiagnostics {
  const StatementExtractionDiagnostics({
    required this.observationsRecognized,
    required this.pagesProcessed,
    required this.transactionRegionsDetected,
    required this.visualRowsReconstructed,
    required this.candidatesReconstructed,
    required this.unresolvedCandidates,
    required this.lowConfidenceCandidates,
    required this.nonTransactionObservationsIgnored,
  });
  final int observationsRecognized,
      pagesProcessed,
      transactionRegionsDetected,
      visualRowsReconstructed,
      candidatesReconstructed,
      unresolvedCandidates,
      lowConfidenceCandidates,
      nonTransactionObservationsIgnored;
}

final class StatementExtractionContext {
  const StatementExtractionContext({
    this.institution,
    this.maskedAccountIdentifier,
    this.periodStart,
    this.periodEnd,
    this.defaultCurrency,
  });
  final String? institution, maskedAccountIdentifier, defaultCurrency;
  final DateTime? periodStart, periodEnd;
}

final class StatementExtraction {
  const StatementExtraction({
    required this.rawText,
    required this.rows,
    this.institution,
    this.maskedAccountIdentifier,
    this.context = const StatementExtractionContext(),
    this.outcome = StatementExtractionOutcome.textWithoutCandidates,
    this.diagnostics,
  });
  final String rawText;
  final List<StatementExtractedRow> rows;
  final String? institution, maskedAccountIdentifier;
  final StatementExtractionContext context;
  final StatementExtractionOutcome outcome;
  final StatementExtractionDiagnostics? diagnostics;
}

final class StatementExtractedRow {
  const StatementExtractedRow({
    required this.originalText,
    this.date,
    this.postingDate,
    this.description,
    this.amount,
    this.currency,
    this.direction,
    this.confidence,
    this.unresolvedReason,
    this.sourceObservationIndexes = const [],
  });
  final String originalText;
  final DateTime? date, postingDate;
  final String? description, amount, currency, direction, unresolvedReason;
  final double? confidence;
  final List<int> sourceObservationIndexes;
  bool get isUnresolved => unresolvedReason != null;
}

/// Versioned, data-free hints for future issuer-specific tuning.
final class StatementLayoutProfile {
  const StatementLayoutProfile({required this.id, required this.version});
  final String id;
  final int version;
}

/// Offline, layout-aware extraction backed by on-device OCR.
final class LocalStatementExtractor {
  const LocalStatementExtractor([this.ocr = const LocalOcrService()]);
  final LocalOcrService ocr;

  Future<StatementExtraction> extract(String path) async {
    final result = await ocr.recognize(path);
    return fromObservations(result.rawText, result.observations);
  }

  static StatementExtraction fromObservations(
    String text,
    List<OcrObservation> observations,
  ) {
    final context = _context(text);
    final source = observations.isEmpty
        ? _lineObservations(text)
        : observations;
    final visualRows = _reconstructRows(_groupRows(source));
    final rows = <StatementExtractedRow>[];
    var ignored = 0;
    for (final row in visualRows) {
      final parsed = _parseVisualRow(row, context);
      if (parsed != null) {
        rows.add(parsed);
      } else if (_looksTransactionLike(
        row.map((value) => value.text).join(' '),
      )) {
        rows.add(
          StatementExtractedRow(
            originalText: row.map((value) => value.text).join(' '),
            confidence: _rowConfidence(row) * .7,
            unresolvedReason: 'Transaction-like evidence needs review',
            sourceObservationIndexes: row.map((value) => value.order).toList(),
          ),
        );
      } else {
        ignored++;
      }
    }
    final reconstructed = rows.where((row) => !row.isUnresolved).length;
    final unresolved = rows.where((row) => row.isUnresolved).length;
    final outcome = text.trim().isEmpty
        ? StatementExtractionOutcome.noText
        : rows.isEmpty
        ? StatementExtractionOutcome.textWithoutCandidates
        : unresolved > 0 && reconstructed == 0
        ? StatementExtractionOutcome.unresolvedEvidence
        : StatementExtractionOutcome.reconstructedCandidates;
    return StatementExtraction(
      rawText: text,
      rows: rows,
      institution: context.institution,
      maskedAccountIdentifier: context.maskedAccountIdentifier,
      context: context,
      outcome: outcome,
      diagnostics: StatementExtractionDiagnostics(
        observationsRecognized: source.length,
        pagesProcessed: source.map((value) => value.pageIndex).toSet().length,
        transactionRegionsDetected: visualRows.isEmpty ? 0 : 1,
        visualRowsReconstructed: visualRows.length,
        candidatesReconstructed: reconstructed,
        unresolvedCandidates: unresolved,
        lowConfidenceCandidates: rows
            .where((row) => (row.confidence ?? 0) <= .5)
            .length,
        nonTransactionObservationsIgnored: ignored,
      ),
    );
  }

  static List<StatementExtractedRow> parse(
    String text, [
    List<OcrObservation> observations = const [],
  ]) => fromObservations(text, observations).rows;

  static List<OcrObservation> _lineObservations(String text) => text
      .split(RegExp(r'\r?\n'))
      .asMap()
      .entries
      .where((entry) => entry.value.trim().isNotEmpty)
      .map(
        (entry) => OcrObservation(
          text: entry.value,
          confidence: .5,
          left: 0,
          top: entry.key.toDouble(),
          width: 1,
          height: 0,
          order: entry.key,
        ),
      )
      .toList(growable: false);

  static List<List<OcrObservation>> _groupRows(List<OcrObservation> input) {
    final sorted = [...input]
      ..sort(
        (a, b) => a.pageIndex != b.pageIndex
            ? a.pageIndex.compareTo(b.pageIndex)
            : a.top.compareTo(b.top),
      );
    final groups = <List<OcrObservation>>[];
    for (final observation in sorted) {
      if (observation.text.trim().isEmpty) {
        continue;
      }
      final last = groups.lastOrNull;
      if (last == null || !_sameRow(last.first, observation)) {
        groups.add([observation]);
      } else {
        last.add(observation);
      }
    }
    for (final group in groups) {
      group.sort((a, b) => a.left.compareTo(b.left));
    }
    return groups;
  }

  static List<List<OcrObservation>> _reconstructRows(
    List<List<OcrObservation>> groups,
  ) {
    final output = <List<OcrObservation>>[];
    List<OcrObservation>? pending;
    for (final group in groups) {
      final text = group.map((value) => value.text).join(' ');
      if (_isContextLine(text)) {
        continue;
      }
      final startsRow = RegExp(
        r'\b(?:\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}(?:[-/]\d{2,4})?)\b',
      ).hasMatch(text);
      if (startsRow) {
        if (pending != null) output.add(pending);
        pending = [...group];
      } else if (pending != null &&
          (RegExp(r'[A-Za-z]{2,}').hasMatch(text) ||
              RegExp(r'\$?\d+[.,]\d{2}').hasMatch(text))) {
        pending.addAll(group);
      } else if (pending != null) {
        output.add(pending);
        pending = null;
      }
    }
    if (pending != null) output.add(pending);
    return output;
  }

  static bool _isContextLine(String text) => RegExp(
    r'\b(?:statement\s+period|transaction\s+date|posting\s+date|balance\s+forward|previous\s+balance|account)\b',
    caseSensitive: false,
  ).hasMatch(text);

  static bool _sameRow(OcrObservation a, OcrObservation b) {
    if (a.pageIndex != b.pageIndex) return false;
    if (a.height == 0 || b.height == 0) return (a.top - b.top).abs() < .08;
    final overlap = (a.top + a.height).min(b.top + b.height) - a.top.max(b.top);
    return overlap >= a.height.min(b.height) * .2 ||
        ((a.top + a.height / 2) - (b.top + b.height / 2)).abs() <=
            a.height.max(b.height) * .65;
  }

  static StatementExtractedRow? _parseVisualRow(
    List<OcrObservation> row,
    StatementExtractionContext context,
  ) {
    final text = row.map((value) => value.text.trim()).join(' ');
    final dates = RegExp(
      r'\b(?:\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}(?:[-/]\d{2,4})?)\b',
    ).allMatches(text).map((match) => match.group(0)!).toList();
    if (dates.isEmpty) return null;
    final amountSource = dates.fold(
      text,
      (value, date) => value.replaceFirst(date, ''),
    );
    final amounts = RegExp(
      r'(?<!\d)([+\-]?\(?\$?\d+(?:,\d{3})*(?:\.\d{2})?\)?)(?:\s*(CR|CREDIT|DR|DEBIT))?(?!\d)',
      caseSensitive: false,
    ).allMatches(amountSource).toList();
    if (amounts.isEmpty) return null;
    final date = _interpretDate(dates.first, context);
    final posting = dates.length > 1 ? _interpretDate(dates[1], context) : null;
    final amountMatch = amounts.last;
    final rawAmount = amountMatch.group(1)!;
    final marker = amountMatch.group(2)?.toUpperCase();
    final explicitPositive = rawAmount.startsWith('+');
    final negative =
        rawAmount.startsWith('-') ||
        rawAmount.startsWith('(') ||
        marker == 'DR' ||
        marker == 'DEBIT';
    final direction = negative && marker != 'CR' && marker != 'CREDIT'
        ? TransactionDirection.expense.name
        : explicitPositive || marker == 'CR' || marker == 'CREDIT'
        ? TransactionDirection.income.name
        : null;
    final description = text
        .replaceFirst(dates.first, '')
        .replaceFirst(dates.length > 1 ? dates[1] : '', '')
        .replaceFirst(amountMatch.group(0)!, '')
        .replaceAll(
          RegExp(r'\b(?:USD|EUR|GBP|CNY)\b', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final confidence =
        _rowConfidence(row) *
        (date == null ? .55 : 1) *
        (description.length < 2 ? .65 : 1);
    final normalizedAmount = rawAmount
        .replaceAll(RegExp(r'[+,()]'), '')
        .replaceFirst('\$', '');
    final amount = DecimalValue.parse(
      normalizedAmount.replaceFirst('-', ''),
    ).toString();
    return StatementExtractedRow(
      originalText: text,
      date: date,
      postingDate: posting,
      description: description.isEmpty ? null : description,
      amount: amount,
      currency: _currency(text) ?? context.defaultCurrency,
      direction: direction,
      confidence: confidence,
      unresolvedReason: date == null || description.isEmpty
          ? 'Some transaction fields could not be interpreted'
          : null,
      sourceObservationIndexes: row.map((value) => value.order).toList(),
    );
  }

  static double _rowConfidence(List<OcrObservation> row) =>
      row.map((value) => value.confidence).reduce((a, b) => a + b) / row.length;
  static bool _looksTransactionLike(String text) =>
      !RegExp(
        r'\b(?:balance\s+forward|previous\s+balance|statement\s+balance|statement\s+period|account)\b',
        caseSensitive: false,
      ).hasMatch(text) &&
      (RegExp(r'\d{1,2}[/-]\d{1,2}').hasMatch(text) ||
          RegExp(r'\$?\d+[.,]\d{2}').hasMatch(text)) &&
      RegExp(r'[A-Za-z]{2,}').hasMatch(text);

  static DateTime? _interpretDate(
    String value,
    StatementExtractionContext context,
  ) {
    final parsed = parseDate(value);
    if (parsed != null) return parsed;
    final parts = value.replaceAll('/', '-').split('-');
    if (parts.length != 2 ||
        context.periodStart == null ||
        context.periodEnd == null) {
      return null;
    }
    final month = int.tryParse(parts[0]), day = int.tryParse(parts[1]);
    if (month == null || day == null) return null;
    for (final year in [context.periodStart!.year, context.periodEnd!.year]) {
      final candidate = DateTime.tryParse(
        '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
      );
      if (candidate != null &&
          !candidate.isBefore(context.periodStart!) &&
          !candidate.isAfter(context.periodEnd!)) {
        return candidate;
      }
    }
    return null;
  }

  static StatementExtractionContext _context(String text) =>
      StatementExtractionContext(
        institution: _institution(text),
        maskedAccountIdentifier: _maskedAccountIdentifier(text),
        periodStart: _period(text, true),
        periodEnd: _period(text, false),
        defaultCurrency: _currency(text),
      );
  static DateTime? _period(String text, bool first) {
    final matches = RegExp(
      r'\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\b',
    ).allMatches(text).toList();
    return matches.length < 2
        ? null
        : parseDate(matches[first ? 0 : 1].group(1)!);
  }

  static DateTime? parseDate(String input) {
    final parts = input.replaceAll('/', '-').split('-');
    if (parts.length != 3) return null;
    var year = int.tryParse(parts[0].length == 4 ? parts[0] : parts[2]);
    if (year != null && year < 100) year += 2000;
    final month = int.tryParse(parts[0].length == 4 ? parts[1] : parts[0]);
    final day = int.tryParse(parts[0].length == 4 ? parts[2] : parts[1]);
    if (year == null || month == null || day == null) return null;
    final value = DateTime.tryParse(
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
    );
    return value != null &&
            value.year == year &&
            value.month == month &&
            value.day == day
        ? value
        : null;
  }

  static String? _currency(String text) {
    final upper = text.toUpperCase();
    if (upper.contains('EUR') || text.contains('€')) return 'EUR';
    if (upper.contains('GBP') || text.contains('£')) return 'GBP';
    if (upper.contains('USD') || text.contains(r'\$')) return 'USD';
    return null;
  }

  static String? _maskedAccountIdentifier(String text) {
    final match = RegExp(
      r'(?:account|acct|card|ending(?:\s+in)?|last\s*4)[^\d]{0,20}(\d{4})(?!\d)',
      caseSensitive: false,
    ).firstMatch(text);
    return match == null ? null : '••••${match.group(1)}';
  }

  static String? _institution(String text) => RegExp(
    r'^(?:institution|bank|issuer)\s*[:\-]\s*(.+)$',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(text)?.group(1)?.trim();
}

extension on num {
  double min(num other) => this < other ? toDouble() : other.toDouble();
  double max(num other) => this > other ? toDouble() : other.toDouble();
}
