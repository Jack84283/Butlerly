import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/services.dart';

/// Installs the packaged definitions, checked against their versioned catalog.
/// Discovering assets avoids a second hand-maintained list in startup code.
Future<RuleInstallationResult> installBundledAnalysisRules(
  InstallBuiltInRules installer, {
  AssetBundle? bundle,
}) async {
  final assets = bundle ?? rootBundle;
  const directory = 'assets/analysis_rules/';
  const catalogPath = '${directory}catalog.yaml';
  final manifest = await AssetManifest.loadFromAssetBundle(assets);
  final paths =
      manifest
          .listAssets()
          .where(
            (path) =>
                path.startsWith(directory) &&
                path.endsWith('.yaml') &&
                path != catalogPath,
          )
          .toList()
        ..sort();
  final sources = <String, String>{};
  for (final path in paths) {
    sources[path] = await assets.loadString(path);
  }
  return installer(
    sources,
    catalogSource: await assets.loadString(catalogPath),
  );
}
