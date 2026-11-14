import 'dart:math' as math;

import 'ocr_contract.dart';

/// Monospaced approximation of text placement using OCR bounding boxes.
/// Financial parsing and durable evidence retain the original OCR stream.
/// Missing geometry falls back to original reading order, not fake positions.
abstract final class OcrSpatialText {
  static const int _columns = 64;

  static bool _hasBounds(OcrObservation item) {
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
  }

  /// At least one positioned observation enables a partial spatial preview.
  static bool hasGeometry(List<OcrObservation> observations) =>
      observations.any(_hasBounds);

  /// Approximate rendered monospace cell widths, not Unicode rune counts.
  /// CJK/fullwidth glyphs occupy two cells; combining marks occupy none.
  static int _displayCells(String value) {
    var cells = 0;
    for (final rune in value.runes) {
      if ((rune >= 0x0300 && rune <= 0x036F) ||
          (rune >= 0x1AB0 && rune <= 0x1AFF) ||
          (rune >= 0x1DC0 && rune <= 0x1DFF) ||
          (rune >= 0x20D0 && rune <= 0x20FF) ||
          (rune >= 0xFE00 && rune <= 0xFE0F) ||
          (rune >= 0xFE20 && rune <= 0xFE2F) ||
          (rune >= 0x200B && rune <= 0x200F)) {
        continue;
      }
      final wide =
          (rune >= 0x1100 && rune <= 0x115F) ||
          (rune >= 0x2329 && rune <= 0x232A) ||
          (rune >= 0x2E80 && rune <= 0xA4CF) ||
          (rune >= 0xAC00 && rune <= 0xD7A3) ||
          (rune >= 0xF900 && rune <= 0xFAFF) ||
          (rune >= 0xFE10 && rune <= 0xFE19) ||
          (rune >= 0xFE30 && rune <= 0xFE6F) ||
          (rune >= 0xFF01 && rune <= 0xFF60) ||
          (rune >= 0xFFE0 && rune <= 0xFFE6) ||
          (rune >= 0x1F000 && rune <= 0x1FAFF) ||
          (rune >= 0x20000 && rune <= 0x3FFFD);
      cells += wide ? 2 : 1;
    }
    return cells;
  }

  static bool _sameRow(OcrBounds a, OcrBounds b) {
    final overlap =
        math.min(a.top + a.height, b.top + b.height) - math.max(a.top, b.top);
    if (overlap <= 0) return false;
    final fraction = overlap / math.min(a.height, b.height);
    final baselineDifference = ((a.top + a.height) - (b.top + b.height)).abs();
    return fraction >= .55 &&
        baselineDifference <=
            math.max(.012, math.max(a.height, b.height) * .55);
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
      if (output.isNotEmpty) output.add('');
      // Page 1 is implicit only when it actually contains observations.
      // If earlier pages were empty, label the first rendered page too.
      if (output.isNotEmpty || page > 0) {
        output.add('--- PAGE ${page + 1} ---');
      }
      final sorted = pages[page]!.where(_hasBounds).toList()
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
        // Match the entire row, not just its first item. Vertical overlap
        // and baseline agreement handle mixed fonts without joining a
        // closely-spaced line above or below.
        final bounds = item.normalizedBounds;
        final sameRow = rows.last.every(
          (member) => _sameRow(member.normalizedBounds, bounds),
        );
        if (sameRow) {
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
              .clamp(0, _columns)
              .toInt();
          if (column > position) {
            line.write(' ' * (column - position));
            position = column;
          } else if (position > 0) {
            line.write(' ');
            position++;
          }
          final value = item.text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
          line.write(value);
          position += _displayCells(value);
        }
        output.add(line.toString().trimRight());
      }
      // Keep missing-geometry lines on their original page, not after all
      // positioned pages. Their local reading order remains unchanged.
      final unpositioned =
          pages[page]!.where((item) => !_hasBounds(item)).toList()
            ..sort((a, b) => a.order.compareTo(b.order));
      if (unpositioned.isNotEmpty) {
        if (sorted.isNotEmpty) output.add('');
        output.add('--- TEXT WITHOUT POSITION ---');
        output.addAll(unpositioned.map((item) => item.text));
      }
    }
    return output.join('\n');
  }
}
