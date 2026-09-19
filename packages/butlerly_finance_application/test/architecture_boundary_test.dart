import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/architecture_policy.dart';

void main() {
  test(
    'application imports, exports, and conditional directives respect layer boundaries',
    () {
      expect(
        packageBoundaryViolations(
          Directory('.'),
          packageName: 'butlerly_finance_application',
          allowedPackages: {
            'butlerly_finance_domain',
            'crypto',
            'timezone',
            'yaml',
          },
          platformIndependent: true,
        ),
        isEmpty,
      );
    },
  );
}
