import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/architecture_policy.dart';

void main() {
  test(
    'detects exports and conditional dependencies, ignores non-directive text',
    () {
      expect(
        dependencyUris('''
// import 'dart:io';
import 'safe.dart' if (dart.library.io) 'dart:io';
export 'package:bad/adapter.dart';
part 'part.dart';
const text = "import 'dart:ffi';";
'''),
        ['safe.dart', 'dart:io', 'package:bad/adapter.dart', 'part.dart'],
      );
    },
  );

  test(
    'rejects reverse-layer packages, platform SDKs, and relative escapes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'architecture-policy-',
      );
      addTearDown(() => root.delete(recursive: true));
      final lib = await Directory('${root.path}/lib').create();
      await File('${lib.path}/model.dart').writeAsString('''
import 'dart:collection';
export 'package:flutter/widgets.dart';
import 'safe.dart' if (dart.library.io) 'dart:io';
import '../adapter.dart';
''');
      final violations = packageBoundaryViolations(
        root,
        packageName: 'example',
        allowedPackages: {},
      );
      expect(violations, hasLength(3));
      expect(violations.join('\n'), contains('package:flutter/widgets.dart'));
      expect(violations.join('\n'), contains('dart:io'));
      expect(violations.join('\n'), contains('../adapter.dart'));
    },
  );
}
