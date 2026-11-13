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
    final total = candidates.singleWhere((entry) => entry['field'] == 'total');
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
    const text =
        '      SHOP NAME\n'
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

  test('savings, discounts and pre-discount totals never become payable totals', () {
    const text =
        '      RECEIPT\n'
        '      MARKET\n'
        '      TOTAL SAVINGS               5.00\n'
        '      TOTAL DISCOUNT              4.00\n'
        '      TOTAL BEFORE DISCOUNT      18.00\n'
        '      SUBTOTAL                   14.00\n'
        '      TAX                         1.12\n'
        '      TOTAL                      15.12\n';
    final parsed = ReceiptTextJson.parse(text);
    final candidates = (parsed['candidates'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final totals = candidates.where((entry) => entry['field'] == 'total');
    expect(totals, hasLength(1));
    expect(totals.single['valueText'], '15.12');
    final unparsed = (parsed['unparsedLines'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(
      unparsed.where(
        (entry) => (entry['sourceText'] as String).contains('TOTAL '),
      ),
      hasLength(3),
    );
    expect(
      candidates.singleWhere((entry) => entry['field'] == 'subtotal')['valueText'],
      '14.00',
    );
  });

  test('generic headings are not merchant names; preserve alternative candidates', () {
    const text =
        'RECEIPT\n'
        'WHOLE FOODS MARKET\n'
        'FOODS GROUP LLC\n'
        'Palo Alto, CA\n'
        'Date: 11/12/2026\n'
        'TOTAL 10.91\n';
    final parsed = ReceiptTextJson.parse(text);
    final candidates = (parsed['candidates'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final merchants = candidates
        .where((entry) => entry['field'] == 'merchantCandidate')
        .map((entry) => entry['valueText'])
        .toList();
    expect(merchants, ['WHOLE FOODS MARKET', 'FOODS GROUP LLC']);
    expect(
      candidates.singleWhere((entry) => entry['field'] == 'date')['valueText'],
      '11/12/2026',
    );
  });

  test('card expiry is not a transaction date; unlabeled dates remain candidates', () {
    const text =
        'MARKET\n'
        'CARD EXP 12/25/2028\n'
        '2026-11-13\n'
        'PURCHASE DATE: 11/12/2026\n'
        'TOTAL 22.00\n';
    final parsed = ReceiptTextJson.parse(text);
    final candidates = (parsed['candidates'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(candidates.where((entry) => entry['field'] == 'date'), hasLength(1));
    expect(
      candidates.where((entry) => entry['field'] == 'dateCandidate'),
      isEmpty,
    );
    final unparsed = (parsed['unparsedLines'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(
      unparsed.any((entry) => (entry['sourceText'] as String).contains('CARD EXP')),
      isTrue,
    );
  });

  test('restaurant tips, credits, international decimals and absent totals', () {
    const text =
        'RESTAURANT\n'
        'SUBTOTAL                   20.00\n'
        'TIP                         3.00\n'
        'GRAND TOTAL                23.00\n'
        'REFUND                     -5.00\n'
        'TOTAL                     -12.50\n'
        'TAX                          1,50\n';
    final parsed = ReceiptTextJson.parse(text);
    final candidates = (parsed['candidates'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(
      candidates.singleWhere((entry) => entry['field'] == 'tip')['valueText'],
      '3.00',
    );
    expect(
      candidates.where((entry) => entry['field'] == 'total').length,
      2,
    );
    expect(
      candidates.lastWhere((entry) => entry['field'] == 'total')['valueText'],
      '-12.50',
    );
    expect(
      candidates.singleWhere((entry) => entry['field'] == 'tax')['valueText'],
      '1,50',
    );
    final unresolved = ReceiptTextJson.parse('TOTAL\nPAYMENT 23.00\n');
    expect(
      (unresolved['candidates'] as List<dynamic>)
          .where((entry) => (entry as Map<String, dynamic>)['field'] == 'total'),
      isEmpty,
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
