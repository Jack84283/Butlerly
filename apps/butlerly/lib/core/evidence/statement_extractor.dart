import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

enum StatementExtractionOutcome {
  noText,
  textWithoutCandidates,
  unresolvedEvidence,
  reconstructedCandidates,
  technicalOcrFailure,
}

enum StatementUnresolvedReason {
  unresolvedAmount,
  unresolvedDate,
  unresolvedDirection,
  unresolvedCurrency,
  ambiguousRow,
  unsupportedLayout,
  incompleteTransactionEvidence,
}

enum StatementColumnRole {
  transactionDate,
  postingDate,
  description,
  amount,
  debit,
  credit,
}

final class StatementColumn {
  const StatementColumn(this.role, this.left);
  final StatementColumnRole role;
  final double left;
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
    this.visualRowsIgnored = 0,
    this.nativeDiagnostics,
    this.technicalFailureCode,
    this.technicalFailureStage,
  });
  final int observationsRecognized,
      pagesProcessed,
      transactionRegionsDetected,
      visualRowsReconstructed,
      candidatesReconstructed,
      unresolvedCandidates,
      lowConfidenceCandidates,
      nonTransactionObservationsIgnored,
      visualRowsIgnored;
  final NativeOcrDiagnostics? nativeDiagnostics;
  final String? technicalFailureCode, technicalFailureStage;
}

final class StatementExtractionContext {
  const StatementExtractionContext({
    this.institution,
    this.maskedAccountIdentifier,
    this.periodStart,
    this.periodEnd,
    this.defaultCurrency,
    this.columns = const [],
    this.profile,
  });
  final String? institution, maskedAccountIdentifier, defaultCurrency;
  final DateTime? periodStart, periodEnd;
  final List<StatementColumn> columns;
  final StatementLayoutProfile? profile;
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

