import 'package:flutter/services.dart';

final class ReceiptOcrResult {
  const ReceiptOcrResult({
    required this.rawText,
    this.merchant,
    this.amount,
    this.currency,
    this.date,
    this.tax,
    this.tip,
    this.cardLast4,
  });

  final String rawText;
  final String? merchant;
  final String? amount;
  final String? currency;
  final DateTime? date;
  final String? tax;
  final String? tip;
  final String? cardLast4;

  Map<String, String> toExtractionValues() => {
    'rawText': rawText,
    if (merchant != null) 'merchant': merchant!,
    if (amount != null) 'amount': amount!,
    if (currency != null) 'currency': currency!,
    if (date != null) 'date': _iso(date!),
    if (tax != null) 'tax': tax!,
    if (tip != null) 'tip': tip!,
    if (cardLast4 != null) 'cardLast4': cardLast4!,
  };

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
    return ReceiptTextParser.parse(text);
  }
}

abstract final class ReceiptTextParser {
  static ReceiptOcrResult parse(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    return ReceiptOcrResult(
      rawText: text,
      merchant: _merchant(lines),
      amount:
          _keyword(lines, const ['grand total', 'amount due', 'total']) ??
          _largest(lines),
      currency: _currency(text),
      date: _date(text),
      tax: _keyword(lines, const ['tax', 'sales tax']),
      tip: _keyword(lines, const ['tip', 'gratuity']),
      cardLast4: _last4(text),
    );
  }

  static String? _merchant(List<String> lines) {
    for (final line in lines.take(5)) {
      if (line.length < 2 || line.length > 60) continue;
      if (RegExp(r'^\d[\d\s./:-]*$').hasMatch(line)) continue;
      if (_money(line).isNotEmpty) continue;
      return line;
    }
    return lines.isEmpty ? null : lines.first;
  }

  static String? _keyword(List<String> lines, List<String> words) {
    for (final line in lines.reversed) {
      final lower = line.toLowerCase();
      if (!words.any(lower.contains)) continue;
      final values = _money(line);
      if (values.isNotEmpty) return values.last;
    }
    return null;
  }

  static String? _largest(List<String> lines) {
    final values = lines.expand(_money).toList(growable: false);
    if (values.isEmpty) return null;
    values.sort(
      (left, right) => (double.tryParse(right) ?? 0).compareTo(
        double.tryParse(left) ?? 0,
      ),
    );
    return values.first;
  }

  static List<String> _money(String value) {
    final output = <String>[];
    final regex = RegExp(
      r'(?<!\d)(?:USD|US\$|\$|EUR|€|GBP|£|CNY|RMB|¥)?\s*'
      r'(\d{1,6}(?:[,\s]\d{3})*(?:[.,]\d{2}))(?!\d)',
      caseSensitive: false,
    );
    for (final match in regex.allMatches(value)) {
      var amount = match.group(1)!.replaceAll(' ', '');
      if (amount.contains(',') && amount.contains('.')) {
        amount = amount.replaceAll(',', '');
      } else if (amount.contains(',') &&
          RegExp(r',\d{2}$').hasMatch(amount)) {
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
    if (upper.contains('CNY') || upper.contains('RMB')) return 'CNY';
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
      final year = int.parse(
        index == 0 ? match.group(1)! : match.group(3)!,
      );
      final month = int.parse(
        index == 0 ? match.group(2)! : match.group(1)!,
      );
      final day = int.parse(
        index == 0 ? match.group(3)! : match.group(2)!,
      );
      final value = DateTime(year, month, day);
      if (value.year == year && value.month == month && value.day == day) {
        return value;
      }
    }
    return null;
  }

  static String? _last4(String text) => RegExp(
    r'(?:ending|card|visa|mastercard|amex|discover|x{2,}|\*{2,})'
    r'[^\d]{0,8}(\d{4})(?!\d)',
    caseSensitive: false,
  ).firstMatch(text)?.group(1);
}
