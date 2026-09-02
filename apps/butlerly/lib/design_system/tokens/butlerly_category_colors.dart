import 'package:flutter/material.dart';

/// Persistent category identity colors. These are deliberately independent of
/// ButlerlySemanticColors: application theme describes surfaces, while this
/// palette describes the category itself.
enum ButlerlyCategoryColorId {
  coral,
  orange,
  green,
  blue,
  purple,
  teal,
  gold,
  slate,
}

abstract final class ButlerlyCategoryColors {
  static const palette = <ButlerlyCategoryColorId, Color>{
    ButlerlyCategoryColorId.coral: Color(0xFFB42333),
    ButlerlyCategoryColorId.orange: Color(0xFFC65D00),
    ButlerlyCategoryColorId.green: Color(0xFF2F855A),
    ButlerlyCategoryColorId.blue: Color(0xFF2878B5),
    ButlerlyCategoryColorId.purple: Color(0xFF6B4FA1),
    ButlerlyCategoryColorId.teal: Color(0xFF007C83),
    ButlerlyCategoryColorId.gold: Color(0xFF8A6411),
    ButlerlyCategoryColorId.slate: Color(0xFF4B5563),
  };

  static const whiteGlyph = Colors.white;

  static Color color(ButlerlyCategoryColorId id) => palette[id]!;

  static ButlerlyCategoryColorId forCustom(String categoryId) {
    var hash = 0;
    for (final codeUnit in categoryId.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return ButlerlyCategoryColorId.values[hash %
        ButlerlyCategoryColorId.values.length];
  }
}
