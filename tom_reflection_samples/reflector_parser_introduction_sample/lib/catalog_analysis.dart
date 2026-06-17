// Shared analysis helpers for the engine-2 parser introduction sample.
//
// Engine 2 (`tom_reflector`) is a *build-time* reflection engine: it runs the
// Dart analyzer over source text and returns an `AnalysisResult` — a pure,
// serializable object model of the code's shape (classes, methods, fields,
// type parameters, annotations). Nothing in the analyzed source is executed.
//
// The source set we analyze lives in `sample_source/` — a tiny, self-contained
// pure-Dart package with no dependencies. It is *input data*, not part of this
// project's own library code (which is why it sits outside `lib/`).
//
// Every scenario starts from `analyzeCatalog()`; the JSON and report helpers
// build on top of it.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_reflector/tom_reflector.dart';

/// Analyzes the bundled `sample_source/` package and returns its model.
///
/// `TomAnalyzer.analyzeBarrel` builds an analyzer context rooted at the source
/// package, resolves every `.dart` file it owns, and walks the element model
/// into an [AnalysisResult]. We point it at the package's barrel
/// (`lib/catalog.dart`); `workspaceRoot` names the package root so the analyzer
/// reads its `pubspec.yaml`.
Future<AnalysisResult> analyzeCatalog() async {
  final sourceRoot = _findSampleSourceRoot();
  final barrel = p.join(sourceRoot, 'lib', 'catalog.dart');
  return TomAnalyzer().analyzeBarrel(
    barrelPath: barrel,
    workspaceRoot: sourceRoot,
  );
}

/// Locates the `sample_source/` package by walking up from the current
/// directory. This keeps the scenarios runnable both standalone
/// (`dart run example/model_report/main.dart`) and through the aggregator
/// (`dart run bin/run_example.dart`), as long as they are launched from inside
/// the sample tree.
String _findSampleSourceRoot() {
  var dir = Directory.current.absolute.path;
  for (var i = 0; i < 8; i++) {
    final candidate = p.join(dir, 'sample_source');
    if (File(p.join(candidate, 'lib', 'catalog.dart')).existsSync()) {
      return candidate;
    }
    final parent = p.dirname(dir);
    if (parent == dir) break;
    dir = parent;
  }
  throw StateError(
    'Could not locate sample_source/. Run the scenarios from inside the '
    'reflector_parser_introduction_sample directory.',
  );
}

/// Renders a [TypeReference] the way it reads in source: `List<String>`,
/// `int?`, `void`. Engine 2 keeps type arguments and nullability as structured
/// data; this collapses them back into a display string for reports.
String renderType(TypeReference type) {
  if (type.isVoid) return 'void';
  if (type.isDynamic) return 'dynamic';
  final args = type.typeArguments.isEmpty
      ? ''
      : '<${type.typeArguments.map(renderType).join(', ')}>';
  final suffix = type.isNullable ? '?' : '';
  return '${type.name}$args$suffix';
}

/// Builds a **deterministic** structural report of the analyzed catalog.
///
/// The full `JsonSerializer.encode(result)` output is faithful but *volatile*:
/// it carries timestamps, absolute paths and content hashes that change between
/// runs and machines. For a stable, reviewable artifact we project the model
/// down to just its shape — names, kinds, members, annotations — and sort every
/// collection so the bytes are identical on every run.
Map<String, dynamic> buildCatalogReport(AnalysisResult result) {
  final classes = result.allClasses.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final enums = result.allEnums.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final functions = result.allFunctions.toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  return {
    'package': result.rootPackage.name,
    'annotationNames': result.annotationNames.toList()..sort(),
    'classes': [for (final c in classes) _classReport(c)],
    'enums': [
      for (final e in enums)
        {'name': e.name, 'values': e.values.map((v) => v.name).toList()},
    ],
    'functions': [
      for (final f in functions)
        {'name': f.name, 'returnType': renderType(f.returnType)},
    ],
  };
}

Map<String, dynamic> _classReport(ClassInfo c) {
  final fields = c.fields.toList()..sort((a, b) => a.name.compareTo(b.name));
  final methods = c.methods.toList()..sort((a, b) => a.name.compareTo(b.name));
  return {
    'name': c.name,
    'isAbstract': c.isAbstract,
    if (c.typeParameters.isNotEmpty)
      'typeParameters': c.typeParameters.map((t) => t.name).toList(),
    if (c.superclass != null && c.superclass!.name != 'Object')
      'superclass': renderType(c.superclass!),
    if (c.annotations.isNotEmpty)
      'annotations': c.annotations.map((a) => a.name).toList(),
    'fields': [
      for (final f in fields)
        {'name': f.name, 'type': renderType(f.type), 'isFinal': f.isFinal},
    ],
    'methods': [
      for (final m in methods)
        {
          'name': m.name,
          'returnType': renderType(m.returnType),
          'parameters': m.parameters.map((param) => param.name).toList(),
        },
    ],
  };
}
