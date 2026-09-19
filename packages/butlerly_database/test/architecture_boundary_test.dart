import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/architecture_policy.dart';

void main() {
  test(
    'database imports, exports, and conditional directives respect layer boundaries',
    () {
      expect(
        packageBoundaryViolations(
          Directory('.'),
          packageName: 'butlerly_database',
          allowedPackages: {'butlerly_finance_domain', 'sqflite_common'},
          platformIndependent: false,
        ),
        isEmpty,
      );
    },
  );
}
