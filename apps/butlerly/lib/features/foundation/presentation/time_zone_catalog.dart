import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// A short, geographically distinct list for the normal preference picker.
/// Values are IANA identifiers, never UTC offsets or translated display names.
final class ButlerlyTimeZone {
  const ButlerlyTimeZone(this.id, this.english, this.chinese, [this.spanish]);

  final String id;
  final String english;
  final String chinese;
  final String? spanish;

  String label(Locale locale) => switch (locale.languageCode) {
    'zh' => chinese,
    'es' => spanish ?? english,
    _ => english,
  };
}

const timeZoneCatalog = <ButlerlyTimeZone>[
  ButlerlyTimeZone('UTC', 'UTC', '协调世界时', 'UTC'),
  ButlerlyTimeZone(
    'America/Los_Angeles',
    'Pacific Time (Los Angeles)',
    '太平洋时间（洛杉矶）',
    'Hora del Pacífico (Los Ángeles)',
  ),
  ButlerlyTimeZone(
    'America/Denver',
    'Mountain Time (Denver)',
    '山地时间（丹佛）',
    'Hora de la Montaña (Denver)',
  ),
  ButlerlyTimeZone(
    'America/Chicago',
    'Central Time (Chicago)',
    '中部时间（芝加哥）',
    'Hora Central (Chicago)',
  ),
  ButlerlyTimeZone(
    'America/New_York',
    'Eastern Time (New York)',
    '东部时间（纽约）',
    'Hora del Este (Nueva York)',
  ),
  ButlerlyTimeZone('Europe/London', 'London', '伦敦', 'Londres'),
  ButlerlyTimeZone('Europe/Paris', 'Paris', '巴黎', 'París'),
  ButlerlyTimeZone(
    'Asia/Shanghai',
    'China Standard Time (Shanghai)',
    '中国标准时间（上海）',
    'Hora estándar de China (Shanghái)',
  ),
  ButlerlyTimeZone(
    'Asia/Tokyo',
    'Japan Standard Time (Tokyo)',
    '日本标准时间（东京）',
    'Hora estándar de Japón (Tokio)',
  ),
  ButlerlyTimeZone(
    'Australia/Sydney',
    'Australian Eastern Time (Sydney)',
    '澳大利亚东部时间（悉尼）',
    'Hora del Este de Australia (Sídney)',
  ),
];

/// Only use well-known IANA aliases that share the same zone rules.
/// Do not collapse zones merely because their current UTC offsets match.
const _commonTimeZoneAliases = <String, String>{
  'Etc/UTC': 'UTC',
  'Etc/GMT': 'UTC',
  'US/Pacific': 'America/Los_Angeles',
  'US/Mountain': 'America/Denver',
  'US/Central': 'America/Chicago',
  'US/Eastern': 'America/New_York',
};

bool _isCommonTimeZone(String id) =>
    timeZoneCatalog.any((zone) => zone.id == id);

/// Keep a previously saved, non-shortlist identifier at the top. Hide only
/// its *known equivalent* common-zone choice, not unrelated zones with the
/// same offset. Never rewrite the persisted identifier.
List<ButlerlyTimeZone> timeZoneChoicesFor(String selectedId) {
  final isCommon = _isCommonTimeZone(selectedId);
  final equivalent = _commonTimeZoneAliases[selectedId];
  return [
    if (!isCommon)
      ButlerlyTimeZone(selectedId, selectedId, selectedId, selectedId),
    for (final zone in timeZoneCatalog)
      if (isCommon || zone.id != equivalent) zone,
  ];
}

String timeZoneLabelFor(String id, Locale locale) {
  for (final zone in timeZoneCatalog) {
    if (zone.id == id) return zone.label(locale);
  }
  final equivalent = _commonTimeZoneAliases[id];
  if (equivalent != null) {
    return '${timeZoneLabelFor(equivalent, locale)} ($id)';
  }
  final city = id.split('/').last.replaceAll('_', ' ');
  return city == id ? id : '$city ($id)';
}

/// A platform result contains a unique IANA ID and a possibly duplicated
/// localized name. Always show the ID alongside that name in advanced search.
final class ButlerlyTimeZoneSearchEntry {
  const ButlerlyTimeZoneSearchEntry(this.id, this.name);

  final String id;
  final String name;
}

