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
  const ReceiptOcrResult({
    required this.rawText,
    this.observations = const [],
    this.fieldConfidence = const {},
    this.fieldEvidence = const {},
    this.merchant,
    this.amount,
    this.currency,
    this.date,
    this.tax,
    this.tip,
    this.cardLast4,
  });

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

  Map<String, String> toExtractionValues() {
    final values = <String, String>{'rawText': rawText};
    if (observations.isNotEmpty) {
      values['observationCount'] = observations.length.toString();
    }
    for (final entry in fieldConfidence.entries) {
      values['${entry.key}Confidence'] = entry.value.toStringAsFixed(3);
    }
    for (final entry in fieldEvidence.entries) {
      values['${entry.key}Evidence'] = entry.value;
    }
    if (merchant case final value?) values['merchant'] = value;
    if (amount case final value?) values['amount'] = value;
    if (currency case final value?) values['currency'] = value;
    if (date case final value?) values['date'] = _iso(value);
    if (tax case final value?) values['tax'] = value;
    if (tip case final value?) values['tip'] = value;
    if (cardLast4 case final value?) values['cardLast4'] = value;
    return values;
  }

  static String _iso(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
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
    return CardTextParser.parse(text);
  }
}

final class CardScanResult {
  const CardScanResult({this.issuer, this.lastFour, this.type});

  final String? issuer;
  final String? lastFour;
  final PaymentSourceType? type;
}

abstract final class CardTextParser {
  static CardScanResult parse(String text) {
    final upper = text.toUpperCase();
    final issuer = switch (true) {
      _ when upper.contains('AMERICAN EXPRESS') || upper.contains('AMEX') =>
        'American Express',
      _ when upper.contains('MASTERCARD') => 'Mastercard',
      _ when upper.contains('VISA') => 'Visa',
      _ when upper.contains('DISCOVER') => 'Discover',
      _ => null,
    };
    final lastFour = RegExp(
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
                      .map(
                        (line) => OcrObservation(
                          text: line,
                          confidence: 0.5,
                          left: 0,
                          top: 0,
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
    );
  }

  static _ReceiptFields _extract(List<OcrObservation> observations) {
    final ordered = [...observations]..sort((a, b) => a.top.compareTo(b.top));
    final text = ordered.map((line) => line.text).join('\n');
    final lines = ordered.map((line) => line.text.trim()).toList();
    final merchant = _merchant(ordered);
    final amount =
        _keyword(ordered, const ['grand total', 'amount due', 'total']) ??
        _largest(ordered);
    final tax = _keyword(ordered, const ['sales tax', 'tax']);
    final tip = _keyword(ordered, const ['tip', 'gratuity']);
    final date = _date(text);
    final currency = _currency(text);
    final cardLast4 = _last4(text);
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
      evidence[key] = source.text;
    }

    record('merchant', merchant);
    record('amount', amount, 0.8);
    record('tax', tax, 0.8);
    record('tip', tip, 0.8);
    record('currency', currency, 0.7);
    record('date', date == null ? null : _iso(date));
    record('cardLast4', cardLast4, 0.8);
    return _ReceiptFields(
      merchant: merchant,
      amount: amount,
      currency: currency,
      date: date,
      tax: tax,
      tip: tip,
      cardLast4: cardLast4,
      confidence: confidence,
      evidence: evidence,
      lines: lines,
    );
  }

  static String? _merchant(List<OcrObservation> observations) {
    for (final line in observations.take(6)) {
      final value = line.text.trim();
      if (value.length < 2 || value.length > 60) continue;
      if (RegExp(r'^\d[\d\s./:-]*$').hasMatch(value)) continue;
      if (_money(value).isNotEmpty) continue;
      if (RegExp(
        r'receipt|invoice|thank you|date|tel',
        caseSensitive: false,
      ).hasMatch(value)) {
        continue;
      }
      return value;
    }
    return observations.isEmpty ? null : observations.first.text.trim();
  }

  static String? _keyword(List<OcrObservation> lines, List<String> words) {
    for (final line in lines.reversed) {
      if (!words.any(line.text.toLowerCase().contains)) continue;
      final values = _money(line.text);
      if (values.isNotEmpty) return values.last;
    }
    return null;
  }

  static String? _largest(List<OcrObservation> lines) {
    final values = lines.expand((line) => _money(line.text)).toList();
    if (values.isEmpty) return null;
    values.sort(
      (a, b) => (double.tryParse(b) ?? 0).compareTo(double.tryParse(a) ?? 0),
    );
    return values.first;
  }

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
    final patterns = [
      RegExp(r'(?<!\d)(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)'),
      RegExp(r'(?<!\d)(\d{1,2})[-/.](\d{1,2})[-/.](20\d{2})(?!\d)'),
    ];
    for (var index = 0; index < patterns.length; index++) {
      final match = patterns[index].firstMatch(text);
      if (match == null) continue;
      final year = int.parse(index == 0 ? match.group(1)! : match.group(3)!);
      final month = int.parse(index == 0 ? match.group(2)! : match.group(1)!);
      final day = int.parse(index == 0 ? match.group(3)! : match.group(2)!);
      final value = DateTime(year, month, day);
      if (value.year == year && value.month == month && value.day == day) {
        return value;
      }
    }
    return null;
  }

  static String? _last4(String text) => RegExp(
    r'(?:visa|mastercard|master\s*card|amex|american\s*express|discover|debit|credit|apple\s*pay|ending|last\s*4|card|x{2,}|\*{2,})[^\d]{0,16}(\d{4})(?!\d)',
    caseSensitive: false,
  ).firstMatch(text)?.group(1);

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
    required this.confidence,
    required this.evidence,
    required this.lines,
  });
  final String? merchant, amount, currency, tax, tip, cardLast4;
  final DateTime? date;
  final Map<String, double> confidence;
  final Map<String, String> evidence;
  final List<String> lines;
}
