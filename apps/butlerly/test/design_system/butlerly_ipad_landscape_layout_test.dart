import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iPad landscape uses wide even below desktop breakpoint', () {
    expect(
      ButlerlyLayout.modeForWidth(980, tabletLandscape: true),
      ButlerlyLayoutMode.wide,
    );
    expect(ButlerlyLayout.modeForWidth(744), ButlerlyLayoutMode.compact);
    expect(ButlerlyLayout.modeForWidth(980), ButlerlyLayoutMode.medium);
    expect(ButlerlyLayout.modeForWidth(1100), ButlerlyLayoutMode.wide);
  });
}
