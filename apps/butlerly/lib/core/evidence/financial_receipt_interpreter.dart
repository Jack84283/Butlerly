import 'ocr_contract.dart';

/// Deterministic interpretation of single-transaction screenshots.
/// The user has already selected the Receipt workflow; this is not a document
/// classifier and deliberately does not replace normal retail-receipt parsing.
final class FinancialReceiptInterpretation {
  const FinancialReceiptInterpretation({
    this.isScreenshot = false,
    this.amount,
    this.currency,
    this.currencyNeedsReview = false,
    this.cashBackReward,
    this.amountNeedsReview = false,
    this.dateNeedsReview = false,
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
  final String? currency;
  final bool currencyNeedsReview;
  final String? cashBackReward;
  final bool amountNeedsReview, dateNeedsReview;
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
    r'\b(?:transaction details|purchased on|posted on|made on)\b|'
    r'appears on your statement as|on your statement as|'
    r'card ending\s+in|transaction alert',
    caseSensitive: false,
  );
  static final _money = RegExp(r'\$\s*(\d+(?:,\d{3})*)\.(\d{2})(?!\d)');
  static final _currencyToken = RegExp(r'^[A-Z]{3}$');
  static const _recognizedCurrencyCodes = {
    'USD',
    'CAD',
    'AUD',
    'NZD',
    'HKD',
    'SGD',
    'EUR',
    'GBP',
    'CNY',
    'JPY',
    'MXN',
  };
  static final _purchaseMoney = RegExp(
    r'^(?:US)?\$\s*(\d+(?:,\d{3})*)\.(\d{2})(?:\s+([A-Z]{3}))?$',
    caseSensitive: false,
  );
  static final _label = RegExp(
    r'^(?:amount|merchant|date|time|card ending in|purchased on|'
    r'posted on|made on|purchase date|posting date|transaction date|on your statement as|appears on your statement as)'
    r'\s*:?\s*$',
    caseSensitive: false,
  );
  static final _separateRewardLabel = RegExp(
    r'^(?:(?:[\d.]+%\s*)?cash\s*back(?:\s+earned)?|rewards?\s*cash(?:\s+earned)?)\s*:?$',
    caseSensitive: false,
  );
  static final _excludeMoney = RegExp(
    r'cash\s*back|rewards?\s*cash|points?\s*earned|'
    r'reward|savings|subtotal|sales?\s*tax|tip|'
    r'balance|credit\s*limit|%',
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
    final retailTotal = RegExp(
      r'^[ \t]*(?:grand[ \t]+)?total(?:[ \t]+(?:amount|due))?\b[ \t]*:?[ \t]*(?:\r?\n[ \t]*)?(?:USD[ \t]*)?[$€£¥]?[ \t]*\d',
      multiLine: true,
      caseSensitive: false,
    );
    final bankContext = RegExp(
      r'posted on|posting date|on your statement as|transaction alert',
      caseSensitive: false,
    );
    if (retailTotal.hasMatch(text) && !bankContext.hasMatch(text)) {
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
            final vertical = a.normalizedBounds.top.compareTo(
              b.normalizedBounds.top,
            );
            return vertical != 0
                ? vertical
                : a.normalizedBounds.left.compareTo(b.normalizedBounds.left);
          });

    final evidence = <String, String>{};
    final labeledAmounts = _observedFields(
      lines,
      RegExp(r'^amount\b\s*:?\s*', caseSensitive: false),
    ).toList();
    final header = lines.takeWhile(
      (line) => !RegExp(
        r'^(?:posted on|posting date|appears on your statement as|on your statement as|merchant details)\b',
        caseSensitive: false,
      ).hasMatch(line.text.trim()),
    );
    final balances = RegExp(
      r'^(?:(?:(?:total|current|available|account|statement|remaining|outstanding)\s+)*balance|credit\s*limit)\s*:?$',
      caseSensitive: false,
    );
    final rewardLabel = RegExp(
      r'cash\s*back|rewards?\s*cash',
      caseSensitive: false,
    );
    final excludedValues = <OcrObservation>{};
    final rewards = <String>{};
    for (final (index, line) in lines.indexed) {
      final value = line.text.trim();
      final isReward = _separateRewardLabel.hasMatch(value);
      if (isReward || balances.hasMatch(value)) {
        final paired = _adjacentMoney(lines, index);
        if (paired != null) {
          excludedValues.add(paired);
          if (isReward) {
            final match = _money.firstMatch(paired.text);
            if (match != null) rewards.add(_normalizedMoney(match));
          }
        }
      } else if (rewardLabel.hasMatch(value)) {
        rewards.addAll(_money.allMatches(value).map(_normalizedMoney));
      }
    }
    final candidates = <String, String>{};
    final currencyByAmount = <String, Set<String>>{};
    void recordAmount(String amount, String value, OcrObservation source) {
      candidates[amount] = value;
      final upper = value.toUpperCase();
      final currencies = currencyByAmount.putIfAbsent(amount, () => <String>{});
      if (upper.startsWith(r'US$')) currencies.add('USD');
      if (_purchaseMoney.firstMatch(value)?.group(3) case final code?) {
        currencies.add(
          _recognizedCurrencyCodes.contains(code.toUpperCase())
              ? code.toUpperCase()
              : '?',
        );
      }
      final bounds = source.normalizedBounds;
      if (bounds.height > 0) {
        for (final observation in lines) {
          final text = observation.text.trim();
          if (observation.pageIndex != source.pageIndex ||
              !_currencyToken.hasMatch(text)) {
            continue;
          }
          final adjacent = observation.normalizedBounds;
          final rightGap = adjacent.left - bounds.left - bounds.width;
          final leftGap = bounds.left - adjacent.left - adjacent.width;
          final centerGap =
              (adjacent.top +
                      adjacent.height / 2 -
                      bounds.top -
                      bounds.height / 2)
                  .abs();
          final belowGap = adjacent.top - bounds.top;
          final sameRow =
              ((rightGap >= -.01 && rightGap < .08) ||
                  (leftGap >= -.01 && leftGap < .08)) &&
              centerGap <= bounds.height * .65;
          final directlyBelow =
              belowGap > 0 &&
              belowGap < .08 &&
              (adjacent.left - bounds.left).abs() < .12;
          if (adjacent.height > 0 && (sameRow || directlyBelow)) {
            currencies.add(
              _recognizedCurrencyCodes.contains(text) ? text : '?',
            );
          }
        }
      } else {
        final index = lines.indexOf(source);
        if (index < 0 || index + 1 >= lines.length) return;
        final afterAmount = index + 1;
        final nextIndex =
            value.endsWith(' + raised cents') &&
                lines[afterAmount].text.trim().replaceFirst('.', '') ==
                    amount.split('.').last
            ? afterAmount + 1
            : afterAmount;
        // Without geometry, a token immediately before or after the amount
        // may be its currency. Do not scan unrelated rewards or balances.
        for (final candidateIndex in [index - 1, nextIndex]) {
          if (candidateIndex < 0 || candidateIndex >= lines.length) continue;
          final neighbor = lines[candidateIndex];
          final text = neighbor.text.trim().toUpperCase();
          if (neighbor.pageIndex == source.pageIndex &&
              _currencyToken.hasMatch(text)) {
            currencies.add(
              _recognizedCurrencyCodes.contains(text) ? text : '?',
            );
          }
        }
      }
    }

    var unresolved = false;
    final whole = RegExp(r'^\s*\$\s*\d[\d, ]*\s*$');
    for (final line
        in labeledAmounts.isEmpty ? header : const <OcrObservation>[]) {
      final value = line.text.trim();
      if (_excludeMoney.hasMatch(value) || excludedValues.contains(line)) {
        continue;
      }
      final decimal = _purchaseMoney.firstMatch(value);
      if (decimal != null) {
        recordAmount(_normalizedMoney(decimal), value, line);
      } else if (whole.hasMatch(value)) {
        final raised = _raisedCents(line, lines);
        if (raised == null) {
          unresolved = true;
        } else {
          recordAmount(raised, '${line.text} + raised cents', line);
        }
      }
    }
    for (final (labeledAmount, source) in labeledAmounts) {
      if (_excludeMoney.hasMatch(labeledAmount) ||
          excludedValues.contains(source)) {
        continue;
      }
      final match = _purchaseMoney.firstMatch(labeledAmount);
      if (match != null) {
        recordAmount(_normalizedMoney(match), labeledAmount, source);
      } else if (whole.hasMatch(labeledAmount)) {
        final resolved =
            _raisedCents(source, lines) ??
            (source.text.trim().endsWith(labeledAmount)
                ? _raisedCents(
                    OcrObservation(text: labeledAmount, confidence: 0),
                    const [],
                  )
                : null);
        if (resolved != null) {
          recordAmount(resolved, '$labeledAmount + raised cents', source);
        } else {
          unresolved = true;
        }
      }
    }
    final amountNeedsReview = unresolved || candidates.length > 1;
    final amount = !amountNeedsReview && candidates.length == 1
        ? candidates.keys.single
        : null;
    if (amount != null) evidence['amount'] = candidates[amount]!;
    final explicitCurrencies = _fields(
      lines,
      RegExp(r'^currency\b\s*:?\s*', caseSensitive: false),
    ).map((value) => value.trim().toUpperCase()).toSet();
    explicitCurrencies.addAll(currencyByAmount[amount] ?? const {});
    final explicitCurrency = explicitCurrencies.length == 1
        ? explicitCurrencies.single
        : null;
    final currency = explicitCurrencies.isEmpty
        ? (amount == null ? null : 'USD')
        : explicitCurrency != null &&
              RegExp(r'^[A-Z]{3}$').hasMatch(explicitCurrency)
        ? explicitCurrency
        : null;
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

    final purchaseTexts = _fields(
      lines,
      RegExp(
        r'^(?:made on|purchased on|purchase date|transaction date)\b\s*:?\s*',
        caseSensitive: false,
      ),
    ).toList();
    if (purchaseTexts.isEmpty) {
      purchaseTexts.addAll(
        _fields(lines, RegExp(r'^date\b\s*:?\s*', caseSensitive: false)),
      );
    }
    final postingTexts = _fields(
      lines,
      RegExp(r'^(?:posted on|posting date)\b\s*:?\s*', caseSensitive: false),
    ).toList();
    final transactionDate = _uniqueDate(purchaseTexts);
    final postingDate = _uniqueDate(postingTexts);
    if (transactionDate != null) evidence['date'] = purchaseTexts.first;
    final timeLabel = _field(
      lines,
      RegExp(r'^time\s*:?\s*', caseSensitive: false),
    );
    final timeSource = timeLabel ?? purchaseTexts.firstOrNull;
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
    final cardContext = lines.map((line) => line.text.trim()).join('\n');
    final card = RegExp(
      r'(?:card\s+ending\s+in|visa|mastercard|amex|discover)'
      r'[ \t]*:?(?:[ \t]*[.*•x]+)?[ \t]*(?:\n[ \t]*)?(\d{4})(?![\d-])',
      caseSensitive: false,
    ).firstMatch(cardContext)?.group(1);
    if (card != null) evidence['cardLast4'] = 'card ending $card';

    return FinancialReceiptInterpretation(
      isScreenshot: true,
      amount: amount,
      currency: currency,
      currencyNeedsReview: currency == null && explicitCurrencies.isNotEmpty,
      cashBackReward: rewards.length == 1 ? rewards.single : null,
      amountNeedsReview: amountNeedsReview,
      dateNeedsReview:
          transactionDate == null ||
          (postingTexts.isNotEmpty && postingDate == null),
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

  static OcrObservation? _adjacentMoney(List<OcrObservation> lines, int index) {
    final anchor = lines[index];
    final bounds = anchor.normalizedBounds;
    final whole = RegExp(r'^\$\s*\d[\d, ]*$');
    bool isMoney(String text) {
      final value = text.trim().replaceFirst(RegExp(r'^\+\s*'), '');
      return _purchaseMoney.hasMatch(value) || whole.hasMatch(value);
    }

    if (index + 1 < lines.length) {
      final next = lines[index + 1];
      final nextBounds = next.normalizedBounds;
      if (next.pageIndex == anchor.pageIndex &&
          isMoney(next.text) &&
          (bounds.height == 0 ||
              ((bounds.left - nextBounds.left).abs() < .12 &&
                  nextBounds.top - bounds.top < .08))) {
        return next;
      }
    }
    if (bounds.height > 0) {
      final sameRow = lines.where((line) {
        final candidate = line.normalizedBounds;
        final leftGap = bounds.left - (candidate.left + candidate.width);
        return line.pageIndex == anchor.pageIndex &&
            candidate.height > 0 &&
            (candidate.left >= bounds.left + bounds.width * .8 ||
                (!anchor.text.contains('%') &&
                    leftGap >= 0 &&
                    leftGap < .15)) &&
            (candidate.top +
                        candidate.height / 2 -
                        bounds.top -
                        bounds.height / 2)
                    .abs() <=
                bounds.height * .65 &&
            isMoney(line.text);
      }).toList();
      if (sameRow.length == 1) return sameRow.single;
    }
    return null;
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
    final whole = RegExp(
      r'^\s*(?:amount\s*:?\s*)?\$\s*(\d{1,6})\s*$',
      caseSensitive: false,
    ).firstMatch(dollars.text);
    final digits = whole?.group(1);
    if (dollars.hasRaisedCents && digits != null && digits.length >= 3) {
      final split = digits.length - 2;
      return wholeMoney(digits.substring(0, split), digits.substring(split));
    }
    if (whole == null ||
        dollars.normalizedBounds.height <= 0 ||
        dollars.normalizedBounds.width <= 0) {
      // A single OCR line with an explicit gap is unambiguous enough to
      // reconstruct, even if character-level bounds are unavailable.
      final spaced = RegExp(
        r'^\s*\$\s*(\d{1,6})\s+(\d{2})\s*$',
      ).firstMatch(dollars.text);
      return spaced == null
          ? null
          : wholeMoney(spaced.group(1)!, spaced.group(2)!);
    }
    final amounts = <String>[];
    final wholeBounds = dollars.normalizedBounds;
    for (final cents in observations) {
      final fraction = cents.normalizedBounds;
      if (identical(dollars, cents) ||
          dollars.pageIndex != cents.pageIndex ||
          !RegExp(r'^\.?\d{2}$').hasMatch(cents.text.trim()) ||
          fraction.height <= 0 ||
          fraction.height > wholeBounds.height * .84) {
        continue;
      }
      final horizontalGap =
          fraction.left - (wholeBounds.left + wholeBounds.width);
      final verticalGap = (fraction.top - wholeBounds.top).abs();
      final bottomGap =
          wholeBounds.top +
          wholeBounds.height -
          (fraction.top + fraction.height);
      if (horizontalGap >= -.02 &&
          horizontalGap <= .06 &&
          verticalGap <= wholeBounds.height * .9 &&
          bottomGap >= wholeBounds.height * .08) {
        amounts.add(
          wholeMoney(whole.group(1)!, cents.text.trim().replaceFirst('.', '')),
        );
      }
    }
    return amounts.length == 1 ? amounts.single : null;
  }

  static String wholeMoney(String dollars, String cents) => '$dollars.$cents';

  /// Relates labels to values on the same line, the same visual row, or the
  /// following visual line. In multi-column layouts the value can wrap.
  static String? _field(List<OcrObservation> lines, RegExp label) =>
      _fields(lines, label).firstOrNull;

  static Iterable<String> _fields(List<OcrObservation> lines, RegExp label) =>
      _observedFields(lines, label).map((field) => field.$1);

  static Iterable<(String, OcrObservation)> _observedFields(
    List<OcrObservation> lines,
    RegExp label,
  ) sync* {
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
      var source = anchor;
      if (value.isEmpty) {
        // Values right of a label share its visual row.
        final adjacent =
            lines
                .where(
                  (candidate) =>
                      !identical(candidate, anchor) &&
                      candidate.pageIndex == anchor.pageIndex &&
                      anchor.normalizedBounds.height > 0 &&
                      candidate.normalizedBounds.height > 0 &&
                      candidate.normalizedBounds.left >=
                          anchor.normalizedBounds.left +
                              anchor.normalizedBounds.width * .8 &&
                      ((candidate.normalizedBounds.top +
                                      candidate.normalizedBounds.height / 2) -
                                  (anchor.normalizedBounds.top +
                                      anchor.normalizedBounds.height / 2))
                              .abs() <=
                          (anchor.normalizedBounds.height >
                                      candidate.normalizedBounds.height
                                  ? anchor.normalizedBounds.height
                                  : candidate.normalizedBounds.height) *
                              .8,
                )
                .toList()
              ..sort(
                (a, b) =>
                    a.normalizedBounds.left.compareTo(b.normalizedBounds.left),
              );
        if (adjacent.isNotEmpty) {
          source = adjacent.first;
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
          source = next;
          value = next.text.trim();
        }
      }
      if (value.isEmpty) continue;
      if (RegExp(
            r'^(?:merchant|(?:appears )?on your statement as)\b',
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
              first.pageIndex == continuation.pageIndex &&
              first.normalizedBounds.height > 0 &&
              continuation.normalizedBounds.height > 0 &&
              (continuation.normalizedBounds.left - first.normalizedBounds.left)
                      .abs() <
                  .06 &&
              continuation.normalizedBounds.top > first.normalizedBounds.top &&
              continuation.normalizedBounds.top - first.normalizedBounds.top <
                  .10;
          final continuationText = continuation.text.trim();
          final startsAnotherField = RegExp(
            r'^(?:made on|purchased on|posted on|purchase date|transaction date|posting date|call merchant|report a problem|learn more|merchant details|spend category)\b',
            caseSensitive: false,
          ).hasMatch(continuationText);
          if (aligned &&
              !startsAnotherField &&
              !_label.hasMatch(continuationText)) {
            value += ' $continuationText';
          }
        }
      }
      yield (value, source);
    }
  }

  static String? _summaryMerchant(List<OcrObservation> lines) {
    final start = lines.indexWhere(
      (line) => RegExp(
        r'^(?:posted on|posting date)\b',
        caseSensitive: false,
      ).hasMatch(line.text.trim()),
    );
    final end = lines.indexWhere(
      (line) => RegExp(
        r'^(?:appears )?on your statement as\b',
        caseSensitive: false,
      ).hasMatch(line.text.trim()),
    );
    if (start >= 0 && end > start) {
      final candidates = lines
          .sublist(start + 1, end)
          .takeWhile(
            (line) => !RegExp(
              r'^learn more|^call merchant|^report a problem',
              caseSensitive: false,
            ).hasMatch(line.text.trim()),
          )
          .where(
            (line) =>
                line.normalizedBounds.height <= 0 ||
                (line.normalizedBounds.left - lines[end].left).abs() < .15,
          )
          .map((l) => l.text.trim())
          .where(_merchantCandidate)
          .toList();
      if (candidates.map((value) => value.toLowerCase()).toSet().length == 1) {
        return candidates.first;
      }
    }
    // Some bank screenshots have a purchase-date label but no posting date.
    // Look for a unique merchant before or after that label, never crossing
    // the original statement-description boundary.
    final purchaseAnchor = lines.indexWhere(
      (line) => RegExp(
        r'^(?:made on|purchased on|purchase date|transaction date)\b',
        caseSensitive: false,
      ).hasMatch(line.text.trim()),
    );
    if (purchaseAnchor >= 0) {
      final boundary = end >= 0 ? end : lines.length;
      final segments = <List<OcrObservation>>[
        if (purchaseAnchor <= boundary) lines.sublist(0, purchaseAnchor),
        if (purchaseAnchor + 1 < boundary)
          lines.sublist(purchaseAnchor + 1, boundary),
      ];
      for (final segment in segments) {
        final candidates = segment
            .map((line) => line.text.trim())
            .where(_merchantCandidate)
            .toList(growable: false);
        if (candidates.isNotEmpty &&
            candidates.map((value) => value.toLowerCase()).toSet().length == 1) {
          return candidates.first;
        }
      }
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
    if (value.length < 2 ||
        value.length > 65 ||
        _parseDate(value) != null ||
        _recognizedCurrencyCodes.contains(value.toUpperCase())) {
      return false;
    }
    if (RegExp(
      r'^\$|^\d|credit card|transaction '
      r'details|rewards|cash back|visa\.{2,}|posted on|card ending|'
      r'purchase|^\+|merchant details|learn more|call merchant|report a problem|'
      r'^made on\b|^transaction date\b|^posting date\b|^currency\b|^amount\b|^time\b|^merchant$',
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

  static DateTime? _uniqueDate(List<String> texts) {
    final dates = texts.map(_parseDate).toSet();
    return dates.length == 1 ? dates.single : null;
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
    final iso = RegExp(r'\b(20\d{2})-(\d{2})-(\d{2})\b').firstMatch(text);
    if (iso != null) {
      return _checkedDate(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }
    final numeric = RegExp(
      r'\b(\d{1,2})/(\d{1,2})/(20\d{2})\b',
    ).firstMatch(text);
    if (numeric == null) return null;
    final monthNumber = int.parse(numeric.group(1)!);
    final day = int.parse(numeric.group(2)!);
    if (monthNumber != day && monthNumber <= 12 && day <= 12) return null;
    return _checkedDate(int.parse(numeric.group(3)!), monthNumber, day);
  }

  static DateTime? _checkedDate(int y, int m, int d) {
    final value = DateTime(y, m, d);
    return value.year == y && value.month == m && value.day == d ? value : null;
  }
}
