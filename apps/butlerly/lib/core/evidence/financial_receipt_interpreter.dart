import 'ocr_contract.dart';

/// Deterministic interpretation of single-transaction screenshots.
/// The user has already selected the Receipt workflow; this is not a document
/// classifier and deliberately does not replace normal retail-receipt parsing.
final class FinancialReceiptInterpretation {
  const FinancialReceiptInterpretation({
    this.isScreenshot = false,
    this.amount,
    this.merchant,
    this.transactionDate,
    this.postingDate,
    this.cardLast4,
    this.originalMerchantDescription,
    this.transactionTimeText,
    this.issuerCategory,
    this.evidence = const {},
  });

  final bool isScreenshot;
  final String? amount;
  final String? merchant;
  final DateTime? transactionDate;
  final DateTime? postingDate;
  final String? cardLast4;
  final String? originalMerchantDescription;
  final String? transactionTimeText;
  final String? issuerCategory;
  final Map<String, String> evidence;
}

abstract final class FinancialReceiptInterpreter {
  static final _screenshotHints = RegExp(
    r'transaction details|purchased on|posted on|made on|'
    r'appears on your statement as|on your statement as|'
    r'card ending\s+in|transaction alert',
    caseSensitive: false,
  );
  static final _money = RegExp(r'\$\s*(\d+(?:,\d{3})*)\.(\d{2})(?!\d)');
  static final _label = RegExp(
    r'^(?:amount|merchant|date|time|card ending in|purchased on|'
    r'posted on|made on|on your statement as|appears on your statement as)'
    r'\s*:?\s*$',
    caseSensitive: false,
  );
  static final _excludeMoney = RegExp(
    r'cash\s*back|rewards?\s*cash|points?\s*earned|'
    r'reward|savings|subtotal|sales?\s*tax|tip|'
    r'available\s*balance|credit\s*limit|account\s*balance',
    caseSensitive: false,
  );
  static final _months = <String, int>{
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  static FinancialReceiptInterpretation interpret(
    String text,
    List<OcrObservation> observations,
  ) {
    if (!_screenshotHints.hasMatch(text.replaceAll(RegExp(r'\s+'), ' '))) {
      return const FinancialReceiptInterpretation();
    }
    final lines =
        observations.isEmpty
              ? text.split(RegExp(r'\r?\n')).asMap().entries.map((entry) {
                  return OcrObservation(
                    text: entry.value,
                    confidence: .5,
                    top: entry.key.toDouble(),
                    order: entry.key,
                  );
                }).toList()
              : [...observations]
          ..sort((a, b) {
            final page = a.pageIndex.compareTo(b.pageIndex);
            if (page != 0) return page;
            final vertical = a.top.compareTo(b.top);
            return vertical != 0 ? vertical : a.left.compareTo(b.left);
          });

    final evidence = <String, String>{};
    final labeledAmount = _field(
      lines,
      RegExp(r'^amount\s*:?\s*', caseSensitive: false),
    );
    final amountMatch = labeledAmount == null
        ? null
        : _money.firstMatch(labeledAmount);
    String? amount;
    if (amountMatch != null) {
      amount = _normalizedMoney(amountMatch);
      evidence['amount'] = labeledAmount!;
    } else {
      // A transaction-detail header often has an unlabeled, prominent amount.
      // Do not use rewards, balances, taxes or incidental dollar figures.
      for (final line in lines) {
        if (_excludeMoney.hasMatch(line.text)) continue;
        final match = _money.firstMatch(line.text);
        if (match != null) {
          amount = _normalizedMoney(match);
          evidence['amount'] = line.text;
          break;
        }
        final raised = _raisedCents(line, lines);
        if (raised != null) {
          amount = raised;
          evidence['amount'] = '${line.text} + raised cents';
          break;
        }
      }
    }

    final description =
        _field(
          lines,
          RegExp(r'^on your statement as\s*:?\s*', caseSensitive: false),
        ) ??
        _field(
          lines,
          RegExp(
            r'^appears on your statement as\s*:?\s*',
            caseSensitive: false,
          ),
        );

    final explicitMerchant = _field(
      lines,
      RegExp(r'^merchant\s*:?\s*', caseSensitive: false),
    );
    final merchantText = explicitMerchant ?? _summaryMerchant(lines);
    final merchant = _normalizedMerchant(merchantText);
    if (merchantText != null && merchant != null) {
      evidence['merchant'] = merchantText;
    }

    final purchased = _field(
      lines,
      RegExp(r'^purchased on\s*:?\s*', caseSensitive: false),
    );
    final made = _field(
      lines,
      RegExp(r'^made on\s*:?\s*', caseSensitive: false),
    );
    final date = _field(lines, RegExp(r'^date\s*:?\s*', caseSensitive: false));
    final posted = _field(
      lines,
      RegExp(r'^posted on\s*:?\s*', caseSensitive: false),
    );
    final transactionText = made ?? purchased ?? date ?? posted;
    final transactionDate = transactionText == null
        ? null
        : _parseDate(transactionText);
    if (transactionDate != null) {
      evidence['date'] = transactionText!;
    }
    final postingDate = posted == null ? null : _parseDate(posted);
    final timeLabel = _field(
      lines,
      RegExp(r'^time\s*:?\s*', caseSensitive: false),
    );
    final timeSource = timeLabel ?? purchased ?? made;
    final transactionTimeText = timeSource == null
        ? null
        : RegExp(
            r'\b\d{1,2}:\d{2}\s*(?:AM|PM)'
            r'(?:\s+(?:ET|EST|EDT|PT|PST|PDT|CT|CST|CDT|MT|MST|MDT))?\b',
            caseSensitive: false,
          ).firstMatch(timeSource)?.group(0);
    final issuerCategory = _field(
      lines,
      RegExp(r'^spend category\s*:?\s*', caseSensitive: false),
    );

    // Restrict last-four matching to explicit card context. Store IDs,
    // phone numbers, ZIP codes, and USPS tracking numbers are not cards.
    final cardContext = text.replaceAll(RegExp(r'\s+'), ' ');
    final card = RegExp(
      r'(?:card\s+ending\s+in|visa|mastercard|amex|discover)'
      r'[^\d]{0,24}(\d{4})(?!\d)',
      caseSensitive: false,
    ).firstMatch(cardContext)?.group(1);
    if (card != null) evidence['cardLast4'] = 'card ending $card';

    return FinancialReceiptInterpretation(
      isScreenshot: true,
      amount: amount,
      merchant: merchant,
      transactionDate: transactionDate,
      postingDate: postingDate,
      cardLast4: card,
      originalMerchantDescription: description,
      transactionTimeText: transactionTimeText,
      issuerCategory: issuerCategory,
      evidence: evidence,
    );
  }

  static String _normalizedMoney(RegExpMatch match) =>
      '${match.group(1)!.replaceAll(',', '')}.${match.group(2)!}';

  /// Join two *separate* OCR observations only when the geometry supports a
  /// smaller, raised two-digit fractional part immediately after the dollars.
  /// Never infer a decimal point from an undifferentiated string like $10500.
  static String? _raisedCents(
    OcrObservation dollars,
    List<OcrObservation> observations,
  ) {
    final whole = RegExp(r'^\s*\$\s*(\d{1,6})\s*$').firstMatch(dollars.text);
    if (whole == null || dollars.height <= 0 || dollars.width <= 0) {
      // A single OCR line with an explicit gap is unambiguous enough to
      // reconstruct, even if character-level bounds are unavailable.
      final spaced = RegExp(
        r'^\s*\$\s*(\d{1,6})\s+(\d{2})\s*$',
      ).firstMatch(dollars.text);
      return spaced == null
          ? null
          : wholeMoney(spaced.group(1)!, spaced.group(2)!);
    }
    for (final cents in observations) {
      if (identical(dollars, cents) ||
          dollars.pageIndex != cents.pageIndex ||
          !RegExp(r'^\.?\d{2}$').hasMatch(cents.text.trim()) ||
          cents.height <= 0 ||
          cents.height > dollars.height * .84) {
        continue;
      }
      final right = dollars.left + dollars.width;
      final horizontalGap = cents.left - right;
      final verticalGap = (cents.top - dollars.top).abs();
      if (horizontalGap >= -.02 &&
          horizontalGap <= .06 &&
          verticalGap <= dollars.height * .9) {
        return wholeMoney(
          whole.group(1)!,
          cents.text.trim().replaceFirst('.', ''),
        );
      }
    }
    return null;
  }

  static String wholeMoney(String dollars, String cents) =>
      '$dollars.$cents';

  /// Relates labels to values on the same line, the same visual row, or the
  /// following visual line. In multi-column layouts the value can wrap.
  static String? _field(List<OcrObservation> lines, RegExp label) {
    for (var index = 0; index < lines.length; index++) {
      final anchor = lines[index];
      // 'Merchant details' is a section heading, not a Merchant field.
      if (RegExp(
        r'^merchant details$',
        caseSensitive: false,
      ).hasMatch(anchor.text.trim())) {
        continue;
      }
      final match = label.firstMatch(anchor.text.trim());
      if (match == null) continue;
      var value = anchor.text.trim().substring(match.end).trim();
      if (value.isEmpty) {
        // Values right of a label share its visual row.
        final adjacent =
            lines
                .where(
                  (candidate) =>
                      !identical(candidate, anchor) &&
                      candidate.pageIndex == anchor.pageIndex &&
                      anchor.height > 0 &&
                      candidate.height > 0 &&
                      candidate.left >= anchor.left + anchor.width * .8 &&
                      ((candidate.top + candidate.height / 2) -
                                  (anchor.top + anchor.height / 2))
                              .abs() <=
                          (anchor.height > candidate.height
                                  ? anchor.height
                                  : candidate.height) *
                              .8,
                )
                .toList()
              ..sort((a, b) => a.left.compareTo(b.left));
        if (adjacent.isNotEmpty) {
          value = adjacent.map((item) => item.text.trim()).join(' ');
        }
      }
      if (value.isEmpty && index + 1 < lines.length) {
        final next = lines[index + 1];
        if (!_label.hasMatch(next.text.trim()) &&
            !RegExp(
              r'^merchant details$',
              caseSensitive: false,
            ).hasMatch(next.text.trim())) {
          value = next.text.trim();
        }
      }
      if (value.isEmpty) continue;
      if (RegExp(
            r'^(?:merchant|spend category|on your statement as|appears on your statement as)\b',
            caseSensitive: false,
          ).hasMatch(anchor.text.trim()) &&
          index + 1 < lines.length) {
        // Extend right-column merchant values onto the following line, but
        // stop at another financial field.
        final first = lines.firstWhere(
          (line) => line.text.trim() == value,
          orElse: () => anchor,
        );
        final position = lines.indexOf(first);
        if (position >= 0 && position + 1 < lines.length) {
          final continuation = lines[position + 1];
          final aligned =
              first.height > 0 &&
              continuation.height > 0 &&
              (continuation.left - first.left).abs() < .06 &&
              continuation.top > first.top &&
              continuation.top - first.top < .10;
          if (aligned && !_label.hasMatch(continuation.text.trim())) {
            value += ' ${continuation.text.trim()}';
          }
        }
      }
      return value;
    }
    return null;
  }

  static String? _summaryMerchant(List<OcrObservation> lines) {
    final start = lines.indexWhere(
      (line) => RegExp(
        r'^posted on\b',
        caseSensitive: false,
      ).hasMatch(line.text.trim()),
    );
    final end = lines.indexWhere(
      (line) => RegExp(
        r'^appears on your statement as\b',
        caseSensitive: false,
      ).hasMatch(line.text.trim()),
    );
    if (start >= 0 && end > start) {
      final candidate = lines
          .sublist(start + 1, end)
          .map((l) => l.text.trim())
          .where(_merchantCandidate)
          .lastOrNull;
      if (candidate != null) return candidate;
    }
    final purchased = lines.indexWhere(
      (line) => RegExp(
        r'^purchased on\b',
        caseSensitive: false,
      ).hasMatch(line.text.trim()),
    );
    if (purchased >= 0) {
      final candidate = lines
          .take(purchased)
          .map((l) => l.text.trim())
          .where(_merchantCandidate)
          .lastOrNull;
      if (candidate != null) return candidate;
    }
    return null;
  }

  static bool _merchantCandidate(String value) {
    if (value.length < 2 || value.length > 65) return false;
    if (RegExp(
      r'^\$|^\d|credit card|transaction '
      r'details|rewards|cash back|visa\.{2,}|posted on|card ending|'
      r'purchase|^\+|merchant details',
      caseSensitive: false,
    ).hasMatch(value)) {
      return false;
    }
    return RegExp(r'[A-Za-z\u4e00-\u9fff]').hasMatch(value);
  }

  static String? _normalizedMerchant(String? value) {
    if (value == null) return null;
    final text = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty || text.length > 100) return null;
    // Preserve raw descriptions separately; only strip recognizable
    // store-number/location suffixes (never numbers inside merchant names).
    final location = RegExp(
      r'^(.+?)\s+#?\d{3,6}(?:\s+[A-Z][A-Z\s]+)?$',
    ).firstMatch(text);
    return location?.group(1)?.trim() ?? text;
  }

  static DateTime? _parseDate(String text) {
    final month = RegExp(
      r'\b(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|'
      r'Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|'
      r'Nov(?:ember)?|Dec(?:ember)?)\s+(\d{1,2}),?\s+(20\d{2})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (month != null) {
      final m = _months[month.group(1)!.toLowerCase().substring(0, 3)];
      if (m == null) return null;
      return _checkedDate(
        int.parse(month.group(3)!),
        m,
        int.parse(month.group(2)!),
      );
    }
    final numeric = RegExp(
      r'\b(\d{1,2})/(\d{1,2})/(20\d{2})\b',
    ).firstMatch(text);
    if (numeric == null) return null;
    return _checkedDate(
      int.parse(numeric.group(3)!),
      int.parse(numeric.group(1)!),
      int.parse(numeric.group(2)!),
    );
  }

  static DateTime? _checkedDate(int y, int m, int d) {
    final value = DateTime(y, m, d);
    return value.year == y && value.month == m && value.day == d ? value : null;
  }
}
