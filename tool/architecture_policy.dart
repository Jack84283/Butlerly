import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// Parse actual Dart directives, including exports and every conditional URI.
/// Text in comments and string literals cannot hide or invent a dependency.
List<String> dependencyUris(String source) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  return [
    for (final directive in unit.directives) ...[
      if (directive is NamespaceDirective) ...[
        if (directive.uri.stringValue case final String uri) uri,
        for (final configuration in directive.configurations)
          if (configuration.uri.stringValue case final String uri) uri,
      ],
      if (directive is PartDirective)
        if (directive.uri.stringValue case final String uri) uri,
    ],
  ];
}

const _pureDartLibraries = {
  'dart:async',
  'dart:collection',
  'dart:convert',
  'dart:core',
  'dart:math',
  'dart:typed_data',
};

List<String> packageBoundaryViolations(
  Directory package, {
  required String packageName,
  required Set<String> allowedPackages,
  bool platformIndependent = true,
}) {
  final root = Directory('${package.path}/lib').absolute.uri;
  final problems = <String>[];
  for (final file in Directory.fromUri(
    root,
  ).listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    for (final uri in dependencyUris(file.readAsStringSync())) {
      final parsed = Uri.parse(uri);
      final allowed = switch (parsed.scheme) {
        'dart' => !platformIndependent || _pureDartLibraries.contains(uri),
        'package' => {
          packageName,
          ...allowedPackages,
        }.contains(parsed.pathSegments.first),
        '' =>
          file.absolute.uri
              .resolveUri(parsed)
              .toString()
              .startsWith(root.toString()),
        _ => false,
      };
      if (!allowed) problems.add('${file.path}: $uri');
    }
  }
  return problems;
}

List<String> presentationBoundaryViolations(Directory app) {
  final root = app.absolute.uri;
  final features = Directory.fromUri(root.resolve('lib/features/'));
  final problems = <String>[];
  for (final file in features.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    for (final uri in dependencyUris(file.readAsStringSync())) {
      final parsed = Uri.parse(uri);
      final resolved =
          parsed.scheme == 'package' && parsed.pathSegments.first == 'butlerly'
          ? root.resolve('lib/${parsed.pathSegments.skip(1).join('/')}')
          : parsed.scheme.isEmpty
          ? file.absolute.uri.resolveUri(parsed)
          : parsed;
      if (uri.startsWith('package:butlerly_database/') ||
          uri.startsWith('package:sqflite') ||
          resolved.toString().startsWith(
            root.resolve('lib/core/database/').toString(),
          ) ||
          resolved.toString().startsWith(
            root.resolve('lib/core/data/').toString(),
          )) {
        problems.add('${file.path}: $uri');
      }
    }
  }
  return problems;
}
