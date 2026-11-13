import 'dart:convert';

/// A conservative test-only transcription of aligned statement TXT to JSON.
/// It preserves verbatim strings and source lines; no dates, directions,
/// currencies, or amounts are inferred beyond literal column contents.
abstract final class StatementTextJson {
  static String encode(String text) =>
      const JsonEncoder.withIndent('  ').convert(parse(text));

  static Map<String, Object> parse(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final entries = <Map<String, Object?>>[];
    final unparsed = <Map<String, Object>>[];
    var page = 1;
    List<int>? starts;
    var headerFound = false;

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final pageMatch = RegExp(r'^--- PAGE (\d+) ---$').firstMatch(trimmed);
      if (pageMatch != null) {
        page = int.parse(pageMatch.group(1)!);
        starts = null;
        headerFound = false;
        continue;
      }
      final lower = line.toLowerCase();
      final description = lower.indexOf('description');
      final amount = lower.indexOf('amount', description < 0 ? 0 : description);
      final date = lower.indexOf('purchase date');
      final posting = lower.indexOf('post date');
      if (date >= 0 &&
          posting > date &&
          description > posting &&
          amount > description) {
        starts = [date, posting, description, amount];
        headerFound = true;
        continue;
      }
      // Ignore non-row headings before the table. They remain available
      // verbatim in the original TXT; never treat them as transactions.
      if (!headerFound || starts == null) continue;
      // Date columns on a monospaced line can start one character before a
      // long OCR header: do not slice the date itself at a guessed offset.
      final datePattern = RegExp(r'\b\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?\b');
      final matches = datePattern.allMatches(line).toList(growable: false);
      if (matches.length < 2 ||
          (matches.first.start - starts[0]).abs() > 4 ||
          (matches[1].start - starts[1]).abs() > 4) {
        unparsed.add({'page': page, 'line': index + 1, 'text': line});
        continue;
      }
      final amountMatch = RegExp(
        r'(?:[$€£¥]|USD\s*)?\d[\d,]*(?:\.\d{2})?\s*$',
      ).firstMatch(line);
      final amountStart = amountMatch?.start ?? line.length;
      final merchant = amountStart > matches[1].end
          ? line.substring(matches[1].end, amountStart).trim()
          : '';
      final first = matches.first.group(0)!;
      final post = matches[1].group(0)!;
      final amountText = amountMatch?.group(0)?.trim() ?? '';
      entries.add({
        'page': page,
        'sourceLine': index + 1,
        'sourceText': line,
        'transactionDateText': first,
        'postingDateText': post.isEmpty ? null : post,
        'description': merchant.isEmpty ? null : merchant,
        'amountText': amountText.isEmpty ? null : amountText,
        'status': (merchant.isEmpty || amountText.isEmpty)
            ? 'unresolved'
            : 'transcribed',
      });
    }
    return {
      'schemaVersion': 1,
      'source': 'position-aligned-text',
      'rows': entries,
      'unparsedLines': unparsed,
    };
  }

}
