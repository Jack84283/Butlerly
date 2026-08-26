import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

final class StatementExtraction {
  const StatementExtraction({
    required this.rawText,
    required this.rows,
    this.institution,
    this.maskedAccountIdentifier,
  });
  final String rawText;
  final List<StatementExtractedRow> rows;
  final String? institution;
  final String? maskedAccountIdentifier;
}

final class StatementExtractedRow {
  const StatementExtractedRow({
    required this.originalText,
    this.date,
    this.description,
    this.amount,
    this.currency,
    this.direction,
    this.confidence,
  });
  final String originalText;
  final DateTime? date;
  final String? description;
  final String? amount;
  final String? currency;
  final String? direction;
  final double? confidence;
}

/// Offline extraction backed by the platform's on-device Vision recognizer.
final class LocalStatementExtractor {
  const LocalStatementExtractor([this.ocr = const LocalOcrService()]);
  final LocalOcrService ocr;

  Future<StatementExtraction> extract(String path) async {
    final result = await ocr.recognize(path);
    return StatementExtraction(
      rawText: result.rawText,
      rows: parse(result.rawText, result.observations),
      institution: _institution(result.rawText),
      maskedAccountIdentifier: _maskedAccountIdentifier(result.rawText),
    );
  }

  static List<StatementExtractedRow> parse(
    String text, [
    List<OcrObservation> observations = const [],
  ]) {
    final confidence = {
      for (final observation in observations)
        observation.text.trim(): observation.confidence,
    };
    final rows = <StatementExtractedRow>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final match = RegExp(
        r'^(\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}[-/]\d{2,4})\s+(.*?)\s+([+\-]?\(?[\d,]+(?:\.\d{2})?\)?)\s*(?:(DR|CR|DEBIT|CREDIT)\s*)?([A-Za-z]{3})?$',
        caseSensitive: false,
      ).firstMatch(line);
      if (match == null) continue;
      final date = parseDate(match.group(1)!);
      final signedText = match.group(3)!.replaceAll(',', '');
      final negative =
          signedText.startsWith('-') ||
          (signedText.startsWith('(') && signedText.endsWith(')'));
      final unsigned = signedText.replaceAll(RegExp(r'[+\-()]'), '');
      final marker = match.group(4)?.toUpperCase();
      final explicitPositive = signedText.startsWith('+');
      final direction = negative || marker == 'DR' || marker == 'DEBIT'
          ? TransactionDirection.expense.name
          : explicitPositive || marker == 'CR' || marker == 'CREDIT'
          ? TransactionDirection.income.name
          : null;
      try {
        final amount = DecimalValue.parse(unsigned).toString();
        rows.add(
          StatementExtractedRow(
            originalText: line,
            date: date,
            description: match.group(2)!.trim(),
            amount: amount,
            currency: match.group(5)?.toUpperCase(),
            direction: direction,
            confidence: confidence[line] ?? 0.5,
          ),
        );
      } on DomainValidationException {
        // Preserve unsupported lines in raw OCR text without inventing values.
      }
    }
    return rows;
  }

  static DateTime? parseDate(String input) {
    final normalized = input.replaceAll('/', '-');
    if (!RegExp(
      r'^(?:\d{4}-\d{1,2}-\d{1,2}|\d{1,2}-\d{1,2}-\d{2,4})$',
    ).hasMatch(normalized)) {
      return null;
    }
    final parts = normalized.split('-');
    if (parts.length != 3) return null;
    var year = int.tryParse(parts.first.length == 4 ? parts[0] : parts[2]);
    if (year != null && year < 100) year += 2000;
    if (year == null) return null;
    final month = int.tryParse(parts.first.length == 4 ? parts[1] : parts[0]);
    final day = int.tryParse(parts.first.length == 4 ? parts[2] : parts[1]);
    if (month == null || day == null) return null;
    final parsed = DateTime.tryParse(
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
    );
    if (parsed == null ||
        parsed.year != year ||
        parsed.month != month ||
        parsed.day != day) {
      return null;
    }
    return parsed;
  }

  static String? _maskedAccountIdentifier(String text) {
    final match = RegExp(
      r'(?:account|acct|card|ending(?:\s+in)?|last\s*4)[^\d]{0,20}(\d{4})(?!\d)',
      caseSensitive: false,
    ).firstMatch(text);
    return match == null ? null : '••••${match.group(1)}';
  }

  static String? _institution(String text) {
    final match = RegExp(
      r'^(?:institution|bank|issuer)\s*[:\-]\s*(.+)$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(text);
    return match?.group(1)?.trim();
  }
}
