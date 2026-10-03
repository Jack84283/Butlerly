import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final instant = DateTime.utc(2026, 9, 16, 22);

  test('resolves a valid persisted IANA timezone', () async {
    final result = await ResolveHomePeriod(_Preferences('America/Los_Angeles'))(
      instant: instant,
    );

    expect(result, isA<ApplicationSuccess<HomePeriodResolution>>());
    expect(
      (result as ApplicationSuccess<HomePeriodResolution>)
          .value
          .period
          .timeZoneId,
      'America/Los_Angeles',
    );
  });

  test(
    'returns a structured failure for an invalid persisted timezone',
    () async {
      final result = await ResolveHomePeriod(_Preferences('Invalid/Timezone'))(
        instant: instant,
      );

      expect(
        result,
        isA<ApplicationFailure<HomePeriodResolution>>().having(
          (value) => value.failure.code,
          'code',
          ApplicationFailureCode.validation,
        ),
      );
    },
  );

  test('uses UTC when the preference is missing', () async {
    final result = await ResolveHomePeriod(_Preferences(null))(
      instant: instant,
    );

    expect(result, isA<ApplicationSuccess<HomePeriodResolution>>());
    expect(
      (result as ApplicationSuccess<HomePeriodResolution>)
          .value
          .period
          .timeZoneId,
      'UTC',
    );
  });

  test('uses UTC when the preference repository fails', () async {
    final result = await ResolveHomePeriod(
      _Preferences(null, failOnLoad: true),
    )(instant: instant);

    expect(result, isA<ApplicationSuccess<HomePeriodResolution>>());
    expect(
      (result as ApplicationSuccess<HomePeriodResolution>)
          .value
          .period
          .timeZoneId,
      'UTC',
    );
  });
}

final class _Preferences implements UserPreferenceRepository {
  const _Preferences(this.timeZoneId, {this.failOnLoad = false});

  final String? timeZoneId;
  final bool failOnLoad;

  @override
  Future<UserPreference?> load() async {
    if (failOnLoad) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'load preferences',
      );
    }
    final value = timeZoneId;
    if (value == null) return null;
    return UserPreference(
      locale: 'en',
      baseCurrency: CurrencyCode('USD'),
      timeZoneId: value,
    );
  }

  @override
  Future<void> save(UserPreference preference) async {}
}
