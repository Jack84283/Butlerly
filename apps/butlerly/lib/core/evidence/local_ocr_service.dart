import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/services.dart';

final class OcrObservation {
  const OcrObservation({
    required this.text,
    required this.confidence,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String text;
  final double confidence;
  final double left;
  final double top;
  final double width;
  final double height;
}

final class ReceiptOcrResult {
  ReceiptOcrResult({
    required String rawText,
    List<OcrObservation> observations = const [],
    this.fieldConfidence = const {},
    this.fieldEvidence = const {},
    this.merchant,
    this.amount,
    this.currency,
    this.date,
    this.tax,
    this.tip,
    this.cardLast4,
    this.cardNetwork,
    this.cardType,
    this.cardExpiry,
  }) : rawText = redactPanLikeText(rawText),
       observations = observations
           .map(
             (value) => OcrObservation(
               text: redactPanLikeText(value.text),
               confidence: value.confidence,
               left: value.left,
               top: value.top,
               width: value.width,
               height: value.height,
             ),
           )
           .toList(growable: false);

  final String rawText;
  final List<OcrObservation> observations;
  final Map<String, double> fieldConfidence;
  final Map<String, String> fieldEvidence;
  final String? merchant;
  final String? amount;
  final String? currency;
  final DateTime? date;
  final String? tax;
  final String? tip;
  final String? cardLast4;
  final String? cardNetwork;
  final String? cardType;
  final String? cardExpiry;

  Map<String, String> toExtractionValues() {
    final values = <String, String>{'rawText': rawText};
    if (observations.isNotEmpty) {
      values['observationCount'] = observations.length.toString();
    }
    for (final entry in fieldConfidence.entries) {
      values['${entry.key}Confidence'] = entry.value.toStringAsFixed(3);
    }
    for (final entry in fieldEvidence.entries) {
      values['${entry.key}Evidence'] = redactPanLikeText(entry.value);
    }
    if (merchant case final value?) values['merchant'] = value;
    if (amount case final value?) values['amount'] = value;
    if (currency case final value?) values['currency'] = value;
    if (date case final value?) values['date'] = _iso(value);
    if (tax case final value?) values['tax'] = value;
    if (tip case final value?) values['tip'] = value;
    if (cardLast4 case final value?) values['cardLast4'] = value;
    if (cardNetwork case final value?) values['cardNetwork'] = value;
    if (cardType case final value?) values['cardType'] = value;
    if (cardExpiry case final value?) values['cardExpiry'] = value;
    for (final key in values.keys.toList()) {
      values[key] = redactPanLikeText(values[key]!);
    }
    return values;
  }

  static String _iso(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

/// Removes complete payment-card numbers from all derived OCR text while
/// retaining the safe last-four representation for card matching.
String redactPanLikeText(String text) {
  var redacted = text;
  for (final pattern in [
    RegExp(r'(?<!\d)\d{13,19}(?!\d)'),
    RegExp(r'(?<!\d)(?:\d{4}[ -]){3}\d{4}(?!\d)'),
  ]) {
    redacted = redacted.replaceAllMapped(pattern, (match) {
      final digits = match.group(0)!.replaceAll(RegExp(r'[^0-9]'), '');
      return '****${digits.substring(digits.length - 4)}';
    });
  }
  return redacted;
}

final class LocalOcrService {
  const LocalOcrService();

  static const _channel = MethodChannel('butlerly/local_ocr');

  Future<ReceiptOcrResult> recognize(String path) async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'recognizeText',
      {'path': path},
    );
    final text = raw?['text'] as String? ?? '';
    if (text.trim().isEmpty) {
      throw const FormatException('No readable receipt text was found.');
    }
    return ReceiptExtractor.extract(text, _observations(raw?['observations']));
  }

  static List<OcrObservation> _observations(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (item) => OcrObservation(
            text: item['text'] as String? ?? '',
            confidence: (item['confidence'] as num?)?.toDouble() ?? 0,
            left: (item['left'] as num?)?.toDouble() ?? 0,
            top: (item['top'] as num?)?.toDouble() ?? 0,
            width: (item['width'] as num?)?.toDouble() ?? 0,
            height: (item['height'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<CardScanResult> recognizeCard(String path) async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'recognizeText',
      {'path': path},
    );
    final text = raw?['text'] as String? ?? '';
    if (text.trim().isEmpty) {
      throw const FormatException('No readable card details were found.');
    }
    return CardTextParser.parse(text, _observations(raw?['observations']));
  }
}

final class CardScanResult {
  const CardScanResult({this.issuer, this.lastFour, this.type});

  final String? issuer;
  final String? lastFour;
  final PaymentSourceType? type;
}

abstract final class CardTextParser {
  static CardScanResult parse(
    String text, [
    List<OcrObservation> observations = const [],
  ]) {
    final upper = text.toUpperCase();
    final issuer = switch (true) {
      _ when upper.contains('AMERICAN EXPRESS') || upper.contains('AMEX') =>
        'American Express',
      _ when upper.contains('MASTERCARD') => 'Mastercard',
      _ when upper.contains('VISA') => 'Visa',
      _ when upper.contains('DISCOVER') => 'Discover',
      _ => null,
    };
    final structured = observations.isEmpty
        ? null
        : ReceiptExtractor.extract(text, observations).cardLast4;
    final lastFour =
        structured ??
        RegExp(
          r'(?<!\d)\d{4}[\s-]*\d{4}[\s-]*\d{4}[\s-]*(\d{4})(?!\d)',
        ).firstMatch(text)?.group(1) ??
        RegExp(
          r'(?:ending|last\s*4|card|visa|mastercard|amex|discover|x{2,}|\*{2,})'
          r'[^\d]{0,12}(\d{4})(?!\d)',
          caseSensitive: false,
        ).firstMatch(text)?.group(1);
    return CardScanResult(
      issuer: issuer,
      lastFour: lastFour,
      type: PaymentSourceType.card,
    );
  }
}

abstract final class ReceiptTextParser {
  static ReceiptOcrResult parse(String text) {
    return ReceiptExtractor.extract(text);
  }
}

abstract final class ReceiptExtractor {
  static ReceiptOcrResult extract(
    String text, [
    List<OcrObservation> observations = const [],
  ]) {
    final lines =
        (observations.isEmpty
                ? text
                      .split(RegExp(r'\r?\n'))
                      .asMap()
                      .entries
                      .map(
                        (entry) => OcrObservation(
                          text: entry.value,
                          confidence: 0.5,
                          left: 0,
                          top: entry.key.toDouble(),
                          width: 1,
                          height: 0,
                        ),
                      )
                : observations)
            .where((line) => line.text.trim().isNotEmpty)
            .toList(growable: false);
    final values = _extract(lines);
    return ReceiptOcrResult(
      rawText: text,
      observations: observations,
      fieldConfidence: values.confidence,
      fieldEvidence: values.evidence,
      merchant: values.merchant,
      amount: values.amount,
      currency: values.currency,
      date: values.date,
      tax: values.tax,
      tip: values.tip,
      cardLast4: values.cardLast4,
      cardNetwork: values.cardNetwork,
      cardType: values.cardType,
      cardExpiry: values.cardExpiry,
    );
  }

  static _ReceiptFields _extract(List<OcrObservation> observations) {
    final ordered = [...observations]..sort((a, b) => a.top.compareTo(b.top));
    final text = ordered.map((line) => line.text).join('\n');
    final lines = ordered.map((line) => line.text.trim()).toList();
    final merchant = _merchant(ordered);
    final amount = _rankedAmount(ordered);
    final tax = _keyword(ordered, const ['sales tax', 'tax']);
    final tip = _keyword(ordered, const ['tip', 'gratuity']);
    final date = _date(_normalize(text));
    final currency = _currency(text);
    final payment = _paymentRegion(ordered);
    final cardLast4 = payment.lastFour;
    final confidence = <String, double>{};
    final evidence = <String, String>{};
    void record(String key, String? value, [double fallback = 0.35]) {
      if (value == null) return;
      final source = ordered.firstWhere(
        (line) => line.text.toLowerCase().contains(value.toLowerCase()),
        orElse: () => ordered.isEmpty
            ? const OcrObservation(
                text: '',
                confidence: 0.0,
                left: 0,
                top: 0,
                width: 0,
                height: 0,
              )
            : ordered.first,
      );
      confidence[key] = source.confidence > 0 ? source.confidence : fallback;
      evidence[key] = key.startsWith('card')
          ? _redactCardEvidence(source.text)
          : source.text;
    }

    record('merchant', merchant);
    record('amount', amount, 0.8);
    record('tax', tax, 0.8);
    record('tip', tip, 0.8);
    record('currency', currency, 0.7);
    record('date', date == null ? null : _iso(date));
    record('cardLast4', cardLast4, 0.8);
    record('cardNetwork', payment.network, 0.8);
    record('cardType', payment.type, 0.7);
    record('cardExpiry', payment.expiry, 0.7);
    return _ReceiptFields(
      merchant: merchant,
      amount: amount,
      currency: currency,
      date: date,
      tax: tax,
      tip: tip,
      cardLast4: cardLast4,
      cardNetwork: payment.network,
      cardType: payment.type,
      cardExpiry: payment.expiry,
      confidence: confidence,
      evidence: evidence,
      lines: lines,
    );
  }

  static String? _merchant(List<OcrObservation> observations) {
    String? best;
    var bestScore = 0.0;
    for (final line in observations.take(6)) {
      final value = line.text.trim();
      if (value.length < 2 || value.length > 60) continue;
      final normalized = _normalize(value);
      if (RegExp(r'^\d[\d\s./:-]*$').hasMatch(normalized)) continue;
      if (_money(normalized).isNotEmpty) continue;
      if (RegExp(
        r'\bwelcome\b|thank you|\breceipt\b|\binvoice\b|customer copy|merchant copy|\bsale\b|\bpurchase\b|\border\b|\btransaction\b|\bstore\b|\bregister\b|\bcashier\b|\bdate\b|\btel\b',
        caseSensitive: false,
      ).hasMatch(value)) {
        continue;
      }
      if (RegExp(
        r'(@|https?://|\b\d{3}[-.) ]\d{3}[-. ]\d{4}\b)',
      ).hasMatch(value)) {
        continue;
      }
      final alpha = RegExp(r'[A-Za-z]').allMatches(value).length;
      final score =
          line.confidence * .55 +
          (line.top < .28 ? .30 : .05) +
          (alpha >= 3 ? .15 : 0);
      if (score > bestScore) {
        best = value;
        bestScore = score;
      }
    }
    return bestScore >= .45 ? best : null;
  }

  static String? _rankedAmount(List<OcrObservation> lines) {
    final explicit = _explicitTotal(lines);
    if (explicit != null) return explicit;

    const positive = [
      'grand total',
      'total due',
      'amount due',
      'amount paid',
      'purchase total',
      'total',
      'amount',
      'sale',
    ];
    const negative = [
      'subtotal',
      'tax',
      'tip',
      'gratuity',
      'change',
      'cash',
      'tendered',
      'savings',
      'balance before',
      'reward',
      'points',
    ];
    final candidates = <({String value, double score})>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final normalized = _normalize(line.text);
      final nearby = <String>[normalized];
      if (index > 0 && (lines[index - 1].top - line.top).abs() < .045) {
        nearby.add(_normalize(lines[index - 1].text));
      }
      if (index + 1 < lines.length &&
          (lines[index + 1].top - line.top).abs() < .045) {
        nearby.add(_normalize(lines[index + 1].text));
      }
      final joined = nearby.join(' ').toLowerCase();
      final values = _money(joined);
      final joinedHasPositiveLabel = positive.any(joined.contains);
      final rankedValues = joinedHasPositiveLabel && values.length > 1
          ? [values.last]
          : values;
      for (final value in rankedValues) {
        final identifierContext = RegExp(
          r'invoice(?:\s*(?:no|number|#))?|order(?:\s*(?:no|number|#))?|receipt\s*(?:no|number|#)?|transaction\s*(?:id|no|number)?|auth(?:orization)?|reference|\bref\b|terminal|register|store\s*(?:no|number|#)|member\s*id|loyalty\s*id',
          caseSensitive: false,
        ).hasMatch(joined);
        if (identifierContext) continue;
        var score = line.confidence * .25;
        final hasFinancialLabel = positive.any(joined.contains);
        final hasCurrencyMarker = RegExp(
          r'(?:\$|€|£|¥|\bUSD\b|\bEUR\b|\bGBP\b|\bCNY\b)',
          caseSensitive: false,
        ).hasMatch(joined);
        final hasCents = RegExp(r'\d+[.,]\d{2}\b').hasMatch(value);
        // A number without a label, currency marker, or cents formatting is
        // almost always an identifier, not a financial amount.
        if (!hasFinancialLabel && !hasCurrencyMarker && !hasCents) continue;
        if (hasFinancialLabel) score += .65;
        if (hasCurrencyMarker) score += .20;
        if (hasCents) score += .05;
        if (negative.any(joined.contains)) score -= .55;
        if (line.top > .60) score += .10;
        candidates.add((value: value, score: score));
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.first.score >= .45 ? candidates.first.value : null;
  }

  /// Explicit TOTAL-family labels are authoritative. Spatial data is used
  /// only to collect the value from the same OCR row, never to invent a total.
  static String? _explicitTotal(List<OcrObservation> lines) {
    const labels = [
      'grand total',
      'total due',
      'amount due',
      'total paid',
      'amount paid',
      'purchase total',
      'total',
    ];
    for (final label in labels) {
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        final normalized = _normalize(line.text).toLowerCase();
        if (!RegExp('\\b${RegExp.escape(label)}\\b').hasMatch(normalized)) {
          continue;
        }
        final row =
            lines.where((candidate) => _sameVisualRow(line, candidate)).toList()
              ..sort((a, b) => a.left.compareTo(b.left));
        final values = row.expand((value) => _money(value.text)).toList();
        if (values.isNotEmpty) return values.last;
      }
    }
    return null;
  }

  static bool _sameVisualRow(OcrObservation left, OcrObservation right) {
    if (left.height == 0 && right.height == 0) {
      return (left.top - right.top).abs() < .045;
    }
    final leftCenter = left.top + left.height / 2;
    final rightCenter = right.top + right.height / 2;
    final overlap =
        ((left.top + left.height) < (right.top + right.height)
            ? left.top + left.height
            : right.top + right.height) -
        (left.top > right.top ? left.top : right.top);
    final minimumHeight = left.height < right.height
        ? left.height
        : right.height;
    final hasMeaningfulOverlap = overlap >= minimumHeight * .25;
    final centerTolerance =
        (left.height > right.height ? left.height : right.height) * .65;
    return hasMeaningfulOverlap ||
        (leftCenter - rightCenter).abs() <= centerTolerance;
  }

  static String? _keyword(List<OcrObservation> lines, List<String> words) {
    for (var index = lines.length - 1; index >= 0; index--) {
      final current = _normalize(lines[index].text);
      final next =
          index + 1 < lines.length &&
              (lines[index + 1].top - lines[index].top).abs() < .16
          ? _normalize(lines[index + 1].text)
          : '';
      final joined = '$current $next';
      if (!words.any(joined.toLowerCase().contains)) continue;
      final values = _money(joined);
      if (values.isNotEmpty) return values.last;
    }
    return null;
  }

  static String _normalize(String value) {
    var normalized = value.toUpperCase().replaceAll(RegExp(r'[|]'), 'I');
    normalized = normalized.replaceAllMapped(
      RegExp(r'\b(T[0O]T[A4][L1]|AM[0O]UNT|V[1I]SA)\b'),
      (match) => switch (match.group(1)) {
        'T0TAL' || 'T0TA1' => 'TOTAL',
        'AM0UNT' => 'AMOUNT',
        'V1SA' => 'VISA',
        _ => match.group(0)!,
      },
    );
    return normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _redactCardEvidence(String value) => value.replaceAllMapped(
    RegExp(r'(?<!\d)(?:\d[\s-]*){13,19}(?!\d)'),
    (match) {
      final digits = match.group(0)!.replaceAll(RegExp(r'\D'), '');
      return '****${digits.substring(digits.length - 4)}';
    },
  );

  static List<String> _money(String value) {
    final output = <String>[];
    final regex = RegExp(
      r'(?<!\d)(?:USD|US\$|\$|EUR|€|GBP|£|CNY|RMB|¥)?\s*(\d{1,6}(?:[,\s]\d{3})*(?:[.,]\d{2})?)(?!\d)',
      caseSensitive: false,
    );
    for (final match in regex.allMatches(value)) {
      var amount = match.group(1)!.replaceAll(' ', '');
      if (amount.contains(',') && amount.contains('.')) {
        amount = amount.replaceAll(',', '');
      } else if (amount.contains(',') && RegExp(r',\d{2}$').hasMatch(amount)) {
        amount = amount.replaceAll(',', '.');
      } else {
        amount = amount.replaceAll(',', '');
      }
      output.add(amount);
    }
    return output;
  }

  static String? _currency(String text) {
    final upper = text.toUpperCase();
    if (upper.contains('EUR') || text.contains('€')) return 'EUR';
    if (upper.contains('GBP') || text.contains('£')) return 'GBP';
    if (upper.contains('CNY') || upper.contains('RMB') || text.contains('¥')) {
      return 'CNY';
    }
    if (upper.contains('USD') ||
        upper.contains('US\$') ||
        text.contains('\$')) {
      return 'USD';
    }
    return null;
  }

  static DateTime? _date(String text) {
    final monthNames = <String, int>{
      'JAN': 1,
      'FEB': 2,
      'MAR': 3,
      'APR': 4,
      'MAY': 5,
      'JUN': 6,
      'JUL': 7,
      'AUG': 8,
      'SEP': 9,
      'OCT': 10,
      'NOV': 11,
      'DEC': 12,
    };
    final named =
        RegExp(r'\b([A-Za-z]{3,9})\s+(\d{1,2})(?:,?\s+)(20\d{2}|\d{2})\b')
            .allMatches(text)
            .where((match) => !_dateIsExcluded(text, match.start))
            .firstOrNull;
    if (named != null) {
      final month = monthNames[named.group(1)!.substring(0, 3).toUpperCase()];
      final year = int.parse(named.group(3)!);
      final value = DateTime(
        year < 100 ? 2000 + year : year,
        month ?? 0,
        int.parse(named.group(2)!),
      );
      if (month != null &&
          value.month == month &&
          value.day == int.parse(named.group(2)!)) {
        return value;
      }
    }
    final patterns = [
      RegExp(r'(?<!\d)(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)'),
      RegExp(r'(?<!\d)(\d{1,2})[-/.](\d{1,2})[-/.](20\d{2}|\d{2})(?!\d)'),
    ];
    for (var index = 0; index < patterns.length; index++) {
      final match = patterns[index]
          .allMatches(text)
          .where((candidate) => !_dateIsExcluded(text, candidate.start))
          .firstOrNull;
      if (match == null) continue;
      final parsedYear = int.parse(
        index == 0 ? match.group(1)! : match.group(3)!,
      );
      final year = parsedYear < 100 ? 2000 + parsedYear : parsedYear;
      final month = int.parse(index == 0 ? match.group(2)! : match.group(1)!);
      final day = int.parse(index == 0 ? match.group(3)! : match.group(2)!);
      final value = DateTime(year, month, day);
      if (value.year == year && value.month == month && value.day == day) {
        return value;
      }
    }
    return null;
  }

  static bool _dateIsExcluded(String text, int start) {
    final context = text
        .substring(start > 32 ? start - 32 : 0, start)
        .toLowerCase();
    return RegExp(
      r'return\s+by|expires?|expiration|valid\s+through|membership\s+ends?|promo',
    ).hasMatch(context);
  }

  static _PaymentRegion _paymentRegion(List<OcrObservation> observations) {
    final indicators = RegExp(
      r'visa|master\s*card|mastercard|amex|american\s*express|discover|credit|debit|apple\s*pay|contactless|chip|ending|last\s*4|pan|acct|account|x{2,}|\*{2,}|•{2,}',
      caseSensitive: false,
    );
    final anchors = <int>[];
    for (var index = 0; index < observations.length; index++) {
      if (indicators.hasMatch(observations[index].text)) anchors.add(index);
    }
    if (anchors.isEmpty) return const _PaymentRegion();
    final selected = <OcrObservation>[];
    for (final index in anchors) {
      final anchor = observations[index];
      for (var candidate = 0; candidate < observations.length; candidate++) {
        final line = observations[candidate];
        final sameRegion =
            (line.top - anchor.top).abs() <= .40 &&
            (line.left - anchor.left).abs() <= .75;
        final syntheticNeighbor =
            line.height == 0 &&
            anchor.height == 0 &&
            (line.top - anchor.top).abs() <= 2;
        if (sameRegion || syntheticNeighbor) selected.add(line);
      }
    }
    final region = selected.toSet().map((line) => line.text).join(' ');
    final upper = _normalize(region);
    final network = switch (true) {
      _ when upper.contains('AMERICAN EXPRESS') || upper.contains('AMEX') =>
        'American Express',
      _ when upper.contains('MASTERCARD') || upper.contains('MASTER CARD') =>
        'Mastercard',
      _ when upper.contains('VISA') => 'Visa',
      _ when upper.contains('DISCOVER') => 'Discover',
      _ => null,
    };
    final type = upper.contains('DEBIT')
        ? 'debit'
        : upper.contains('CREDIT')
        ? 'credit'
        : null;
    final completePanLastFour = RegExp(
      r'(?<!\d)\d{4}[\s-]*\d{4}[\s-]*\d{4}[\s-]*(\d{4})(?!\d)',
    ).firstMatch(region)?.group(1);
    final lastFour =
        completePanLastFour ??
        RegExp(
          r'(?:visa|master\s*card|amex|american\s*express|discover|debit|credit|apple\s*pay|ending(?:\s+in)?|last\s*4|card|pan|acct|account|x{2,}|\*{2,}|•{2,})[^\d]{0,20}(\d{4})(?!\d)',
          caseSensitive: false,
        ).firstMatch(region)?.group(1);
    final expiry = RegExp(
      r'(?:EXP|EXPIRY|EXPIRATION|VALID\s*THRU|GOOD\s*THRU)\s*[:.]?\s*(0[1-9]|1[0-2])\s*[/ -]\s*(\d{2,4})',
      caseSensitive: false,
    ).firstMatch(region);
    return _PaymentRegion(
      network: network,
      type: type,
      lastFour: lastFour,
      expiry: expiry == null ? null : '${expiry.group(1)}/${expiry.group(2)}',
    );
  }

  static String _iso(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

final class _ReceiptFields {
  const _ReceiptFields({
    this.merchant,
    this.amount,
    this.currency,
    this.date,
    this.tax,
    this.tip,
    this.cardLast4,
    this.cardNetwork,
    this.cardType,
    this.cardExpiry,
    required this.confidence,
    required this.evidence,
    required this.lines,
  });
  final String? merchant,
      amount,
      currency,
      tax,
      tip,
      cardLast4,
      cardNetwork,
      cardType,
      cardExpiry;
  final DateTime? date;
  final Map<String, double> confidence;
  final Map<String, String> evidence;
  final List<String> lines;
}

final class _PaymentRegion {
  const _PaymentRegion({this.network, this.type, this.lastFour, this.expiry});
  final String? network;
  final String? type;
  final String? lastFour;
  final String? expiry;
}
