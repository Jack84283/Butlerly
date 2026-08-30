import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:butlerly/core/evidence/statement_extractor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('butlerly/local_ocr');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'native observations retain text confidence geometry page and zero order',
    () async {
      const rawText = '2026-08-12 PRIVATE MERCHANT 18.25';
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'recognizeText');
        expect(call.arguments, {'path': '/local/statement.heic'});
        return {
          'text': rawText,
          'observations': [
            _nativeObservation(rawText, order: 4),
            _nativeObservation('Second page text', page: 1, order: 0),
          ],
          'diagnostics': _nativeDiagnostics(2),
        };
      });

      final result = await const LocalOcrService().recognizeStatement(
        '/local/statement.heic',
      );
      expect(result.rawText, rawText);
      expect(result.observations, hasLength(2));
      final observation = result.observations.first;
      expect(observation.text, rawText);
      expect(observation.confidence, .91);
      expect(observation.left, .12);
      expect(observation.top, .24);
      expect(observation.width, .61);
      expect(observation.height, .023);
      expect(observation.order, 4);
      expect(result.observations.last.pageIndex, 1);
      expect(result.observations.last.order, 0);
      expect(result.nativeDiagnostics?.pixelWidth, 3024);
      expect(result.nativeDiagnostics?.pixelHeight, 4032);
      expect(result.nativeDiagnostics?.orientation, 'right');
      expect(result.nativeDiagnostics?.matchesChannelPayload(2), isTrue);
    },
  );

  test(
    'the full channel-to-parser path emits only safe count diagnostics',
    () async {
      const rawText = '2026-08-12 PRIVATE MERCHANT 18.25';
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'text': rawText,
          'observations': [_nativeObservation(rawText)],
          'diagnostics': _nativeDiagnostics(1),
        },
      );
      final result = await const LocalStatementExtractor().extract(
        '/local/statement.jpg',
      );
      expect(result.rawText, rawText);
      expect(result.rows.single.originalText, rawText);
      expect(result.rows.single.amount, '18.25');
      expect(result.debugSummary, contains('OCR: 1 observations'));
      expect(result.debugSummary, contains('Candidates: 1'));
      expect(result.debugSummary, contains('Image: 3024x4032'));
      expect(result.debugSummary, isNot(contains('PRIVATE MERCHANT')));
      expect(result.debugSummary, isNot(contains('18.25')));
      expect(result.debugSummary, isNot(contains('/local/')));
    },
  );

  test(
    'native technical failure is not reported as an empty OCR result',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: 'image_open_failed',
          message: 'sensitive path or native detail must not be logged',
          details: {'stage': 'imageOpen'},
        );
      });
      final result = await const LocalStatementExtractor().extract(
        '/local/photo.heic',
      );
      expect(result.outcome, StatementExtractionOutcome.technicalOcrFailure);
      expect(result.diagnostics?.technicalFailureStage, 'imageOpen');
      expect(result.debugSummary, contains('image_open_failed'));
      expect(result.debugSummary, isNot(contains('sensitive')));
    },
  );

  test('empty successful Vision response remains noText', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'text': '',
        'observations': <Object>[],
        'diagnostics': _nativeDiagnostics(0),
      },
    );
    final result = await const LocalStatementExtractor().extract(
      '/local/photo.jpg',
    );
    expect(result.outcome, StatementExtractionOutcome.noText);
    expect(result.diagnostics?.nativeDiagnostics?.sourceOpened, isTrue);
  });

  test(
    'a lost structured observation is a channel failure not no candidates',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'text': 'Recognized text',
          'observations': <Object>[],
          'diagnostics': _nativeDiagnostics(1),
        },
      );
      final result = await const LocalStatementExtractor().extract(
        '/local/photo.jpg',
      );
      expect(result.outcome, StatementExtractionOutcome.technicalOcrFailure);
      expect(result.diagnostics?.technicalFailureStage, 'methodChannel');
      expect(
        result.diagnostics?.technicalFailureCode,
        'observation_count_mismatch',
      );
    },
  );

  test(
    'derived statement OCR retains source text except established PAN redaction',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'text': 'CARD 4111 1111 1111 1234\n2026-08-12 SHOP 18.25',
          'observations': [_nativeObservation('2026-08-12 SHOP 18.25')],
          'diagnostics': _nativeDiagnostics(1),
        },
      );
      final result = await const LocalStatementExtractor().extract(
        '/local/photo.jpg',
      );
      expect(result.rawText, 'CARD ****1234\n2026-08-12 SHOP 18.25');
      expect(result.rows.single.originalText, '2026-08-12 SHOP 18.25');
    },
  );
}

Map<String, Object> _nativeObservation(
  String text, {
  int page = 0,
  int order = 0,
}) => {
  'text': text,
  'confidence': .91,
  'left': .12,
  'top': .24,
  'width': .61,
  'height': .023,
  'pageIndex': page,
  'order': order,
};

Map<String, Object> _nativeDiagnostics(int count) => {
  'sourceKind': 'image',
  'sourceOpened': true,
  'observationCount': count,
  'recognizedLineCount': count,
  'observationsWithBounds': count,
  'pixelWidth': 3024,
  'pixelHeight': 4032,
  'orientation': 'right',
  'confidenceMinimum': .91,
  'confidenceAverage': .91,
  'confidenceMaximum': .91,
};
