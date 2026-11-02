import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/services.dart';

/// The versioned identities that the explicit bundled-rule repair operation
/// can restore. Keep this catalog aligned with assets/analysis_rules/catalog.yaml.
const bundledAnalysisRuleVersions = <String, String>{
  'ANL-R001': '1.3.0',
  'ANL-R002': '1.3.0',
  'ANL-R003': '1.3.0',
  'ANL-R004': '1.4.0',
  'ANL-R010': '1.1.0',
  'ANL-R011': '1.0.0',
  'ANL-R012': '1.0.0',
  'ANL-R014': '1.5.0',
  'ANL-R016': '1.1.0',
  'ANL-R020': '1.5.0',
  'ANL-R021': '1.3.0',
  'ANL-R022': '1.3.0',
  'ANL-R023': '1.3.0',
  'ANL-R024': '1.3.0',
  'ANL-R025': '1.3.0',
  'ANL-R026': '1.3.0',
  'ANL-R027': '1.0.0',
  'ANL-R028': '1.0.0',
  'ANL-R029': '1.1.0',
  'ANL-R090': '1.1.0',
  'ANL-R091': '1.1.0',
  'ANL-R092': '1.1.0',
};

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
