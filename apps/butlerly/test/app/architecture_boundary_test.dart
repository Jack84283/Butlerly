import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../../tool/architecture_policy.dart';

void main() {
  test(
    'presentation depends on application contracts, not database adapters',
    () {
      expect(presentationBoundaryViolations(Directory('.')), isEmpty);
    },
  );
}
