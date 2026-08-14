import 'package:butlerly/core/database/initial_master_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seeds local merchants for transaction organization', () {
    final merchants = buildInitialMasterData().merchants;

    expect(merchants, isNotEmpty);
    expect(merchants.map((value) => value.name), contains('Grocery Store'));
    expect(merchants.map((value) => value.name), contains('Restaurant'));
  });
}
