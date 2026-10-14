import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';

/// Shared localized greeting for device and desktop Home.
String greetingKeyForTime(DateTime localTime) {
  if (localTime.hour < 12) return 'greetingMorning';
  if (localTime.hour < 18) return 'greetingAfternoon';
  return 'greetingEvening';
}

String homeGreetingWithName(
  BuildContext context,
  String greetingKey,
  String? displayName,
) {
  final greeting = context.l10n.text(greetingKey);
  final name = displayName?.trim() ?? '';
  if (name.isEmpty) return greeting;
  return context.l10n.text('greetingWithName', {
    'greeting': greeting,
    'name': name,
  });
}
