import 'dart:convert';

import 'package:butlerly/core/evidence/statement_extractor.dart';

import 'receipt_layout_fixture.dart';

/// Statement-specific test fixture; reuses the exact OCR geometry serializer
/// and text-layout renderer validated for receipts.
final class StatementLayoutFixture {
  const StatementLayoutFixture({
    required this.ocr,
    required this.expectedRows,
  });

  factory StatementLayoutFixture.fromJson(Map<String, dynamic> json) {
    final rows = (json['expectedRows'] as List<dynamic>).map((value) {
      final row = value as Map<String, dynamic>;
      return row.map((key, value) => MapEntry(key, value as String?));
    }).toList(growable: false);
    return StatementLayoutFixture(
      ocr: ReceiptLayoutFixture.fromJson({
        ...json,
        'expected': <String, String?>{},
      }),
      expectedRows: rows,
    );
  }

  final ReceiptLayoutFixture ocr;
  final List<Map<String, String?>> expectedRows;

  String get id => ocr.id;
  String get layout => ocr.layout;

  /// Preserve original OcrDocument and observation geometry for the
  /// production statement extractor; layout text is diagnostics only.
  StatementExtraction extract() =>
      const LocalStatementExtractor().extractDocument(ocr.document);

  String get diagnosticReport {
    final rows = extract().rows;
    final details = <String>[];
    for (var i = 0; i < expectedRows.length; i++) {
      if (i >= rows.length) {
        details.add('FAIL row ${i + 1}: missing');
        continue;
      }
      final actual = rows[i];
      final values = <String, String?>{
        'date': actual.date?.toIso8601String().substring(0, 10),
        'postingDate': actual.postingDate?.toIso8601String().substring(0, 10),
        'description': actual.description,
        'amount': actual.amount,
        'currency': actual.currency,
        'direction': actual.direction,
      };
      for (final field in expectedRows[i].entries) {
        details.add(
          '${values[field.key] == field.value ? 'PASS' : 'FAIL'} '
          'row ${i + 1} ${field.key}: '
          'expected=${field.value ?? '(null)'} '
          'actual=${values[field.key] ?? '(null)'}',
        );
      }
    }
    if (rows.length != expectedRows.length) {
      details.add(
        'FAIL row count: expected=${expectedRows.length} actual=${rows.length}',
      );
    }
    return 'Statement fixture: $id\n$layout\n\n${details.join('\n')}';
  }

  /// For redacted fixture creation; no statement rows or inferred fields are
  /// silently inserted into the original OCR observation payload.
  static String encodeDocument({
    required String id,
    required OcrDocument document,
    required List<Map<String, String?>> expectedRows,
  }) {
    final raw = jsonDecode(
      ReceiptLayoutFixture.encodeDocument(
        id: id,
        document: document,
        expected: const {},
      ),
    ) as Map<String, dynamic>;
    raw.remove('expected');
    raw['expectedRows'] = expectedRows;
    return const JsonEncoder.withIndent('  ').convert(raw);
  }
}
