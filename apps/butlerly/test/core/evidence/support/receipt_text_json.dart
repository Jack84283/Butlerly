import 'dart:convert';

/// Test-only, conservative field candidates from an aligned UTF-8 receipt TXT.
/// All candidates are traceable to literal source lines. This is not a
/// replacement for the production OCR/receipt interpreter.
abstract final class ReceiptTextJson {
  static String encode(String text) =>
      const JsonEncoder.withIndent('  ').convert(parse(text));

  static Map<String, Object> parse(String text) {
    final candidates = <Map<String, Object?>>[];
    final unparsed = <Map<String, Object>>[];
    final lines = text.split(RegExp(r'\r?\n'));
    var page = 1;
    var headerSeen = false;
    final currencyAmount = RegExp(r'([$€£¥]?\s*\d[\d,]*\.\d{2})\s*$');
    final labeledAmount = RegExp(
      r'^\s*(SUB\s*TOTAL|GRAND\s+TOTAL|TOTAL\s+DUE|AMOUNT\s+DUE|TOTAL|SALES\s+TAX|TAX|TIP|GRATUITY)\b',
      caseSensitive: false,
    );
    final datePattern = RegExp(
      r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b',
    );

    for (var index = 0; index < lines.length; index++) {
      final source = lines[index];
      final line = source.trim();
      if (line.isEmpty) continue;
      final separator = RegExp(r'^--- PAGE (\d+) ---$').firstMatch(line);
      if (separator != null) {
        page = int.parse(separator.group(1)!);
        headerSeen = false;
        continue;
      }

      final number = currencyAmount.firstMatch(source);
      final label = labeledAmount.firstMatch(source);
      if (label != null && number != null && number.start >= label.end) {
        final name = label.group(1)!.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
        final field = switch (name) {
          'SUB TOTAL' || 'SUBTOTAL' => 'subtotal',
          'SALES TAX' => 'tax',
          'GRAND TOTAL' || 'TOTAL DUE' || 'AMOUNT DUE' || 'TOTAL' => 'total',
          'TAX' => 'tax',
          'TIP' || 'GRATUITY' => 'tip',
          _ => 'unresolved',
        };
        candidates.add({
          'field': field,
          'label': name,
          'valueText': number.group(1)!.trim(),
          'page': page,
          'sourceLine': index + 1,
          'sourceText': source,
        });
        continue;
      }
      final date = datePattern.firstMatch(line);
      if (date != null) {
        candidates.add({
          'field': 'date',
          'label': null,
          'valueText': date.group(0)!,
          'page': page,
          'sourceLine': index + 1,
          'sourceText': source,
        });
        continue;
      }
      if (!headerSeen &&
          page == 1 &&
          label == null &&
          line.length >= 3 &&
          RegExp(r'[A-Za-z]').hasMatch(line)) {
        candidates.add({
          'field': 'merchantCandidate',
          'label': null,
          'valueText': line,
          'page': page,
          'sourceLine': index + 1,
          'sourceText': source,
        });
        headerSeen = true;
        continue;
      }
      unparsed.add({'page': page, 'sourceLine': index + 1, 'sourceText': source});
    }
    return {
      'schemaVersion': 1,
      'source': 'position-aligned-text',
      'candidates': candidates,
      'unparsedLines': unparsed,
    };
  }
}
