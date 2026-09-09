import 'package:butlerly/core/evidence/platform_ocr_recognizer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('butlerly/local_ocr');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

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

  test('Android-shaped native payload maps to the neutral contract', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'recognizeText');
      expect(call.arguments, {'path': '/private/receipt.jpg'});
      return {
        'text': 'CAFE\nTOTAL 10.00',
        'observations': [
          {
            'text': 'CAFE',
            'confidence': .91,
            'left': .1,
            'top': .2,
            'width': .3,
            'height': .04,
            'pageIndex': 0,
            'order': 0,
          },
          {
            'text': 'TOTAL 10.00',
            'confidence': .87,
            'left': .1,
            'top': .3,
            'width': .5,
            'height': .04,
            'pageIndex': 0,
            'order': 1,
          },
        ],
        'diagnostics': {
          'sourceKind': 'image',
          'sourceOpened': true,
          'pageCount': 1,
          'observationCount': 2,
          'recognizedLineCount': 2,
          'observationsWithBounds': 2,
          'pixelWidth': 2048,
          'pixelHeight': 1536,
        },
      };
    });

    final document = await const PlatformOcrRecognizer().recognize(
      const OcrRequest(
        source: OcrSource(
          path: '/private/receipt.jpg',
          kind: OcrSourceKind.image,
        ),
        intent: OcrIntent.receipt,
      ),
    );
    expect(document.observations.map((value) => value.text), [
      'CAFE',
      'TOTAL 10.00',
    ]);
    expect(document.observations.first.confidence, .91);
    expect(document.observations.first.normalizedBounds.left, .1);
    expect(document.observations.last.order, 1);
    expect(document.diagnostics.pixelWidth, 2048);
  });

  test(
    'Android PDF requests fail with a typed unsupported-source outcome',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await expectLater(
        const PlatformOcrRecognizer().recognize(
          const OcrRequest(
            source: OcrSource(
              path: '/private/statement.pdf',
              kind: OcrSourceKind.pdf,
            ),
            intent: OcrIntent.statement,
          ),
        ),
        throwsA(
          isA<OcrException>().having(
            (error) => error.code,
            'code',
            OcrFailureCode.unsupportedSource,
          ),
        ),
      );
    },
  );
}