List<ButlerlyTimeZoneSearchEntry> searchButlerlyTimeZones(
  Iterable<TimezoneInfo> available,
  String query, {
  required Locale locale,
}) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return const [];
  final candidates = <String, ButlerlyTimeZoneSearchEntry>{};
  for (final entry in available) {
    final id = entry.identifier.trim();
    if (id.isEmpty) continue;
    final name = (entry.localizedName?.name ?? '').trim();
    candidates.putIfAbsent(
      id,
      () => ButlerlyTimeZoneSearchEntry(
        id,
        name.isEmpty ? timeZoneLabelFor(id, locale) : name,
      ),
    );
  }
  // Keep the common zones searchable if the platform plugin is unavailable
  // or omits a valid IANA name.
  for (final entry in timeZoneCatalog) {
    candidates.putIfAbsent(
      entry.id,
      () => ButlerlyTimeZoneSearchEntry(entry.id, entry.label(locale)),
    );
  }
  final results = candidates.values
      .where((entry) {
        final city = entry.id.replaceAll('_', ' ');
        return entry.name.toLowerCase().contains(normalized) ||
            city.toLowerCase().contains(normalized);
      })
      .toList(growable: false);
  results.sort((a, b) {
    final nameOrder = a.name.compareTo(b.name);
    return nameOrder == 0 ? a.id.compareTo(b.id) : nameOrder;
  });
  return results;
}

const _moreTimeZonesValue = '__butlerly_other_time_zones__';

/// Common choices are immediately visible; full IANA coverage stays available
/// through an explicit search instead of a huge, duplicate-looking menu.
Future<String?> showButlerlyTimeZonePicker(
  BuildContext context, {
  required String selectedId,
  Future<List<TimezoneInfo>> Function(String locale)? loadTimeZones,
}) async {
  final locale = Localizations.localeOf(context);
  final chosen = await showButlerlySelectionSheet<String>(
    context: context,
    title: context.l10n.text('timeZone'),
    selectedValue: selectedId,
    options: [
      for (final zone in timeZoneChoicesFor(selectedId))
        ButlerlySelectionOption(
          value: zone.id,
          child: Text(
            !_isCommonTimeZone(selectedId) && zone.id == selectedId
                ? '${context.l10n.text('timeZoneCurrent')}: ${timeZoneLabelFor(zone.id, locale)}'
                : timeZoneLabelFor(zone.id, locale),
          ),
        ),
      ButlerlySelectionOption(
        value: _moreTimeZonesValue,
        child: Row(
          children: [
            const Icon(Icons.search_rounded),
            const SizedBox(width: 12),
            Expanded(child: Text(context.l10n.text('timeZoneOther'))),
          ],
        ),
      ),
    ],
  );
  if (chosen != _moreTimeZonesValue) return chosen;
  if (!context.mounted) return null;
  final searched = await showSearch<String>(
    context: context,
    delegate: _TimeZoneSearchDelegate(
      locale: locale,
      hint: context.l10n.text('timeZoneSearchHint'),
      prompt: context.l10n.text('timeZoneSearchPrompt'),
      noResults: context.l10n.text('timeZoneSearchNoResults'),
      loadTimeZones: loadTimeZones,
    ),
  );
  return searched == null || searched.isEmpty ? null : searched;
}

class _TimeZoneSearchDelegate extends SearchDelegate<String> {
  _TimeZoneSearchDelegate({
    required this.locale,
    required String hint,
    required this.prompt,
    required this.noResults,
    Future<List<TimezoneInfo>> Function(String locale)? loadTimeZones,
  }) : super(searchFieldLabel: hint) {
    final load = loadTimeZones ?? FlutterTimezone.getAvailableTimezones;
    _available = load(locale.toLanguageTag()).catchError(
      (Object _) => timeZoneCatalog
          .map((zone) => TimezoneInfo(identifier: zone.id))
          .toList(growable: false),
    );
  }

  final Locale locale;
  final String prompt;
  final String noResults;
  late final Future<List<TimezoneInfo>> _available;

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(
      tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
      onPressed: () {
        query = '';
        showSuggestions(context);
      },
      icon: const Icon(Icons.clear_rounded),
    ),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
    onPressed: () => close(context, ''),
    icon: const Icon(Icons.arrow_back_rounded),
  );

  @override
  Widget buildResults(BuildContext context) => _buildMatches(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildMatches(context);

  Widget _buildMatches(BuildContext context) {
    if (query.trim().isEmpty) return Center(child: Text(prompt));
    return FutureBuilder<List<TimezoneInfo>>(
      future: _available,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final matches = searchButlerlyTimeZones(
          snapshot.data!,
          query,
          locale: locale,
        );
        if (matches.isEmpty) return Center(child: Text(noResults));
        return ListView.builder(
          itemCount: matches.length,
          itemBuilder: (context, index) {
            final zone = matches[index];
            return ListTile(
              key: ValueKey('time-zone-result-${zone.id}'),
              title: Text(zone.name),
              subtitle: Text(zone.id.replaceAll('_', ' ')),
              onTap: () => close(context, zone.id),
            );
          },
        );
      },
    );
  }
}
