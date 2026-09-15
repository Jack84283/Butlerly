import 'package:butlerly/l10n/app_localizations.dart';

/// Localized brand copy used by the Home header.
///
/// Kept in the localization layer so brand copy does not remain embedded in
/// presentation widgets. The supported languages intentionally mirror
/// [AppLocalizations.supportedLocales].
extension HomeBrandLocalizations on AppLocalizations {
  String get homeTagline => switch (locale.languageCode) {
    'es' => 'UNA FORMA MÁS TRANQUILA DE VIVIR EL DINERO',
    'zh' => '更从容地管理金钱',
    _ => 'A CALMER WAY TO MONEY',
  };
}
