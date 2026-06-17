// Shared analysis helpers for the engine-2 parser ADVANCED sample.
//
// Engine 2 (`tom_reflector`) runs the Dart analyzer over source *text* and
// returns an `AnalysisResult` — a pure, serializable object model. This sample
// digs into the model's harder corners (generics, mixins, extensions, cyclic
// references) and projects them into a deterministic API-surface index.
//
// The analyzed source set lives in `sample_source/` — a dependency-free
// pure-Dart package, input data rather than part of this project's own code.
//
// Every scenario starts from `analyzeShop()`; the type renderer and the
// API-surface builder layer on top of it.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_reflector/tom_reflector.dart';

/// Analyzes the bundled `sample_source/` package and returns its model.
Future<AnalysisResult> analyzeShop() async {
  final sourceRoot = _findSampleSourceRoot();
  final barrel = p.join(sourceRoot, 'lib', 'shop.dart');
  return TomAnalyzer().analyzeBarrel(
    barrelPath: barrel,
    workspaceRoot: sourceRoot,
  );
}

/// Locates `sample_source/` by walking up from the current directory, so the
/// scenarios run both standalone and through the aggregator, as long as they
/// are launched from inside the sample tree.
String _findSampleSourceRoot() {
  var dir = Directory.current.absolute.path;
  for (var i = 0; i < 8; i++) {
    final candidate = p.join(dir, 'sample_source');
    if (File(p.join(candidate, 'lib', 'shop.dart')).existsSync()) {
      return candidate;
    }
    final parent = p.dirname(dir);
    if (parent == dir) break;
    dir = parent;
  }
  throw StateError(
    'Could not locate sample_source/. Run the scenarios from inside the '
    'reflector_parser_advanced_sample directory.',
  );
}

/// Renders a [TypeReference] the way it reads in source: `List<Order>`,
/// `Map<String, List<OrderLine>>`, `Node<T>?`, `void`.
///
/// The renderer reads only the **inline** structure of the reference — `name`,
/// `typeArguments`, `isNullable` — which is exactly the data that survives a
/// JSON/YAML round-trip. It does NOT depend on `resolvedElement`, the in-memory
/// cross-link that is not rebuilt on deserialization (see the README).
String renderType(TypeReference type) {
  if (type.isVoid) return 'void';
  if (type.isDynamic) return 'dynamic';
  final args = type.typeArguments.isEmpty
      ? ''
      : '<${type.typeArguments.map(renderType).join(', ')}>';
  final suffix = type.isNullable ? '?' : '';
  return '${type.name}$args$suffix';
}

/// Renders a generic parameter with its bound: `T extends Entity`, or just `T`.
String renderTypeParameter(TypeParameterInfo tp) {
  final bound = tp.bound;
  return bound == null ? tp.name : '${tp.name} extends ${renderType(bound)}';
}

/// Builds a **deterministic** API-surface index of the analyzed shop domain.
///
/// This is the sample's non-trivial tool: a stable, reviewable projection that
/// captures inheritance (extends / with / implements), generic shapes, mixins
/// and extensions — every collection sorted so the bytes are identical on every
/// run. Volatile fields (ids, timestamps, paths, hashes) are dropped.
Map<String, dynamic> buildApiSurface(AnalysisResult result) {
  final classes = result.allClasses.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final mixins = result.allMixins.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final extensions = result.allExtensions.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final enums = result.allEnums.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final functions = result.allFunctions.toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  return {
    'package': result.rootPackage.name,
    'classes': [for (final c in classes) _classSurface(c)],
    'mixins': [
      for (final m in mixins)
        {
          'name': m.name,
          'on': m.onTypes.map(renderType).toList(),
          'methods': (m.methods.map((x) => x.name).toList()..sort()),
        },
    ],
    'extensions': [
      for (final e in extensions)
        {
          'name': e.name,
          'on': renderType(e.extendedType),
          'methods': (e.methods.map((x) => x.name).toList()..sort()),
        },
    ],
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

Map<String, dynamic> _classSurface(ClassInfo c) {
  final fields = c.fields.toList()..sort((a, b) => a.name.compareTo(b.name));
  final methods = c.methods.toList()..sort((a, b) => a.name.compareTo(b.name));
  return {
    'name': c.name,
    if (c.isAbstract) 'isAbstract': true,
    if (c.typeParameters.isNotEmpty)
      'typeParameters': c.typeParameters.map(renderTypeParameter).toList(),
    if (c.superclass != null && c.superclass!.name != 'Object')
      'extends': renderType(c.superclass!),
    if (c.mixins.isNotEmpty) 'with': c.mixins.map(renderType).toList(),
    if (c.interfaces.isNotEmpty)
      'implements': c.interfaces.map(renderType).toList(),
    if (c.annotations.isNotEmpty)
      'annotations': c.annotations.map((a) => a.name).toList(),
    'fields': [
      for (final f in fields)
        {'name': f.name, 'type': renderType(f.type), 'isFinal': f.isFinal},
    ],
    'methods': [
      for (final m in methods)
        {'name': m.name, 'returnType': renderType(m.returnType)},
    ],
  };
}
