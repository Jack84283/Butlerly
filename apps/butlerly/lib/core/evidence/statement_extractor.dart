import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

final class StatementExtraction {
  const StatementExtraction({required this.rawText, required this.rows});
  final String rawText;
  final List<StatementExtractedRow> rows;
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
        r'^(\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}[-/]\d{2,4})\s+(.*?)\s+([+\-]?\(?[\d,]+(?:\.\d{2})?\)?)\s*([A-Za-z]{3})?$',
      ).firstMatch(line);
      if (match == null) continue;
      final date = _date(match.group(1)!);
      final signedText = match.group(3)!.replaceAll(',', '');
      final negative =
          signedText.startsWith('-') ||
          (signedText.startsWith('(') && signedText.endsWith(')'));
      final unsigned = signedText.replaceAll(RegExp(r'[+\-()]'), '');
      try {
        final amount = DecimalValue.parse(unsigned).toString();
        rows.add(
          StatementExtractedRow(
            originalText: line,
            date: date,
            description: match.group(2)!.trim(),
            amount: amount,
            currency: match.group(4)?.toUpperCase(),
            direction: negative
                ? TransactionDirection.expense.name
                : TransactionDirection.income.name,
            confidence: confidence[line] ?? 0.5,
          ),
        );
      } on DomainValidationException {
        // Preserve unsupported lines in raw OCR text without inventing values.
      }
    }
    return rows;
  }

  static DateTime? _date(String input) {
    final normalized = input.replaceAll('/', '-');
    final parts = normalized.split('-');
    if (parts.first.length == 4) return DateTime.tryParse(normalized);
    if (parts.length != 3) return null;
    var year = int.tryParse(parts[2]);
    if (year != null && year < 100) year += 2000;
    if (year == null) return null;
    return DateTime.tryParse(
      '$year-${parts[0].padLeft(2, '0')}-${parts[1].padLeft(2, '0')}',
    );
  }
}
