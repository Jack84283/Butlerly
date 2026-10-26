import 'ocr_contract.dart';

/// A row in a card statement's explicitly labeled transaction table.
final class StatementSectionTableRow {
  const StatementSectionTableRow({
    required this.originalText,
    required this.description,
    required this.amount,
    required this.date,
    required this.currency,
    required this.direction,
    required this.confidence,
    required this.sourceObservationIndexes,
  });

  final String originalText;
  final String? description, amount, currency, direction;
  final DateTime? date;
  final double confidence;
  final List<int> sourceObservationIndexes;
}

/// Present only when a transaction table has recognisable section boundaries.
/// Never merges narrative, rewards or fee observations into transaction rows.
final class StatementSectionTableResult {
  const StatementSectionTableResult({
    required this.rows,
    required this.regionsDetected,
    required this.ignoredObservationCount,
  });

  final List<StatementSectionTableRow> rows;
  final int regionsDetected, ignoredObservationCount;
}

/// A layout-aware alternative for credit-card statements containing separate
/// Purchases and Payments/Credits tables alongside unrelated page sections.
/// It uses OCR geometry and section headings, not bank-specific pixel offsets.
abstract final class StatementSectionTableInterpreter {
  static final _section = RegExp(
    r'(?:^|:\s*)(PAYMENTS\s+AND\s+CREDITS|PURCHASES)\s*$',
    caseSensitive: false,
  );
  static final _stop = RegExp(
    r'^(?:FEES\s+AND\s+INTEREST\s+CHARGED|'
    r'INTEREST\s+CHARGE\s+CALCULATION|'
    r'TOTAL\s+FEES\s+FOR\s+THIS\s+PERIOD|'
    r'ACCOUNT\s+SUMMARY)\b',
    caseSensitive: false,
  );
  static final _header = RegExp(
    r'^(?:TRANS\.?\s*DATE|DATE|AMOUNT|PAYMENTS\s+AND\s+CREDITS|'
    r'PURCHASES|TRANSACTIONS|VISIT\s+)',
    caseSensitive: false,
  );
  static final _shortDate = RegExp(r'^\s*(\d{1,2})/(\d{1,2})(?!\d)');
  static final _amount = RegExp(
    r'(?<!\d)([-−]?\s*\$?\s*\d+(?:,\d{3})*\.\d{2})(?!\d)',
  );

  static StatementSectionTableResult? interpret(
    String text,
    List<OcrObservation> observations, {
    required DateTime? periodStart,
    required DateTime? periodEnd,
    required String? defaultCurrency,
  }) {
    if (observations.isEmpty ||
        !observations.any((value) => value.width > 0 && value.height > 0)) {
      return null;
    }
    // Avoid routing generic one-column transactions through a specialized
    // parser unless explicit distinct card-statement sections are present.
    if (!RegExp(r'payments\s+and\s+credits', caseSensitive: false)
            .hasMatch(text) ||
        !RegExp(r'\bpurchases\b', caseSensitive: false).hasMatch(text)) {
      return null;
    }

    final rows = <StatementSectionTableRow>[];
    var sections = 0;
    var used = 0;

    for (final page in observations.map((value) => value.pageIndex).toSet()) {
      final onPage = observations
          .where((value) => value.pageIndex == page &&
              value.text.trim().isNotEmpty)
          .toList()
        ..sort((a, b) {
          final vertical = a.top.compareTo(b.top);
          return vertical != 0 ? vertical : a.left.compareTo(b.left);
        });
      final sectionHeadings = onPage.where((value) =>
          _section.hasMatch(value.text.trim()) && value.left < .65).toList();
      final transactionHeader = onPage.where((value) =>
          value.text.trim().toLowerCase() == 'transactions' &&
          value.left < .65).firstOrNull;
      final amountHeader = onPage.where((value) =>
          value.text.trim().toLowerCase() == 'amount' &&
          value.left > .4 && value.left < .75).firstOrNull;
      if (transactionHeader == null ||
          sectionHeadings.isEmpty ||
          amountHeader == null) {
        continue;
      }

      final rewards = onPage.where((value) =>
          RegExp(r'^rewards?\s+summary$', caseSensitive: false)
              .hasMatch(value.text.trim()) && value.left > .50).firstOrNull;
      // The transaction amount header is a measured right-column anchor.
      // The rewards heading supplies an independent boundary if present.
      final boundary = rewards == null
          ? (amountHeader.left + amountHeader.width + .06).clamp(.55, 1.0)
          : (rewards.left - .015).clamp(.55, 1.0);
      final left = onPage.where((value) =>
          value.left < boundary && value.top >= transactionHeader.top).toList();

      var active = '';
      var began = 0.0;
      for (var i = 0; i <= left.length; i++) {
        final observation = i < left.length ? left[i] : null;
        final value = observation?.text.trim() ?? '';
        final nextSection = _section.firstMatch(value);
        final endSection = observation == null || _stop.hasMatch(value);
        if (nextSection != null || endSection) {
          if (active.isNotEmpty) {
            final end = observation?.top ?? 2.0;
            final part = left.where((item) =>
                item.top >= began && item.top < end &&
                !_section.hasMatch(item.text.trim()) &&
                !_header.hasMatch(item.text.trim()) &&
                !_stop.hasMatch(item.text.trim())).toList();
            final extracted = _extractSection(
              part,
              section: active,
              periodStart: periodStart,
              periodEnd: periodEnd,
              defaultCurrency: defaultCurrency,
              amountColumn: amountHeader.left,
            );
            rows.addAll(extracted.rows);
            used += extracted.used;
          }
          active = '';
          if (nextSection != null) {
            active = nextSection.group(1)!.toLowerCase().contains('purchases')
                ? 'purchases'
                : 'credits';
            began = observation!.top + observation.height * .4;
            sections++;
          }
        }
        if (endSection && nextSection == null) break;
      }
    }
    if (sections == 0) return null;
    return StatementSectionTableResult(
      rows: rows,
      regionsDetected: sections,
      ignoredObservationCount: (observations.length - used)
          .clamp(0, observations.length).toInt(),
    );
  }

