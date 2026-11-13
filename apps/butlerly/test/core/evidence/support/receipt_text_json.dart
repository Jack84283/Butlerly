import 'dart:convert';

/// Test-only, conservative field candidates from aligned UTF-8 receipt TXT.
/// All candidates are traceable to source lines. No field is silently chosen
/// as the final payable amount, merchant, or transaction date.
abstract final class ReceiptTextJson {
  static String encode(String text) =>
      const JsonEncoder.withIndent('  ').convert(parse(text));

  static Map<String, Object> parse(String text) {
    final candidates = <Map<String, Object?>>[];
    final unparsed = <Map<String, Object>>[];
    final lines = text.split(RegExp(r'\r?\n'));
    final amountLine = RegExp(
      r'^\s*(SUB\s*TOTAL|GRAND\s+TOTAL|TOTAL\s+DUE|AMOUNT\s+DUE|'
      r'TOTAL\s+AMOUNT|BALANCE\s+DUE|TOTAL|SALES\s+TAX|TAX|TIP|'
      r'GRATUITY)\s*:?\s+'
      r'([+-]?(?:[$€£¥]\s*)?(?:\d{1,3}(?:,\d{3})+|\d+)'
      r'(?:[.,]\d{2})?|\([€£¥$]?\s*\d+(?:[.,]\d{2})?\))\s*$',
      caseSensitive: false,
    );
    final datePattern = RegExp(r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b');
    final genericHeader = RegExp(
      r'^(?:receipt|sales receipt|invoice|thank you|welcome|copy|'
      r'customer copy|merchant copy|store receipt|transaction)$',
      caseSensitive: false,
    );
    final address = RegExp(
      r'(?:\b(?:street|st\.|avenue|ave\.|road|rd\.|suite|ste\.|'
      r'blvd|boulevard|zip|phone|tel)\b|,\s*[A-Z]{2}\b)',
      caseSensitive: false,
    );
    var page = 1;
    var inHeader = true;
    var merchantCount = 0;

    for (var index = 0; index < lines.length; index++) {
      final source = lines[index];
      final line = source.trim();
      if (line.isEmpty) continue;
      final separator = RegExp(r'^--- PAGE (\d+) ---$').firstMatch(line);
      if (separator != null) {
        page = int.parse(separator.group(1)!);
        inHeader = false;
        continue;
      }

      final amount = amountLine.firstMatch(source);
      if (amount != null) {
        inHeader = false;
        final label = amount.group(1)!.toUpperCase().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
        final field = switch (label) {
          'SUB TOTAL' || 'SUBTOTAL' => 'subtotal',
          'SALES TAX' || 'TAX' => 'tax',
          'TIP' || 'GRATUITY' => 'tip',
          'GRAND TOTAL' ||
          'TOTAL DUE' ||
          'AMOUNT DUE' ||
          'TOTAL AMOUNT' ||
          'BALANCE DUE' ||
          'TOTAL' => 'total',
          _ => 'unresolved',
        };
        candidates.add({
          'field': field,
          'label': label,
          'valueText': amount.group(2)!.trim(),
          'page': page,
          'sourceLine': index + 1,
          'sourceText': source,
        });
        continue;
      }

      final date = datePattern.firstMatch(line);
      if (date != null) {
        inHeader = false;
        final context = line.substring(0, date.start).toLowerCase();
        final expiration = RegExp(
          r'(?:\bexp(?:iration|iry)?\b|\bvalid\s+(?:thru|through)\b|'
          r'\bexpires?\b)',
        ).hasMatch(context);
        if (!expiration) {
          final labeled = RegExp(
            r'\b(?:transaction|purchase|receipt)?\s*date\s*:?\s*$',
          ).hasMatch(context);
          candidates.add({
            'field': labeled ? 'date' : 'dateCandidate',
            'label': null,
            'valueText': date.group(0)!,
            'page': page,
            'sourceLine': index + 1,
            'sourceText': source,
          });
          continue;
        }
      }

      // Keep several plausible names, rather than treating the first line
      // (often just "RECEIPT") as the actual merchant.
      if (page == 1 &&
          inHeader &&
          merchantCount < 3 &&
          !genericHeader.hasMatch(line) &&
          !address.hasMatch(line) &&
          !RegExp(r'\d').hasMatch(line) &&
          RegExp(r'[A-Za-z]').hasMatch(line) &&
          line.length >= 3) {
        candidates.add({
          'field': 'merchantCandidate',
          'label': null,
          'valueText': line,
          'page': page,
          'sourceLine': index + 1,
          'sourceText': source,
        });
        merchantCount++;
        continue;
      }
      unparsed.add({
        'page': page,
        'sourceLine': index + 1,
        'sourceText': source,
      });
    }
    return {
      'schemaVersion': 1,
      'source': 'position-aligned-text',
      'candidates': candidates,
      'unparsedLines': unparsed,
    };
  }
}
