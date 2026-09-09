import 'package:butlerly/core/evidence/ocr_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes iOS-shaped and Android-shaped observations identically', () {
    const ios = OcrDocument(
      pages: [
        OcrPage(
          index: 0,
          observations: [
            OcrObservation(
              text: 'CAFE',
              confidence: .91,
              left: .1,
              top: .2,
              width: .3,
              height: .04,
              order: 0,
            ),
          ],
        ),
      ],
      diagnostics: OcrDiagnostics(
        sourceKind: OcrSourceKind.image,
        sourceOpened: true,
        pageCount: 1,
        observationCount: 1,
        recognizedLineCount: 1,
        observationsWithBounds: 1,
      ),
    );
    const android = OcrDocument(
      pages: [
        OcrPage(
          index: 0,
          observations: [
            OcrObservation(
              text: 'CAFE',
              confidence: .91,
              bounds: OcrBounds(left: .1, top: .2, width: .3, height: .04),
              left: .1,
              top: .2,
              width: .3,
              height: .04,
              order: 0,
            ),
          ],
        ),
      ],
      diagnostics: OcrDiagnostics(
        sourceKind: OcrSourceKind.image,
        sourceOpened: true,
        pageCount: 1,
        observationCount: 1,
        recognizedLineCount: 1,
        observationsWithBounds: 1,
      ),
    );

    expect(android.text, ios.text);
    expect(android.observations.single.normalizedBounds.left, .1);
    expect(android.observations.single.normalizedBounds.height, .04);
    expect(android.diagnostics.pageCount, ios.diagnostics.pageCount);
  });

  test('unsupported recognizer returns a typed unavailable failure', () async {
    const recognizer = UnsupportedOcrRecognizer();
    expect(await recognizer.availability(), OcrAvailability.unavailable);
    await expectLater(
      recognizer.recognize(
        const OcrRequest(
          source: OcrSource(path: 'private.jpg', kind: OcrSourceKind.image),
          intent: OcrIntent.receipt,
        ),
      ),
      throwsA(
        isA<OcrException>().having(
          (error) => error.code,
          'code',
          OcrFailureCode.unavailable,
        ),
      ),
    );
  });
}
