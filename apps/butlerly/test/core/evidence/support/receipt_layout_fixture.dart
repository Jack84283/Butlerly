import 'dart:convert';
import 'dart:math' as math;

import 'package:butlerly/core/evidence/local_ocr_service.dart';

/// Test-only, lossless OCR fixture. Original observations feed production
/// extraction; the aligned text is diagnostic and must never become its input.
final class ReceiptLayoutFixture {
  const ReceiptLayoutFixture({
    required this.id,
    required this.document,
    required this.expected,
  });

  final String id;
  final OcrDocument document;
  final Map<String, String?> expected;

  factory ReceiptLayoutFixture.fromJson(Map<String, dynamic> json) {
    final pages = (json['pages'] as List<dynamic>).map((value) {
      final page = value as Map<String, dynamic>;
      final index = (page['index'] as num).toInt();
      return OcrPage(
        index: index,
        pixelWidth: (page['pixelWidth'] as num?)?.toInt(),
        pixelHeight: (page['pixelHeight'] as num?)?.toInt(),
        orientation: page['orientation'] as String?,
        observations: (page['observations'] as List<dynamic>).map((value) {
          final item = value as Map<String, dynamic>;
          final bounds = item['bounds'] as Map<String, dynamic>?;
          return OcrObservation(
            text: item['text'] as String,
            confidence: (item['confidence'] as num).toDouble(),
            bounds: bounds == null
                ? null
                : OcrBounds(
                    left: (bounds['left'] as num).toDouble(),
                    top: (bounds['top'] as num).toDouble(),
                    width: (bounds['width'] as num).toDouble(),
                    height: (bounds['height'] as num).toDouble(),
                  ),
            left: (item['left'] as num?)?.toDouble() ?? 0,
            top: (item['top'] as num?)?.toDouble() ?? 0,
            width: (item['width'] as num?)?.toDouble() ?? 0,
            height: (item['height'] as num?)?.toDouble() ?? 0,
            pageIndex: (item['pageIndex'] as num?)?.toInt() ?? index,
            order: (item['order'] as num).toInt(),
          );
        }).toList(growable: false),
      );
    }).toList(growable: false);
    final observations = [for (final page in pages) ...page.observations];
    final meta = json['diagnostics'] as Map<String, dynamic>?;
    final diagnostics = OcrDiagnostics(
      sourceKind: OcrSourceKind.values.byName(
        meta?['sourceKind'] as String? ?? 'image',
      ),
      sourceOpened: meta?['sourceOpened'] as bool? ?? true,
      pageCount: pages.length,
      observationCount: observations.length,
      recognizedLineCount:
          (meta?['recognizedLineCount'] as num?)?.toInt() ??
          observations.length,
      observationsWithBounds: observations
          .where((value) => value.normalizedBounds.width > 0)
          .length,
    );
    return ReceiptLayoutFixture(
      id: json['id'] as String,
      document: OcrDocument(
        pages: pages,
        diagnostics: diagnostics,
        fullText: json['fullText'] as String?,
      ),
      expected: (json['expected'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as String?),
      ),
    );
  }

  /// Export observations from the actual OCR interface without flattening
  /// their geometry. Use only redacted, consented examples in the repository.
  static String encodeDocument({
    required String id,
    required OcrDocument document,
    required Map<String, String?> expected,
  }) {
    return const JsonEncoder.withIndent('  ').convert({
      'id': id,
      'diagnostics': {
        'sourceKind': document.diagnostics.sourceKind.name,
        'sourceOpened': document.diagnostics.sourceOpened,
        'recognizedLineCount': document.diagnostics.recognizedLineCount,
      },
      if (document.fullText != null) 'fullText': document.fullText,
      'pages': [
        for (final page in document.pages)
          {
            'index': page.index,
            if (page.pixelWidth != null) 'pixelWidth': page.pixelWidth,
            if (page.pixelHeight != null) 'pixelHeight': page.pixelHeight,
            if (page.orientation != null) 'orientation': page.orientation,
            'observations': [
              for (final observation in page.observations)
                {
                  'text': observation.text,
                  'confidence': observation.confidence,
                  'pageIndex': observation.pageIndex,
                  'order': observation.order,
                  if (observation.bounds case final bounds?)
                    'bounds': {
                      'left': bounds.left,
                      'top': bounds.top,
                      'width': bounds.width,
                      'height': bounds.height,
                    }
                  else ...{
                    'left': observation.left,
                    'top': observation.top,
                    'width': observation.width,
                    'height': observation.height,
                  },
                },
            ],
          },
      ],
      'expected': expected,
    });
  }

  ReceiptOcrResult extract() =>
      ReceiptExtractor.extract(document.text, document.observations);

  /// A readable approximation only. Never synthesize missing OCR geometry.
  /// A page with no usable bounds remains in native OCR reading order.
  String get layout {
    final output = <String>[];
    for (final page in document.pages) {
      if (output.isNotEmpty) output.add('--- PAGE ${page.index + 1} ---');
      final observations = [...page.observations]
        ..sort((a, b) => a.order.compareTo(b.order));
      if (observations.any((value) => value.normalizedBounds.width <= 0)) {
        output.addAll(observations.map((value) => value.text));
        continue;
      }
      final ordered = [...observations]
        ..sort((a, b) {
          final aBounds = a.normalizedBounds;
          final bBounds = b.normalizedBounds;
          final vertical = aBounds.top.compareTo(bBounds.top);
          return vertical != 0
              ? vertical
              : aBounds.left.compareTo(bBounds.left);
        });
      final groups = <List<OcrObservation>>[];
      for (final item in ordered) {
        if (groups.isEmpty) {
          groups.add([item]);
          continue;
        }
        final last = groups.last;
        final anchor = last.first.normalizedBounds;
        final next = item.normalizedBounds;
        final center = anchor.top + anchor.height / 2;
        final nextCenter = next.top + next.height / 2;
        final tolerance = math.max(anchor.height, next.height) * .65;
        if ((center - nextCenter).abs() <= tolerance) {
          last.add(item);
        } else {
          groups.add([item]);
        }
      }
      for (final group in groups) {
        group.sort(
          (a, b) => a.normalizedBounds.left.compareTo(b.normalizedBounds.left),
        );
        final buffer = StringBuffer();
        var column = 0;
        for (final observation in group) {
          final target = math.min(
            64,
            math.max(0, (observation.normalizedBounds.left * 64).round()),
          );
          if (target > column) {
            buffer.write(' ' * (target - column));
            column = target;
          } else if (column > 0) {
            buffer.write(' ');
            column++;
          }
          buffer.write(observation.text);
          column += observation.text.length;
        }
        output.add(buffer.toString().trimRight());
      }
    }
    return output.join('\n');
  }

  String get diagnosticReport {
    final result = extract();
    final actual = <String, String?>{
      'merchant': result.merchant,
      'amount': result.amount,
      'currency': result.currency,
      'date': result.date?.toIso8601String().substring(0, 10),
      'tax': result.tax,
      'tip': result.tip,
    };
    final fields = expected.keys.map((field) {
      final wanted = expected[field];
      final received = actual[field];
      final evidence = result.fieldEvidence[field] ?? '(none)';
      return '${wanted == received ? 'PASS' : 'FAIL'} $field: '
          'expected=${wanted ?? '(null)'} actual=${received ?? '(null)'} '
          'evidence=$evidence';
    });
    return 'Receipt fixture: $id\n$layout\n\n${fields.join('\n')}';
  }
}
