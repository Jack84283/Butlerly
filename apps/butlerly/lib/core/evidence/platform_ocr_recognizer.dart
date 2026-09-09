import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ocr_contract.dart';

export 'ocr_contract.dart';

OcrRecognizer platformOcrRecognizer() =>
    defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android
    ? const PlatformOcrRecognizer()
    : const UnsupportedOcrRecognizer();

/// Flutter/native transport is confined to this platform adapter.
final class PlatformOcrRecognizer implements OcrRecognizer {
  const PlatformOcrRecognizer();

  static const _channel = MethodChannel('butlerly/local_ocr');

  @override
  Future<OcrAvailability> availability() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return OcrAvailability.unavailable;
    }
    try {
      final available = await _channel.invokeMethod<bool>('availability');
      return available == true
          ? OcrAvailability.available
          : OcrAvailability.unavailable;
    } on MissingPluginException {
      return OcrAvailability.unavailable;
    } on PlatformException {
      return OcrAvailability.unavailable;
    }
  }

  @override
  Future<OcrDocument> recognize(OcrRequest request) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      throw const OcrException(
        code: OcrFailureCode.unavailable,
        stage: 'platformAvailability',
      );
    }
    if (request.source.kind == OcrSourceKind.pdf &&
        defaultTargetPlatform == TargetPlatform.android) {
      throw const OcrException(
        code: OcrFailureCode.unsupportedSource,
        stage: 'sourceType',
      );
    }
    Map<Object?, Object?>? payload;
    try {
      payload = await _channel
          .invokeMapMethod<Object?, Object?>('recognizeText', {
            'path': request.source.path,
            if (request.source.kind == OcrSourceKind.pdf)
              'sourceKind': request.source.kind.name,
          });
    } on PlatformException catch (error) {
      throw _exception(error);
    } on MissingPluginException {
      throw const OcrException(
        code: OcrFailureCode.unavailable,
        stage: 'methodChannel',
      );
    }
    if (payload == null) {
      throw const OcrException(
        code: OcrFailureCode.technicalFailure,
        stage: 'nativeResponse',
      );
    }
    final observations = _observations(payload['observations']);
    final diagnosticMap = payload['diagnostics'];
    final reportedCount = diagnosticMap is Map
        ? (diagnosticMap['observationCount'] as num?)?.toInt()
        : null;
    if (reportedCount != null && reportedCount != observations.length) {
      throw const OcrException(
        code: OcrFailureCode.invalidResponse,
        stage: 'methodChannel',
      );
    }
    final normalizedObservations = observations.isNotEmpty
        ? observations
        : _textObservations(payload['text'] as String? ?? '');
    final diagnostics = _diagnostics(diagnosticMap, request.source);
    return OcrDocument(
      pages: _pages(normalizedObservations, diagnostics),
      diagnostics: diagnostics,
      fullText: payload['text'] as String? ?? '',
    );
  }

  static OcrException _exception(PlatformException error) {
    final code = switch (error.code) {
      'image_open_failed' ||
      'file_open_failed' => OcrFailureCode.unreadableSource,
      'unsupported_source' => OcrFailureCode.unsupportedSource,
      'no_text' => OcrFailureCode.noReadableText,
      'native_ocr_unavailable' => OcrFailureCode.unavailable,
      _ => OcrFailureCode.technicalFailure,
    };
    final details = error.details;
    final stage = details is Map ? details['stage']?.toString() : null;
    return OcrException(code: code, stage: stage ?? 'nativeOcr');
  }

  static List<OcrObservation> _observations(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .indexed
        .map((entry) {
          final (index, item) = entry;
          final pageIndex = (item['pageIndex'] as num?)?.toInt() ?? 0;
          final order = (item['order'] as num?)?.toInt() ?? index;
          return OcrObservation(
            text: item['text'] as String? ?? '',
            confidence: (item['confidence'] as num?)?.toDouble() ?? 0,
            left: (item['left'] as num?)?.toDouble() ?? 0,
            top: (item['top'] as num?)?.toDouble() ?? 0,
            width: (item['width'] as num?)?.toDouble() ?? 0,
            height: (item['height'] as num?)?.toDouble() ?? 0,
            bounds: OcrBounds(
              left: (item['left'] as num?)?.toDouble() ?? 0,
              top: (item['top'] as num?)?.toDouble() ?? 0,
              width: (item['width'] as num?)?.toDouble() ?? 0,
              height: (item['height'] as num?)?.toDouble() ?? 0,
            ),
            pageIndex: pageIndex,
            order: order,
          );
        })
        .toList(growable: false);
  }

  static List<OcrObservation> _textObservations(String text) => text
      .split(RegExp(r'\r?\n'))
      .asMap()
      .entries
      .where((entry) => entry.value.trim().isNotEmpty)
      .map(
        (entry) => OcrObservation(
          text: entry.value,
          confidence: 0.5,
          left: 0,
          top: entry.key.toDouble(),
          width: 1,
          height: 0,
          order: entry.key,
        ),
      )
      .toList(growable: false);

  static OcrDiagnostics _diagnostics(Object? value, OcrSource source) {
    final map = value is Map ? value : const <Object?, Object?>{};
    final kind = map['sourceKind'] == 'pdf' ? OcrSourceKind.pdf : source.kind;
    return OcrDiagnostics(
      sourceKind: kind,
      sourceOpened: map['sourceOpened'] as bool? ?? false,
      pageCount: (map['pageCount'] as num?)?.toInt() ?? 1,
      observationCount: (map['observationCount'] as num?)?.toInt() ?? 0,
      recognizedLineCount: (map['recognizedLineCount'] as num?)?.toInt() ?? 0,
      observationsWithBounds:
          (map['observationsWithBounds'] as num?)?.toInt() ?? 0,
      pixelWidth: (map['pixelWidth'] as num?)?.toInt(),
      pixelHeight: (map['pixelHeight'] as num?)?.toInt(),
      orientation: map['orientation'] as String?,
      visionObservationsRecognized: (map['visionObservationCount'] as num?)
          ?.toInt(),
      confidenceMinimum: (map['confidenceMinimum'] as num?)?.toDouble(),
      confidenceAverage: (map['confidenceAverage'] as num?)?.toDouble(),
      confidenceMaximum: (map['confidenceMaximum'] as num?)?.toDouble(),
    );
  }

  static List<OcrPage> _pages(
    List<OcrObservation> observations,
    OcrDiagnostics diagnostics,
  ) => [
    for (
      var index = 0;
      index <
          [
            diagnostics.pageCount,
            ...observations.map((value) => value.pageIndex + 1),
          ].reduce((a, b) => a > b ? a : b);
      index++
    )
      OcrPage(
        index: index,
        observations: observations
            .where((value) => value.pageIndex == index)
            .toList(growable: false),
        pixelWidth: index == 0 ? diagnostics.pixelWidth : null,
        pixelHeight: index == 0 ? diagnostics.pixelHeight : null,
        orientation: index == 0 ? diagnostics.orientation : null,
      ),
  ];
}