  /// Counts and enum values only: safe to share from a debug device run.
  String get debugSummary {
    final diagnostic = diagnostics;
    final native = diagnostic?.nativeDiagnostics;
    return [
      'OCR: ${diagnostic?.observationsRecognized ?? 0} observations',
      if (native != null)
        'Native: ${native.visionObservationsRecognized ?? native.observationsRecognized} Vision observations, '
            '${native.observationsRecognized} channel observations, '
            '${native.recognizedLineCount} lines, '
            '${native.observationsWithBounds} bounded',
      if (native?.pixelWidth != null)
        'Image: ${native!.pixelWidth}x${native.pixelHeight}, '
            'orientation ${native.orientation}',
      if (native?.confidenceAverage != null)
        'OCR confidence: ${native!.confidenceMinimum?.toStringAsFixed(3)} / '
            '${native.confidenceAverage?.toStringAsFixed(3)} / '
            '${native.confidenceMaximum?.toStringAsFixed(3)} (min/avg/max)',
      'Visual rows: ${diagnostic?.visualRowsReconstructed ?? 0}',
      'Candidates: ${rows.length}',
      'Unresolved: ${diagnostic?.unresolvedCandidates ?? 0}',
      'Ignored: ${diagnostic?.visualRowsIgnored ?? 0} rows, '
          '${diagnostic?.nonTransactionObservationsIgnored ?? 0} observations',
      'Outcome: ${outcome.name}',
      if (diagnostic?.technicalFailureStage != null)
        'Failure stage: ${diagnostic!.technicalFailureStage}; '
            'code: ${diagnostic.technicalFailureCode}',
    ].join('\n');
  }
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
  final String? description, amount, currency, direction;
  final StatementUnresolvedReason? unresolvedReason;
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
    try {
      final result = await ocr.recognizeStatement(path);
      return fromObservations(
        result.rawText,
        result.observations,
        nativeDiagnostics: result.nativeDiagnostics,
      );
    } on LocalOcrException catch (error) {
      return StatementExtraction(
        rawText: '',
        rows: const [],
        outcome: StatementExtractionOutcome.technicalOcrFailure,
        diagnostics: StatementExtractionDiagnostics(
          observationsRecognized: 0,
          pagesProcessed: 0,
          transactionRegionsDetected: 0,
          visualRowsReconstructed: 0,
          candidatesReconstructed: 0,
          unresolvedCandidates: 0,
          lowConfidenceCandidates: 0,
          nonTransactionObservationsIgnored: 0,
          technicalFailureCode: error.code,
          technicalFailureStage: error.stage,
        ),
      );
    }
  }

  static StatementExtraction fromObservations(
    String text,
    List<OcrObservation> observations, {
    NativeOcrDiagnostics? nativeDiagnostics,
  }) {
    final context = _context(text, observations);
    final source = observations.isEmpty
        ? _lineObservations(text)
        : observations;
    final ambiguousGeometry = <OcrObservation>{};
    final visualRows = _reconstructRows(_groupRows(source, ambiguousGeometry));
    final rows = <StatementExtractedRow>[];
    var ignored = 0;
    var ignoredRows = 0;
    for (final row in visualRows) {
      final parsed = _parseVisualRow(
        row,
        context,
        ambiguousGeometry: row.any(ambiguousGeometry.contains),
      );
      if (parsed != null) {
        rows.add(parsed);
      } else if (_looksTransactionLike(
        row.map((value) => value.text).join(' '),
      )) {
        rows.add(
          StatementExtractedRow(
            originalText: row.map((value) => value.text).join(' '),
            confidence: _rowConfidence(row) * .7,
            unresolvedReason:
                StatementUnresolvedReason.incompleteTransactionEvidence,
            sourceObservationIndexes: row.map((value) => value.order).toList(),
          ),
        );
      } else {
        ignored += row.length;
        ignoredRows++;
      }
    }
    final reconstructed = rows.where((row) => !row.isUnresolved).length;
    final unresolved = rows.where((row) => row.isUnresolved).length;
    final hasText =
        text.trim().isNotEmpty ||
        source.any((observation) => observation.text.trim().isNotEmpty);
    final outcome = !hasText
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
        observationsRecognized: observations.length,
        pagesProcessed: source.map((value) => value.pageIndex).toSet().length,
        transactionRegionsDetected: visualRows.isEmpty ? 0 : 1,
        visualRowsReconstructed: visualRows.length,
        candidatesReconstructed: reconstructed,
        unresolvedCandidates: unresolved,
        lowConfidenceCandidates: rows
            .where((row) => (row.confidence ?? 0) <= .5)
            .length,
        nonTransactionObservationsIgnored: ignored,
        visualRowsIgnored: ignoredRows,
        nativeDiagnostics: nativeDiagnostics,
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

  static List<List<OcrObservation>> _groupRows(
    List<OcrObservation> input,
    Set<OcrObservation> ambiguous,
  ) {
    final groups = <List<OcrObservation>>[];
    final slopes = {
      for (final page in input.map((value) => value.pageIndex).toSet())
        page: _pageSlope(
          input.where((value) => value.pageIndex == page).toList(),
        ),
    };
    double position(OcrObservation value) =>
        value.top - (slopes[value.pageIndex]?.slope ?? 0) * value.left;
    final sorted = [...input]
      ..sort(
        (a, b) => a.pageIndex != b.pageIndex
            ? a.pageIndex.compareTo(b.pageIndex)
            : position(a).compareTo(position(b)),
      );
    for (final observation in sorted) {
      if (observation.text.trim().isEmpty) {
        continue;
      }
      // Compare vertical positions after removing the page's measured skew.
      // Missing fields must not make an older row steal a newer row's value.
      final compatibleGroups =
          <({List<OcrObservation> row, double distance})>[];
      for (final group in groups) {
        if (group.first.pageIndex != observation.pageIndex ||
            group.any((value) => _repeatsColumn(value, observation))) {
          continue;
        }
        final center =
            group.map(position).reduce((a, b) => a + b) / group.length;
        final distance = (center - position(observation)).abs();
        final height = group
            .map((value) => value.height)
            .fold(observation.height, (a, b) => a.max(b));
        final tolerance = height == 0 ? .08 : height * 1.2;
        if (distance <= tolerance) {
          compatibleGroups.add((row: group, distance: distance));
        }
      }
      compatibleGroups.sort((a, b) => a.distance.compareTo(b.distance));
      final compatible = compatibleGroups.firstOrNull?.row;
      if (compatibleGroups.length > 1 &&
          (compatibleGroups[1].distance - compatibleGroups[0].distance).abs() <
              observation.height * .2) {
        // Retain the source fragment, but do not publish guessed financial
        // fields for either of the nearly equally plausible associations.
        ambiguous.addAll(compatibleGroups[0].row);
        ambiguous.addAll(compatibleGroups[1].row);
        ambiguous.add(observation);
      }
      if (compatible == null) {
        groups.add([observation]);
      } else {
        compatible.add(observation);
      }
    }
    for (final entry in slopes.entries) {
      if (!entry.value.uncertain) continue;
      for (final row in groups.where(
        (row) => row.first.pageIndex == entry.key,
      )) {
        ambiguous.addAll(row);
      }
    }
    // Reconsider isolated fragments only after all neighboring rows exist.
    // This prevents an early date/amount from claiming a row before its real
    // neighbors have arrived, while allowing bounded perspective residuals.
    for (final fragment in [...groups]) {
      final text = fragment.map((value) => value.text).join(' ');
      if (!groups.contains(fragment) ||
          _isContextLine(text) ||
          _looksTransactionLike(text)) {
        continue;
      }
      final center =
          fragment.map(position).reduce((a, b) => a + b) / fragment.length;
      final targets = <({List<OcrObservation> row, double distance})>[];
      for (final row in groups) {
        if (identical(row, fragment) ||
            row.first.pageIndex != fragment.first.pageIndex ||
            _isContextLine(row.map((value) => value.text).join(' ')) ||
            row.any((a) => fragment.any((b) => _repeatsColumn(a, b)))) {
          continue;
        }
        final distance =
            (row.map(position).reduce((a, b) => a + b) / row.length - center)
                .abs();
        final height = [
          ...row,
          ...fragment,
        ].map((value) => value.height).reduce((a, b) => a.max(b));
        if (height > 0 && distance <= height * 2) {
          targets.add((row: row, distance: distance));
        }
      }
      targets.sort((a, b) => a.distance.compareTo(b.distance));
      if (targets.isEmpty) continue;
      if (targets.length > 1 &&
          targets[1].distance - targets[0].distance <
              fragment.first.height * .2) {
        ambiguous.addAll(targets[0].row);
        ambiguous.addAll(targets[1].row);
        ambiguous.addAll(fragment);
      }
      targets.first.row.addAll(fragment);
      groups.remove(fragment);
    }
    // A sparse outer column cannot establish which neighboring row it belongs
    // to by extrapolating a slope measured only between inner columns. Keep
    // those nearby candidates unresolved instead of asserting a guessed date
    // or amount. Complete columns still use their directly measured span.
    for (final observation in sorted) {
      final geometry = slopes[observation.pageIndex]!;
      final outsideSpan = observation.left < geometry.left
          ? geometry.left - observation.left
          : (observation.left - geometry.right).max(0);
      if (observation.height <= 0 ||
          outsideSpan * geometry.slope.abs() <= observation.height ||
          _isContextLine(observation.text) ||
          _detachedMarker.hasMatch(observation.text.trim())) {
        continue;
      }
      for (final row in groups) {
        if (row.first.pageIndex != observation.pageIndex) continue;
        final center = row.map(position).reduce((a, b) => a + b) / row.length;
        if ((center - position(observation)).abs() <= observation.height * 3) {
          ambiguous.addAll(row);
        }
      }
    }
    for (final group in groups) {
      group.sort((a, b) => a.left.compareTo(b.left));
    }
    groups.sort(
      (a, b) => a.first.pageIndex != b.first.pageIndex
          ? a.first.pageIndex.compareTo(b.first.pageIndex)
          : (a.map(position).reduce((a, b) => a + b) / a.length).compareTo(
              b.map(position).reduce((a, b) => a + b) / b.length,
            ),
    );
    return groups;
  }

  static ({double slope, double left, double right, bool uncertain}) _pageSlope(
    List<OcrObservation> observations,
  ) {
    final columns = <List<OcrObservation>>[];
    final sorted =
        observations
            .where(
              (value) =>
                  value.height > 0 &&
                  value.width > 0 &&
                  !_isContextLine(value.text) &&
                  !_detachedMarker.hasMatch(value.text.trim()),
            )
            .toList()
          ..sort((a, b) => a.left.compareTo(b.left));
    for (final observation in sorted) {
      final column = columns.lastOrNull;
      if (column == null ||
          (observation.left - column.first.left).abs() > .08) {
        columns.add([observation]);
      } else {
        column.add(observation);
      }
    }
    final slopes = <double>[];
    var minimumLeft = 1.0;
    var maximumLeft = 0.0;
    for (var i = 0; i < columns.length; i++) {
      final left = [...columns[i]]..sort((a, b) => a.top.compareTo(b.top));
      for (final column in columns.skip(i + 1)) {
        if (column.length != left.length) continue;
        final right = [...column]..sort((a, b) => a.top.compareTo(b.top));
        for (var index = 0; index < left.length; index++) {
          final width = right[index].left - left[index].left;
          if (width < .2) continue;
          final slope = (right[index].top - left[index].top) / width;
          if (slope.abs() <= .1) {
            slopes.add(slope);
            minimumLeft = minimumLeft.min(left[index].left);
            maximumLeft = maximumLeft.max(right[index].left);
          }
        }
      }
    }
    if (slopes.isEmpty) {
      return (slope: 0, left: 0, right: 1, uncertain: false);
    }
    slopes.sort();
    final unequalColumnCounts =
        columns.map((column) => column.length).toSet().length > 1;
    return (
      slope: slopes[slopes.length ~/ 2],
      left: minimumLeft,
      right: maximumLeft,
      uncertain:
          unequalColumnCounts && slopes.any((value) => value.abs() > .01),
    );
  }

  static final _detachedMarker = RegExp(
    r'^(?:[$€£+\-]|CR|CREDIT|DR|DEBIT|REFUND)$',
    caseSensitive: false,
  );

  static bool _repeatsColumn(OcrObservation a, OcrObservation b) {
    if (_detachedMarker.hasMatch(a.text.trim()) ||
        _detachedMarker.hasMatch(b.text.trim())) {
      return false;
    }
    final overlap =
        (a.left + a.width).min(b.left + b.width) - a.left.max(b.left);
    return a.width > 0 && b.width > 0 && overlap >= a.width.min(b.width) * .5;
  }

  static List<List<OcrObservation>> _reconstructRows(
    List<List<OcrObservation>> groups,
  ) {
    final output = <List<OcrObservation>>[];
    List<OcrObservation>? pending;
    var pendingPage = -1;
    for (final group in groups) {
      final text = group.map((value) => value.text).join(' ');
      if (pending != null && group.first.pageIndex != pendingPage) {
        output.add(pending);
        pending = null;
      }
      if (_isContextLine(text)) {
        if (pending != null) {
          output.add(pending);
          pending = null;
        }
        output.add(group);
        continue;
      }
      final startsRow = _datePattern.hasMatch(text);
      if (startsRow) {
        if (pending != null) output.add(pending);
        pending = [...group];
        pendingPage = group.first.pageIndex;
      } else if (pending != null &&
          (_hasFormattedAmount(pending.map((value) => value.text).join(' ')) ||
              _hasDescription(pending.map((value) => value.text).join(' '))) &&
          _looksTransactionLike(text)) {
        // Complementary missing fields are not evidence that independent
        // transaction-like rows belong together. Only date-only anchors can
        // absorb a following merchant-and-amount group.
        output.add(pending);
        pending = null;
        output.add(group);
      } else if (pending != null &&
          (_hasDescription(text) || _hasFormattedAmount(text))) {
        pending.addAll(group);
      } else if (pending != null) {
        output.add(pending);
        pending = null;
        output.add(group);
      } else {
        // A damaged date must not erase an otherwise plausible transaction.
        output.add(group);
      }
    }
    if (pending != null) output.add(pending);
    return output;
  }

  static bool _isContextLine(String text) {
    // NEW BALANCE can be a merchant in a dated transaction, unlike explicit
    // balance-forward/opening/closing summary labels, which stay excluded.
    if (_datePattern.matchAsPrefix(text.trimLeft()) == null &&
        RegExp(r'\bnew\s+balance\b', caseSensitive: false).hasMatch(text)) {
      return true;
    }
    if (RegExp(
      r'\b(?:statement\s+period|billing\s+period|transaction\s+date|posting\s+date|balance\s+forward|previous\s+balance|statement\s+balance|opening\s+balance|closing\s+balance|minimum\s+payment|account\s+(?:number|summary)|payment\s+due)\b|^\s*(?:date|description|amount|debit|credit|total|balance)\s*$|^\s*(?:balance|total\s+(?:fees|interest|payments|credits|purchases))\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return true;
    }
    return !_datePattern.hasMatch(text) &&
        !_hasFormattedAmount(text) &&
        RegExp(
              r'\b(?:date|description|amount|debit|credit)\b',
              caseSensitive: false,
            ).allMatches(text).length >=
            2;
  }

  static StatementExtractedRow? _parseVisualRow(
    List<OcrObservation> row,
    StatementExtractionContext context, {
    bool ambiguousGeometry = false,
  }) {
    final originalText = row.map((value) => value.text.trim()).join(' ');
    if (!_looksTransactionLike(originalText)) return null;
    final text = originalText.replaceAllMapped(
      RegExp(r'([$€£])\s+(?=\d)'),
      (match) => match.group(1)!,
    );
    final dates = _datePattern
        .allMatches(text)
        .map((match) => match.group(0)!)
        .toList();
    final amountSource = dates.fold(
      text,
      (value, date) => value.replaceFirst(date, ''),
    );
    final amounts = RegExp(
      r'(?<!\d)([+\-]?\(?\$?\d+(?:,\d{3})*(?:\.\d{2})?\)?)(?:\s*(CREDIT|CR|DEBIT|DR|REFUND)\b)?(?!\d)',
      caseSensitive: false,
    ).allMatches(amountSource).toList();
    final date = dates.isEmpty ? null : _interpretDate(dates.first, context);
    final posting = dates.length > 1 ? _interpretDate(dates[1], context) : null;
    final amountMatch = _selectAmount(amounts, row, context);
    final rawAmount = amountMatch?.group(1);
    final prefixMarker = amountMatch == null || amountMatch.group(2) != null
        ? null
        : RegExp(
            r'\b(CREDIT|CR|DEBIT|DR|REFUND)\s*$',
            caseSensitive: false,
          ).firstMatch(amountSource.substring(0, amountMatch.start));
    final marker = (amountMatch?.group(2) ?? prefixMarker?.group(1))
        ?.toUpperCase();
    final explicitPositive = rawAmount?.startsWith('+') ?? false;
    final negative =
        (rawAmount?.startsWith('-') ?? false) ||
        (rawAmount?.startsWith('(') ?? false) ||
        marker == 'DR' ||
        marker == 'DEBIT';
    final direction = marker == 'REFUND'
        ? TransactionDirection.refund.name
        : negative && marker != 'CR' && marker != 'CREDIT'
        ? TransactionDirection.expense.name
        : explicitPositive || marker == 'CR' || marker == 'CREDIT'
        ? TransactionDirection.income.name
        : null;
    final description =
        (amountMatch == null
                ? amountSource
                : amountSource.replaceRange(
                    prefixMarker?.start ?? amountMatch.start,
                    amountMatch.end,
                    '',
                  ))
            .replaceAll(
              RegExp(r'\b(?:USD|EUR|GBP|CNY)\b', caseSensitive: false),
              '',
            )
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    final hasDescription = _hasDescription(description);
    final confidence =
        _rowConfidence(row) *
        (date == null ? .55 : 1) *
        (hasDescription ? 1 : .65);
    final normalizedAmount = rawAmount
        ?.replaceAll(RegExp(r'[+,()]'), '')
        .replaceFirst('\$', '');
    final amount = normalizedAmount == null
        ? null
        : DecimalValue.parse(normalizedAmount.replaceFirst('-', '')).toString();
    return StatementExtractedRow(
      originalText: originalText,
      date: ambiguousGeometry ? null : date,
      postingDate: ambiguousGeometry ? null : posting,
      description: hasDescription ? description : null,
      amount: ambiguousGeometry ? null : amount,
      currency: _currency(text) ?? context.defaultCurrency,
      direction: ambiguousGeometry ? null : direction,
      confidence:
          ambiguousGeometry || date == null || amount == null || !hasDescription
          ? confidence.min(.5)
          : confidence,
      unresolvedReason: ambiguousGeometry
          ? StatementUnresolvedReason.ambiguousRow
          : amount == null
          ? StatementUnresolvedReason.unresolvedAmount
          : date == null
          ? StatementUnresolvedReason.unresolvedDate
          : !hasDescription
          ? StatementUnresolvedReason.incompleteTransactionEvidence
          : null,
      sourceObservationIndexes: row.map((value) => value.order).toList(),
    );
  }

  static RegExpMatch? _selectAmount(
    List<RegExpMatch> matches,
    List<OcrObservation> row,
    StatementExtractionContext context,
  ) {
    matches = matches.where((match) {
      final token = match.group(0)!;
      return RegExp(r'[.,$()+\-]').hasMatch(token) ||
          match.group(2) != null ||
          context.columns.any(
            (column) =>
                (column.role == StatementColumnRole.amount ||
                    column.role == StatementColumnRole.debit ||
                    column.role == StatementColumnRole.credit) &&
                row.any(
                  (observation) =>
                      observation.text.trim() == token.trim() &&
                      (observation.left - column.left).abs() <= .12,
                ),
          );
    }).toList();
    if (matches.length == 1) return matches.single;
    final amountColumn = context.columns
        .where(
          (column) =>
              column.role == StatementColumnRole.amount ||
              column.role == StatementColumnRole.debit ||
              column.role == StatementColumnRole.credit,
        )
        .firstOrNull;
    if (amountColumn == null) {
      final formatted = matches
          .where(
            (match) =>
                match.group(0)!.contains('.') ||
                match.group(0)!.contains(',') ||
                match.group(0)!.contains('\$') ||
                match.group(0)!.contains('('),
          )
          .toList();
      return formatted.length == 1 ? formatted.single : null;
    }
    final positioned = <({RegExpMatch match, double distance})>[];
    for (final match in matches) {
      // Currency symbols and debit/credit markers can be separate Vision
      // observations. Match the numeric component, not the joined row token.
      final number = match.group(1)!.replaceAll(r'$', '');
      final component = RegExp(
        r'(?<![\d.])' + RegExp.escape(number) + r'(?![\d.])',
      );
      final observations = row.where((value) => component.hasMatch(value.text));
      for (final observation in observations) {
        positioned.add((
          match: match,
          distance: (observation.left - amountColumn.left).abs(),
        ));
      }
    }
    positioned.sort((a, b) => a.distance.compareTo(b.distance));
    if (positioned.length > 1 &&
        positioned[0].distance == positioned[1].distance) {
      return null;
    }
    return positioned.firstOrNull?.match;
  }

  static double _rowConfidence(List<OcrObservation> row) =>
      row.map((value) => value.confidence).reduce((a, b) => a + b) / row.length;
  static final _datePattern = RegExp(
    r'\b(?:\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}(?:[-/]\d{2,4})?)\b',
  );

  static bool _looksTransactionLike(String text) {
    if (_isContextLine(text)) return false;
    final signals = [
      _datePattern.hasMatch(text),
      _hasFormattedAmount(text),
      _hasDescription(text),
    ];
    return signals.where((signal) => signal).length >= 2;
  }

  static bool _hasFormattedAmount(String text) =>
      RegExp(r'\$?\s*\d+(?:,\d{3})*[.,]\d{2}').hasMatch(text);

  static bool _hasDescription(String text) =>
      RegExp(r'\p{L}', unicode: true).hasMatch(text);

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
    if (context.periodEnd!.year - context.periodStart!.year > 1) return null;
    final candidates = <DateTime>[];
    for (final year in {context.periodStart!.year, context.periodEnd!.year}) {
      final candidate = DateTime.tryParse(
        '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
      );
      if (candidate != null &&
          candidate.year == year &&
          candidate.month == month &&
          candidate.day == day &&
          !candidate.isBefore(context.periodStart!) &&
          !candidate.isAfter(context.periodEnd!)) {
        candidates.add(candidate);
      }
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  static StatementExtractionContext _context(
    String text,
    List<OcrObservation> observations,
  ) {
    final columns = _columns(observations);
    return StatementExtractionContext(
      institution: _institution(text),
      maskedAccountIdentifier: _maskedAccountIdentifier(text),
      periodStart: _period(text, true),
      periodEnd: _period(text, false),
      defaultCurrency: _currency(text),
      columns: columns,
      profile: _profile(text),
    );
  }

  static StatementLayoutProfile? _profile(String text) =>
      RegExp(
        r'\b(?:purchase|transaction|posting|post)\s+date\b',
        caseSensitive: false,
      ).hasMatch(text)
      ? const StatementLayoutProfile(
          id: 'generic-date-posting-amount',
          version: 1,
        )
      : null;

  static List<StatementColumn> _columns(List<OcrObservation> observations) {
    final output = <StatementColumn>[];
    for (final observation in observations) {
      final value = observation.text
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final role =
          value.contains('transaction date') || value.contains('purchase date')
          ? StatementColumnRole.transactionDate
          : RegExp(r'^post(?:ing)?\s+date$').hasMatch(value)
          ? StatementColumnRole.postingDate
          : value == 'date'
          ? StatementColumnRole.transactionDate
          : value.contains('description') || value.contains('merchant')
          ? StatementColumnRole.description
          : value == 'amount'
          ? StatementColumnRole.amount
          : value == 'debit'
          ? StatementColumnRole.debit
          : value == 'credit'
          ? StatementColumnRole.credit
          : null;
      if (role != null) output.add(StatementColumn(role, observation.left));
    }
    return output;
  }

  static DateTime? _period(String text, bool first) {
    const date = r'(\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[/-]\d{1,2}[/-]\d{2,4})';
    final match = RegExp(
      r'\b(?:statement|billing)\s+period\s*:?\s*' +
          date +
          r'\s*(?:-|–|to|through)\s*' +
          date,
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) {
      if (!RegExp(
        r'\b(?:statement|billing|period|cycle|from|through)\b',
        caseSensitive: false,
      ).hasMatch(text)) {
        return null;
      }
      final fallback = RegExp(
        r'\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\s*(?:-|–|to|through)\s*'
        r'(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\b',
        caseSensitive: false,
      ).firstMatch(text);
      if (fallback == null) return null;
      final start = parseDate(fallback.group(1)!);
      final end = parseDate(fallback.group(2)!);
      if (start == null || end == null || end.isBefore(start)) return null;
      return first ? start : end;
    }
    final start = parseDate(match.group(1)!);
    final end = parseDate(match.group(2)!);
    if (start == null || end == null || end.isBefore(start)) return null;
    return first ? start : end;
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
    if (RegExp(r'\bEUR\b', caseSensitive: false).hasMatch(text) ||
        text.contains('€')) {
      return 'EUR';
    }
    if (RegExp(r'\bGBP\b', caseSensitive: false).hasMatch(text) ||
        text.contains('£')) {
      return 'GBP';
    }
    if (RegExp(r'\bUSD\b|US\$', caseSensitive: false).hasMatch(text)) {
      return 'USD';
    }
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
