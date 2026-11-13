import 'dart:math' as math;

import 'ocr_contract.dart';

/// Monospaced approximation of text placement using OCR bounding boxes.
/// Financial parsing and durable evidence retain the original OCR stream.
/// Missing geometry falls back to original reading order, not fake positions.
abstract final class OcrSpatialText {
  static const int _columns = 96;

  static bool hasGeometry(List<OcrObservation> observations) {
    if (observations.isEmpty) return false;
    return observations.every((item) {
      final bounds = item.normalizedBounds;
      return bounds.left.isFinite &&
          bounds.top.isFinite &&
          bounds.width.isFinite &&
          bounds.height.isFinite &&
          bounds.left >= 0 &&
          bounds.top >= 0 &&
          bounds.left <= 1 &&
          bounds.top <= 1 &&
          bounds.width > 0 &&
          bounds.height > 0 &&
          bounds.left + bounds.width <= 1.01 &&
          bounds.top + bounds.height <= 1.01;
    });
  }

  static String render({
    required String rawText,
    required List<OcrObservation> observations,
  }) {
    if (!hasGeometry(observations)) return rawText;

    final pages = <int, List<OcrObservation>>{};
    for (final item in observations) {
      pages.putIfAbsent(item.pageIndex, () => <OcrObservation>[]).add(item);
    }
    final pageIndexes = pages.keys.toList()..sort();
    final output = <String>[];
    for (final page in pageIndexes) {
      if (output.isNotEmpty) {
        output.add('');
        output.add('--- PAGE ${page + 1} ---');
      }
      final sorted = [...pages[page]!]
        ..sort((a, b) {
          final aBounds = a.normalizedBounds;
          final bBounds = b.normalizedBounds;
          final vertical = (aBounds.top + aBounds.height / 2).compareTo(
            bBounds.top + bBounds.height / 2,
          );
          return vertical != 0
              ? vertical
              : aBounds.left.compareTo(bBounds.left);
        });

      final rows = <List<OcrObservation>>[];
      for (final item in sorted) {
        if (rows.isEmpty) {
          rows.add([item]);
          continue;
        }
        final anchor = rows.last.first.normalizedBounds;
        final bounds = item.normalizedBounds;
        final center = anchor.top + anchor.height / 2;
        final nextCenter = bounds.top + bounds.height / 2;
        if ((center - nextCenter).abs() <=
            math.max(anchor.height, bounds.height) * .6) {
          rows.last.add(item);
        } else {
          rows.add([item]);
        }
      }

      OcrBounds? previous;
      for (final row in rows) {
        row.sort(
          (a, b) => a.normalizedBounds.left.compareTo(b.normalizedBounds.left),
        );
        final firstBounds = row.first.normalizedBounds;
        if (previous != null) {
          final gap = firstBounds.top - (previous.top + previous.height);
          final rowHeight = math.max(
            .025,
            math.max(previous.height, firstBounds.height),
          );
          final blanks = math.min(
            3,
            math.max(0, (gap / rowHeight).floor() - 1),
          );
          for (var index = 0; index < blanks; index++) {
            output.add('');
          }
        }
        previous = firstBounds;

        final line = StringBuffer();
        var position = 0;
        for (final item in row) {
          // Monospaced characters have no physical pixel width. Collision
          // handling keeps every recognized word readable.
          final column = (item.normalizedBounds.left * _columns)
              .round()
              .clamp(0, _columns);
          if (column > position) {
            line.write(' ' * (column - position));
            position = column;
          } else if (position > 0) {
            line.write(' ');
            position++;
          }
          final value = item.text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
          line.write(value);
          position += value.runes.length;
        }
        output.add(line.toString().trimRight());
      }
    }
    return output.join('\n');
  }
}
