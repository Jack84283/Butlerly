import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:butlerly/core/evidence/ocr_spatial_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('side-by-side labels and values preserve receipt geometry', () {
    final observations = [
      const OcrObservation(
        text: r'Amount: $2.99',
        confidence: .96,
        bounds: OcrBounds(left: .28, top: .05, width: .46, height: .05),
        order: 0,
      ),
      const OcrObservation(
        text: '9988',
        confidence: .96,
        bounds: OcrBounds(left: .46, top: .20, width: .10, height: .035),
        order: 1,
      ),
      const OcrObservation(
        text: 'Card',
        confidence: .96,
        bounds: OcrBounds(left: .19, top: .20, width: .09, height: .035),
        order: 2,
      ),
      const OcrObservation(
        text: 'Ending In',
        confidence: .96,
        bounds: OcrBounds(left: .19, top: .25, width: .15, height: .035),
        order: 3,
      ),
      const OcrObservation(
        text: 'Merchant',
        confidence: .96,
        bounds: OcrBounds(left: .19, top: .41, width: .18, height: .035),
        order: 4,
      ),
      const OcrObservation(
        text: 'APPLE.COM/BILL',
        confidence: .96,
        bounds: OcrBounds(left: .45, top: .41, width: .38, height: .035),
        order: 5,
      ),
      const OcrObservation(
        text: '866-712-7753 US',
        confidence: .96,
        bounds: OcrBounds(left: .45, top: .46, width: .39, height: .035),
        order: 6,
      ),
      const OcrObservation(
        text: 'Date',
        confidence: .96,
        bounds: OcrBounds(left: .19, top: .57, width: .10, height: .035),
        order: 7,
      ),
      const OcrObservation(
        text: '11/13/2026',
        confidence: .96,
        bounds: OcrBounds(left: .45, top: .57, width: .22, height: .035),
        order: 8,
      ),
    ];
    const raw =
        'Amount: \$2.99\n9988\nCard\nEnding In\n'
        'Merchant\nDate\nAPPLE.COM/BILL\n866-712-7753 US\n11/13/2026';
    final positioned = OcrSpatialText.render(
      rawText: raw,
      observations: observations,
    );
    expect(OcrSpatialText.hasGeometry(observations), isTrue);
    final lines = positioned.split('\n');
    expect(
      lines.singleWhere((line) => line.contains('Card')),
      matches(RegExp(r'Card\s+9988')),
    );
    expect(
      lines.singleWhere((line) => line.contains('Merchant')),
      matches(RegExp(r'Merchant\s+APPLE.COM/BILL')),
    );
    expect(
      lines.singleWhere((line) => line.contains('Date')),
      matches(RegExp(r'Date\s+11/13/2026')),
    );
    expect(
      lines.singleWhere((line) => line.contains('866-712-7753')),
      startsWith(' ' * 29),
    );
    expect(positioned, isNot(raw));
  });

  test('receipt OCR result keeps explicit bounding boxes after sanitizing', () {
    const source = OcrObservation(
      text: 'APPLE.COM/BILL',
      confidence: .9,
      bounds: OcrBounds(left: .45, top: .4, width: .35, height: .03),
      order: 3,
    );
    final receipt = ReceiptOcrResult(
      rawText: 'APPLE.COM/BILL',
      observations: const [source],
    );
    final restored = receipt.observations.single;
    expect(restored.bounds, isNotNull);
    expect(restored.normalizedBounds.left, .45);
    expect(restored.normalizedBounds.top, .4);
    expect(restored.order, 3);
    expect(OcrSpatialText.hasGeometry(receipt.observations), isTrue);
  });

  test('missing or partial geometry preserves original OCR text', () {
    const raw = '9988\nCard\nMerchant\nAPPLE.COM/BILL';
    expect(OcrSpatialText.render(rawText: raw, observations: []), raw);
    expect(
      OcrSpatialText.render(
        rawText: raw,
        observations: const [
          OcrObservation(text: 'Card', confidence: .9, order: 1),
        ],
      ),
      raw,
    );
    final partiallyPositioned = OcrSpatialText.render(
      rawText: raw,
      observations: const [
        OcrObservation(
          text: 'Card',
          confidence: .9,
          bounds: OcrBounds(left: .1, top: .2, width: .2, height: .03),
        ),
        OcrObservation(text: '9988', confidence: .9),
      ],
    );
    expect(partiallyPositioned, contains('Card'));
    expect(partiallyPositioned, contains('--- TEXT WITHOUT POSITION ---'));
    expect(partiallyPositioned, contains('9988'));
    expect(
      OcrSpatialText.hasGeometry(const [
        OcrObservation(
          text: 'Card',
          bounds: OcrBounds(left: .1, top: .2, width: .2, height: .03),
        ),
        OcrObservation(text: '9988'),
      ]),
      isTrue,
    );
  });

  test(
    'large and small fonts share baselines, wrapped text stays separate',
    () {
      const lines = [
        OcrObservation(
          text: 'MERCHANT',
          bounds: OcrBounds(left: .10, top: .20, width: .25, height: .065),
        ),
        OcrObservation(
          text: 'APPLE.COM/BILL',
          bounds: OcrBounds(left: .48, top: .235, width: .39, height: .03),
        ),
        OcrObservation(
          text: '866-712-7753 US',
          bounds: OcrBounds(left: .48, top: .274, width: .39, height: .029),
        ),
        OcrObservation(
          text: 'Date',
          bounds: OcrBounds(left: .10, top: .35, width: .1, height: .035),
        ),
        OcrObservation(
          text: '11/13/2026',
          bounds: OcrBounds(left: .48, top: .35, width: .22, height: .035),
        ),
      ];
      final rendered = OcrSpatialText.render(
        rawText: 'MERCHANT APPLE.COM/BILL 866-712-7753 US Date 11/13/2026',
        observations: lines,
      );
      final rows = rendered.split('\n');
      expect(
        rows.singleWhere((line) => line.contains('MERCHANT')),
        matches(RegExp(r'MERCHANT\s+APPLE.COM/BILL')),
      );
      expect(
        rows.singleWhere((line) => line.contains('866-712-7753')),
        isNot(contains('MERCHANT')),
      );
      expect(
        rows.singleWhere((line) => line.contains('Date')),
        matches(RegExp(r'Date\s+11/13/2026')),
      );
    },
  );

  test('separate pages render in page order without merging rows', () {
    const observations = [
      OcrObservation(
        text: 'SECOND PAGE',
        confidence: .9,
        pageIndex: 1,
        bounds: OcrBounds(left: .1, top: .1, width: .4, height: .03),
      ),
      OcrObservation(
        text: 'FIRST PAGE',
        confidence: .9,
        pageIndex: 0,
        bounds: OcrBounds(left: .1, top: .1, width: .4, height: .03),
      ),
    ];
    final text = OcrSpatialText.render(
      rawText: 'SECOND PAGE\nFIRST PAGE',
      observations: observations,
    );
    expect(text.indexOf('FIRST PAGE'), lessThan(text.indexOf('SECOND PAGE')));
    expect(text, contains('--- PAGE 2 ---'));
  });
}
