import 'dart:io';

import 'package:butlerly/core/data/evidence_path_safety.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows Apple sandbox aliases on both macOS and iOS', () {
    expect(
      isAllowedSystemPathAlias('/var', isMacOS: true, isIOS: false),
      isTrue,
    );
    expect(
      isAllowedSystemPathAlias('/tmp', isMacOS: true, isIOS: false),
      isTrue,
    );
    expect(
      isAllowedSystemPathAlias('/var', isMacOS: false, isIOS: true),
      isTrue,
    );
    expect(
      isAllowedSystemPathAlias('/tmp', isMacOS: false, isIOS: true),
      isTrue,
    );
  });

  test('does not allow Apple aliases on non-Apple platforms', () {
    expect(
      isAllowedSystemPathAlias('/var', isMacOS: false, isIOS: false),
      isFalse,
    );
    expect(
      isAllowedSystemPathAlias('/tmp', isMacOS: false, isIOS: false),
      isFalse,
    );
    expect(
      isAllowedSystemPathAlias('/private', isMacOS: true, isIOS: true),
      isFalse,
    );
  });

  test(
    'still rejects a user-controlled symlink below the private root',
    () async {
      final root = await Directory.systemTemp.createTemp('butlerly-path-test-');
      final outside = await Directory.systemTemp.createTemp(
        'butlerly-path-outside-',
      );
      addTearDown(() async {
        await root.delete(recursive: true);
        await outside.delete(recursive: true);
      });

      final linked = Link('${root.path}/linked');
      await linked.create(outside.path);

      await expectLater(
        rejectSymlinkedPath('${linked.path}/marker.json'),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
