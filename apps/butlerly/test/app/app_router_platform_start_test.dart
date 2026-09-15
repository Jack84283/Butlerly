import 'package:butlerly/app/router/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'production router ignores platform startup route and starts at launch',
    (tester) async {
      tester.platformDispatcher.defaultRouteNameTestValue = '/transactions';
      addTearDown(
        tester.platformDispatcher.clearDefaultRouteNameTestValue,
      );

      expect(appRouter.routeInformationProvider.value.uri.path, '/launch');
    },
  );
}
