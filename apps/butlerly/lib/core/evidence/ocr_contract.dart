enum OcrIntent { receipt, paymentCard, statement }

enum OcrSourceKind { image, pdf }

final class OcrSource {
  const OcrSource({required this.path, required this.kind});

  final String path;
  final OcrSourceKind kind;
}

final class OcrBounds {
  const OcrBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left, top, width, height;
}

final class OcrObservation {
  const OcrObservation({
    required this.text,
    required this.confidence,
    this.bounds,
    this.left = 0,
    this.top = 0,
    this.width = 0,
    this.height = 0,
    this.pageIndex = 0,
    this.order = 0,
  });

  final String text;
  final double confidence;
  final OcrBounds? bounds;
  final double left, top, width, height;
  final int pageIndex;
  final int order;

  OcrBounds get normalizedBounds =>
      bounds ?? OcrBounds(left: left, top: top, width: width, height: height);
}

final class OcrPage {
  const OcrPage({
    required this.index,
    required this.observations,
    this.pixelWidth,
    this.pixelHeight,
    this.orientation,
  });

  final int index;
  final List<OcrObservation> observations;
  final int? pixelWidth, pixelHeight;
  final String? orientation;
}

final class OcrDiagnostics {
  const OcrDiagnostics({
    required this.sourceKind,
    required this.sourceOpened,
    required this.pageCount,
    required this.observationCount,
    required this.recognizedLineCount,
    required this.observationsWithBounds,
    this.pixelWidth,
    this.pixelHeight,
    this.orientation,
  });

  final OcrSourceKind sourceKind;
  final bool sourceOpened;
  final int pageCount, observationCount, recognizedLineCount;
  final int observationsWithBounds;
  final int? pixelWidth, pixelHeight;
  final String? orientation;
}

final class OcrDocument {
  const OcrDocument({required this.pages, required this.diagnostics});

  final List<OcrPage> pages;
  final OcrDiagnostics diagnostics;

  List<OcrObservation> get observations =>
      [for (final page in pages) ...page.observations]..sort((a, b) {
        final page = a.pageIndex.compareTo(b.pageIndex);
        return page == 0 ? a.order.compareTo(b.order) : page;
      });

  String get text => observations.map((value) => value.text).join('\n');
}

final class OcrRequest {
  const OcrRequest({required this.source, required this.intent});

  final OcrSource source;
  final OcrIntent intent;
}

enum OcrAvailability { available, unavailable }

enum OcrFailureCode {
  unavailable,
  unsupportedSource,
  unreadableSource,
  noReadableText,
  technicalFailure,
}

final class OcrException implements Exception {
  const OcrException({required this.code, required this.stage});

  final OcrFailureCode code;
  final String stage;

  @override
  String toString() => 'OcrException(code: $code, stage: $stage)';
}

abstract interface class OcrRecognizer {
  Future<OcrDocument> recognize(OcrRequest request);
  Future<OcrAvailability> availability();
}

/// Used on web and platforms without a bundled local OCR engine.
final class UnsupportedOcrRecognizer implements OcrRecognizer {
  const UnsupportedOcrRecognizer();

  @override
  Future<OcrAvailability> availability() async => OcrAvailability.unavailable;

  @override
  Future<OcrDocument> recognize(OcrRequest request) async {
    throw const OcrException(
      code: OcrFailureCode.unavailable,
      stage: 'platformAvailability',
    );
  }
}
