import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/receipt_layout_fixture.dart';
import 'support/receipt_text_json.dart';

void main() {
  final path = 'test/core/evidence/fixtures/receipt_layout_grocery.json';

  ReceiptLayoutFixture load() => ReceiptLayoutFixture.fromJson(
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
  );

  test(
    'spatial fixture preserves source observations and renders receipt rows',
    () {
      final fixture = load();
      final observations = fixture.document.observations;
      expect(observations, hasLength(17));
      expect(observations[0].text, 'WHOLE FOODS MARKET');
      expect(observations[12].text, r'$10.91');
      expect(observations[12].normalizedBounds.left, .76);
      expect(observations[12].pageIndex, 0);
      expect(observations[12].order, 12);
      expect(observations[12].confidence, .96);
      final layout = fixture.layout;
      expect(layout, contains('WHOLE FOODS MARKET'));
      expect(layout, contains('TOTAL'));
      final totalLine = layout
          .split('\n')
          .firstWhere((line) => line.trimLeft().startsWith('TOTAL'));
      expect(totalLine, contains(r'$10.91'));
      expect(
        totalLine.indexOf(r'$10.91'),
        greaterThan(totalLine.indexOf('TOTAL')),
      );
      expect(layout, contains('CHANGE'));
    },
  );

  test('companion text file reproduces the JSON OCR coordinates', () {
    final fixture = load();
    final textPath = '${path.substring(0, path.length - 5)}.txt';
    final snapshot = File(textPath).readAsStringSync();
    expect(snapshot, '${fixture.layout}\n');
    final lines = snapshot.split('\n');
    expect(
      lines.firstWhere((line) => line.contains('Organic Milk')),
      contains('5.99'),
    );
    expect(
      lines.firstWhere(
        (line) => line.contains('TOTAL') && !line.contains('SUB'),
      ),
      contains(r'$10.91'),
    );
    expect(lines.where((line) => line.isEmpty).length, greaterThanOrEqualTo(2));
  });

  test('derived JSON is generated from the saved aligned TXT', () {
    final text = File(
      '${path.substring(0, path.length - 5)}.txt',
    ).readAsStringSync();
    final snapshot = File(
      '${path.substring(0, path.length - 5)}.extracted.json',
    ).readAsStringSync();
    expect(snapshot, '${ReceiptTextJson.encode(text)}\n');

    final parsed = jsonDecode(snapshot) as Map<String, dynamic>;
    expect(parsed['source'], 'position-aligned-text');
    final candidates = (parsed['candidates'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final subtotal = candidates.singleWhere(
      (entry) => entry['field'] == 'subtotal',
    );
    expect(subtotal['valueText'], '10.49');
    final total = candidates.singleWhere(
      (entry) => entry['field'] == 'total',
    );
    expect(total['valueText'], r'$10.91');
    expect(total['sourceText'], contains('TOTAL'));
    expect(total['sourceLine'], isA<int>());
    final merchant = candidates.singleWhere(
      (entry) => entry['field'] == 'merchantCandidate',
    );
    expect(merchant['valueText'], 'WHOLE FOODS MARKET');
    expect(merchant.containsKey('confidence'), isFalse);
    expect(merchant.containsKey('bounds'), isFalse);
  });

  test('missing labeled amounts remain unparsed, not guessed', () {
    const text = '      SHOP NAME\n'
        '      TOTAL\n'
        '      VISA                  20.00\n';
    final parsed = ReceiptTextJson.parse(text);
    final candidates = (parsed['candidates'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(candidates.where((row) => row['field'] == 'total'), isEmpty);
    expect(
      (parsed['unparsedLines'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .any((row) => row['sourceText'] == '      TOTAL'),
      isTrue,
    );
  });

  test('production extractor runs against original OCR observations', () {
    final fixture = load();
    final result = fixture.extract();
    expect(
      result.merchant,
      fixture.expected['merchant'],
      reason: fixture.diagnosticReport,
    );
    expect(
      result.amount,
      fixture.expected['amount'],
      reason: fixture.diagnosticReport,
    );
    expect(
      result.currency,
      fixture.expected['currency'],
      reason: fixture.diagnosticReport,
    );
    expect(
      result.date?.toIso8601String().substring(0, 10),
      fixture.expected['date'],
      reason: fixture.diagnosticReport,
    );
    expect(
      result.tax,
      fixture.expected['tax'],
      reason: fixture.diagnosticReport,
    );
    expect(result.observations, hasLength(17));
    expect(fixture.diagnosticReport, contains('PASS merchant'));
    expect(fixture.diagnosticReport, contains('evidence='));
  });

  test(
    'JSON export round-trips original OCR geometry without rewriting text',
    () {
      final original = load();
      final encoded = ReceiptLayoutFixture.encodeDocument(
        id: original.id,
        document: original.document,
        expected: original.expected,
      );
      final decoded = ReceiptLayoutFixture.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      expect(decoded.id, original.id);
      expect(decoded.expected, original.expected);
      expect(decoded.document.text, original.document.text);
      expect(decoded.document.pages.first.pixelWidth, 1200);
      expect(decoded.document.pages.first.pixelHeight, 1800);
      for (
        var index = 0;
        index < original.document.observations.length;
        index++
      ) {
        final before = original.document.observations[index];
        final after = decoded.document.observations[index];
        expect(after.text, before.text);
        expect(after.confidence, before.confidence);
        expect(after.order, before.order);
        expect(after.pageIndex, before.pageIndex);
        expect(after.normalizedBounds.left, before.normalizedBounds.left);
        expect(after.normalizedBounds.top, before.normalizedBounds.top);
        expect(after.normalizedBounds.width, before.normalizedBounds.width);
        expect(after.normalizedBounds.height, before.normalizedBounds.height);
      }
    },
  );

  test(
    'missing geometry remains in OCR reading order, not invented columns',
    () {
      final fixture = ReceiptLayoutFixture.fromJson({
        'id': 'no-bounds',
        'pages': [
          {
            'index': 0,
            'observations': [
              {'text': 'MERCHANT', 'confidence': .9, 'order': 0},
              {'text': 'TOTAL 8.50', 'confidence': .9, 'order': 1},
            ],
          },
        ],
        'expected': <String, String?>{},
      });
      expect(fixture.layout, 'MERCHANT\nTOTAL 8.50');
    },
  );

  test('JSON fixture retains explicit bounding-box representation', () {
    final document = OcrDocument(
      pages: const [
        OcrPage(
          index: 0,
          observations: [
            OcrObservation(
              text: 'TOTAL 7.00',
              confidence: .8,
              bounds: OcrBounds(left: .1, top: .6, width: .8, height: .05),
              order: 0,
            ),
          ],
        ),
      ],
      diagnostics: const OcrDiagnostics(
        sourceKind: OcrSourceKind.image,
        sourceOpened: true,
        pageCount: 1,
        observationCount: 1,
        recognizedLineCount: 1,
        observationsWithBounds: 1,
      ),
    );
    final raw = ReceiptLayoutFixture.encodeDocument(
      id: 'boxed',
      document: document,
      expected: {'amount': '7.00'},
    );
    final fixture = ReceiptLayoutFixture.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    expect(fixture.document.observations.single.bounds, isNotNull);
    expect(fixture.document.observations.single.normalizedBounds.top, .6);
  });
}
