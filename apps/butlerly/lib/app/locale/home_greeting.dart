import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Falls back to the plain greeting for isolated widget previews and tests
/// that intentionally do not install an application preferences scope.
class PersonalizedHomeGreeting extends StatelessWidget {
  const PersonalizedHomeGreeting({
    required this.greetingKey,
    this.textKey,
    this.maxLines,
    this.textAlign,
    this.style,
    super.key,
  });

  final String greetingKey;
  final Key? textKey;
  final int? maxLines;
  final TextAlign? textAlign;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    Widget label(String? name) {
      final named = name?.trim().isNotEmpty ?? false;
      final lineCount = maxLines ?? (named ? 1 : null);
      return Text(
        homeGreetingWithName(context, greetingKey, name),
        key: textKey,
        maxLines: lineCount,
        textAlign: textAlign,
        overflow: lineCount == null ? null : TextOverflow.ellipsis,
        style: style,
      );
    }

    if (context.getElementForInheritedWidgetOfExactType<
            UncontrolledProviderScope>() ==
        null) {
      return label(null);
    }
    return Consumer(
      builder: (context, ref, _) =>
          label(ref.watch(userPreferenceProvider).value?.displayName),
    );
  }
}
