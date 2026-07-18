import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/analyzer_comparison.dart';

void main() {
  group('TomAnalyzer', () {
    group('self analysis json', () {
      test('should contain all analyzer elements from the package', () async {
        // The former `tom_analyzer` package was folded into `tom_reflector`;
        // the self-analysis fixture is this package's own barrel + doc dump.
        final rootPath = _findTomReflectorRoot();
        final barrelPath = p.join(rootPath, 'lib', 'tom_reflector.dart');
        final jsonPath = p.join(rootPath, 'doc', 'analyzer_analysis.json');

        await compareAnalyzerToJson(
          rootPath: rootPath,
          barrelPath: barrelPath,
          jsonPath: jsonPath,
          packageName: 'tom_reflector',
        );
      });
    });
  });
}

String _findTomReflectorRoot() {
  var current = Directory.current;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: tom_reflector')) {
      return current.path;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Unable to locate tom_reflector package root.');
    }
    current = parent;
  }
}
