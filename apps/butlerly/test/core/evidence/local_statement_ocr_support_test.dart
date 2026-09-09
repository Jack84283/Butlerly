import 'package:butlerly/core/evidence/local_statement_ocr_support.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enables statement OCR for supported native platforms', () {
    expect(
      supportsLocalStatementOcr(platform: TargetPlatform.iOS, isWeb: false),
      isTrue,
    );
    for (final platform in TargetPlatform.values) {
      if (platform != TargetPlatform.iOS &&
          platform != TargetPlatform.android) {
        expect(
          supportsLocalStatementOcr(platform: platform, isWeb: false),
          isFalse,
        );
      }
    }
    expect(
      supportsLocalStatementOcr(platform: TargetPlatform.iOS, isWeb: true),
      isFalse,
    );
  });
}
