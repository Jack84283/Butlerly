import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/statement_layout_fixture.dart';
import 'support/statement_text_json.dart';

void main() {
  const path = 'test/core/evidence/fixtures/statement_layout_card.json';

  StatementLayoutFixture load() => StatementLayoutFixture.fromJson(
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
  );

  test('aligned TXT snapshot corresponds to original statement JSON', () {
    final fixture = load();
    final snapshot = File(
      '${path.substring(0, path.length - 5)}.txt',
    ).readAsStringSync();
    expect(snapshot, '${fixture.layout}\n');
    final lines = snapshot.split('\n');
    expect(
      lines.firstWhere((line) => line.contains('SAFEWAY STORE')),
      contains(r'$42.19'),
    );
    expect(
      lines.firstWhere((line) => line.contains('CAFE')),
      contains(r'$8.25'),
    );
    expect(
      lines.indexWhere((line) => line.contains('HARBOR CARD')),
      lessThan(lines.indexWhere((line) => line.contains('SAFEWAY STORE'))),
    );
  });

  test('semantic JSON is built from the saved TXT, not OCR fixture fields', () {
    final text = File(
      '${path.substring(0, path.length - 5)}.txt',
    ).readAsStringSync();
    final snapshot = File(
      '${path.substring(0, path.length - 5)}.extracted.json',
    ).readAsStringSync();
    expect(snapshot, '${StatementTextJson.encode(text)}\n');
    final result = jsonDecode(snapshot) as Map<String, dynamic>;
    expect(result['source'], 'position-aligned-text');
    final rows = result['rows'] as List<dynamic>;
    expect(rows, hasLength(2));
    final first = rows.first as Map<String, dynamic>;
    expect(first['transactionDateText'], '8/15');
    expect(first['postingDateText'], '8/17');
    expect(first['description'], 'SAFEWAY STORE');
    expect(first['amountText'], r'$42.19');
    expect(first['status'], 'transcribed');
    expect(first['sourceText'], contains('SAFEWAY STORE'));
    expect(first.containsKey('confidence'), isFalse);
    expect(first.containsKey('bounds'), isFalse);
  });

  test('incomplete statement rows remain unresolved when TXT lacks amount', () {
    const text = 'Purchase Date Post Date   Description             Amount\n'
        '8/15          8/17         GROCER\n';
    final result = StatementTextJson.parse(text);
    final rows = result['rows']! as List<dynamic>;
    expect(rows, hasLength(1));
    final row = rows.first as Map<String, dynamic>;
    expect(row['amountText'], isNull);
    expect(row['status'], 'unresolved');
    expect(row['description'], 'GROCER');
  });

  test('OCR statement observations retain geometry and order', () {
    final fixture = load();
    final lines = fixture.ocr.document.observations;
    expect(lines, hasLength(14));
    expect(lines[9].text, r'$42.19');
    expect(lines[9].normalizedBounds.left, .82);
    expect(lines[9].normalizedBounds.top, .34);
    expect(lines[9].confidence, .96);
    expect(lines[9].order, 9);
    expect(lines[9].pageIndex, 0);
    expect(fixture.ocr.document.pages.first.pixelWidth, 1200);
  });

  test('fixture extraction uses original observations, not TXT alignment', () {
    final fixture = load();
    final result = fixture.extract();
    expect(
      result.rows,
      hasLength(fixture.expectedRows.length),
      reason: fixture.diagnosticReport,
    );
    for (var i = 0; i < fixture.expectedRows.length; i++) {
      final expected = fixture.expectedRows[i];
      final row = result.rows[i];
      expect(
        row.date?.toIso8601String().substring(0, 10),
        expected['date'],
        reason: fixture.diagnosticReport,
      );
      expect(
        row.postingDate?.toIso8601String().substring(0, 10),
        expected['postingDate'],
        reason: fixture.diagnosticReport,
      );
      expect(
        row.description,
        expected['description'],
        reason: fixture.diagnosticReport,
      );
      expect(row.amount, expected['amount'], reason: fixture.diagnosticReport);
    }
  });

  test('JSON export round-trips original OCR text and bounding geometry', () {
    final fixture = load();
    final encoded = StatementLayoutFixture.encodeDocument(
      id: fixture.id,
      document: fixture.ocr.document,
      expectedRows: fixture.expectedRows,
    );
    final restored = StatementLayoutFixture.fromJson(
      jsonDecode(encoded) as Map<String, dynamic>,
    );
    expect(restored.expectedRows, fixture.expectedRows);
    expect(restored.ocr.document.text, fixture.ocr.document.text);
    for (var i = 0; i < fixture.ocr.document.observations.length; i++) {
      final a = fixture.ocr.document.observations[i];
      final b = restored.ocr.document.observations[i];
      expect(b.text, a.text);
      expect(b.order, a.order);
      expect(b.pageIndex, a.pageIndex);
      expect(b.confidence, a.confidence);
      expect(b.normalizedBounds.left, a.normalizedBounds.left);
      expect(b.normalizedBounds.top, a.normalizedBounds.top);
      expect(b.normalizedBounds.width, a.normalizedBounds.width);
      expect(b.normalizedBounds.height, a.normalizedBounds.height);
    }
  });

  test('multi-page statements preserve page separators and reading order', () {
    final fixture = StatementLayoutFixture.fromJson({
      'id': 'two-pages',
      'pages': [
        {
          'index': 0,
          'observations': [
            {'text': 'PAGE ONE', 'confidence': .9, 'order': 0},
          ],
        },
        {
          'index': 1,
          'observations': [
            {'text': 'PAGE TWO', 'confidence': .9, 'order': 0},
          ],
        },
      ],
      'expectedRows': <Object>[],
    });
    expect(fixture.layout, 'PAGE ONE\n--- PAGE 2 ---\nPAGE TWO');
  });

  test(
    'the original OCR document can be passed to the statement extractor',
    () {
      final fixture = load();
      expect(fixture.ocr.document, isA<OcrDocument>());
      expect(fixture.ocr.document.text, contains('Statement period:'));
      expect(fixture.ocr.document.text, contains('SAFEWAY STORE'));
    },
  );
}