  static ({List<StatementSectionTableRow> rows, int used}) _extractSection(
    List<OcrObservation> observations, {
    required String section,
    required DateTime? periodStart,
    required DateTime? periodEnd,
    required String? defaultCurrency,
    required double amountColumn,
  }) {
    final anchors = observations.where((value) {
      final text = value.text.trim();
      return value.left < amountColumn - .18 &&
          _shortDate.hasMatch(text) &&
          !_header.hasMatch(text);
    }).toList()
      ..sort((a, b) => a.top.compareTo(b.top));

    final output = <StatementSectionTableRow>[];
    var used = 0;
    for (var i = 0; i < anchors.length; i++) {
      final anchor = anchors[i];
      final nextTop = i + 1 < anchors.length ? anchors[i + 1].top : 2.0;
      // A row can wrap, but it must not borrow fields from the next date.
      final cells = observations.where((value) =>
          value.top >= anchor.top - anchor.height * .5 &&
          value.top < nextTop - (i + 1 < anchors.length ? .001 : 0) &&
          !_header.hasMatch(value.text.trim()) &&
          !_section.hasMatch(value.text.trim())).toList()
        ..sort((a, b) {
          final vertical = a.top.compareTo(b.top);
          return (vertical.abs() > .007)
              ? vertical
              : a.left.compareTo(b.left);
        });
      if (cells.isEmpty) continue;
      used += cells.length;

      final dateMatch = _shortDate.firstMatch(anchor.text.trim())!;
      final date = _resolveDate(
        int.parse(dateMatch.group(1)!),
        int.parse(dateMatch.group(2)!),
        periodStart,
        periodEnd,
      );

      final amounts = <String>[];
      final descriptions = <String>[];
      for (final cell in cells) {
        var content = cell.text.trim();
        if (identical(cell, anchor)) {
          content = content.substring(dateMatch.end).trim();
        }
        if (content.isEmpty) continue;
        final matches = _amount.allMatches(content).toList();
        // Amount candidates must be in the measured amount column OR in a
        // single observation that contains the date and description.
        final amountCell = cell.left >= amountColumn - .055 ||
            (identical(cell, anchor) && matches.length == 1);
        if (amountCell && matches.isNotEmpty) {
          for (final match in matches) {
            amounts.add(match.group(1)!);
          }
          for (final match in matches.reversed) {
            content = content.replaceRange(match.start, match.end, ' ');
          }
        }
        if (cell.left < amountColumn - .055 && content.isNotEmpty) {
          descriptions.add(content);
        }
      }

      final parsed = amounts.length == 1 ? _parseAmount(amounts.single) : null;
      final description = descriptions.join(' ')
          .replaceAll(RegExp(r'\s+'), ' ').trim();
      final direction = switch (section) {
        'purchases' => 'expense',
        'credits' when RegExp(
            r'\b(?:AUTOPAY|AUTO\s*PAY|PAYMENT\s+RECEIVED|'
            r'ONLINE\s+PAYMENT|PAYMENT\s+THANK\s+YOU|'
            r'PYMT|PMT)\b',
            caseSensitive: false,
          ).hasMatch(description) => 'transfer',
        'credits' when RegExp(
            r'\b(?:REFUND|RETURN|REVERSAL|CREDIT)\b',
            caseSensitive: false,
          ).hasMatch(description) => 'refund',
        _ => null,
      };
      final confidence = cells.map((e) => e.confidence)
          .fold<double>(0, (sum, value) => sum + value) / cells.length;
      output.add(StatementSectionTableRow(
        originalText: cells.map((value) => value.text.trim()).join(' '),
        description: description.isEmpty ? null : description,
        amount: parsed,
        date: date,
        currency: defaultCurrency,
        direction: direction,
        confidence: date != null && parsed != null &&
                description.isNotEmpty && direction != null
            ? confidence
            : confidence * .5,
        sourceObservationIndexes: [
          for (final cell in cells) cell.order,
        ],
      ));
    }
    return (rows: output, used: used);
  }

  static String? _parseAmount(String value) {
    final plain = value.replaceAll(RegExp(r'[\s,$−-]'), '');
    if (!RegExp(r'^\d+(?:\.\d{2})$').hasMatch(plain)) return null;
    return plain;
  }

  static DateTime? _resolveDate(
    int month,
    int day,
    DateTime? start,
    DateTime? end,
  ) {
    if (start == null || end == null ||
        end.isBefore(start) || end.difference(start).inDays > 370) {
      return null;
    }
    final candidates = <DateTime>[];
    for (final year in {start.year, end.year}) {
      final value = DateTime(year, month, day);
      if (value.month == month && value.day == day &&
          !value.isBefore(start) && !value.isAfter(end)) {
        candidates.add(value);
      }
    }
    return candidates.length == 1 ? candidates.single : null;
  }
}
