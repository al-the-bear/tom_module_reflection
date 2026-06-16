# tom_reflector_model

> Part of the Tom Framework reflection toolkit — an original analyzer-based
> build-time reflection engine (BSD 3-Clause). See [`LICENSE`](LICENSE).

The **pure, serializable object model** behind engine 2 of the Tom reflection
toolkit. It is the typed snapshot of a program's structure — libraries,
packages, classes, enums, mixins, extensions, functions, members, parameters,
types and annotations — that [`tom_reflector`](../tom_reflector/README.md)
produces and that downstream generators and tools consume.

Crucially, this package **has no dependency on the Dart analyzer** (only
`collection` and `yaml`). That is the whole point: the analyzer-heavy work lives
in `tom_reflector`, while the *data* lives here as plain Dart objects that any
tool can read, round-trip through JSON/YAML, and depend on without inheriting an
`analyzer` version constraint.

## Overview

A reflection result has to travel: it is produced once (by the analyzer), then
read many times by code generators, doc tools and workspace indexers — often in
separate processes, sometimes from disk. For that to be stable and cheap, the
result must be **plain data**, not a live analyzer element tree.

`tom_reflector_model` provides exactly that:

- A comprehensive object graph rooted at **`AnalysisResult`** (packages →
  libraries → declarations → members → types/annotations), with full modifiers,
  type parameters and bounds, annotation arguments, and source locations.
- **In memory**, elements reference each other directly (e.g. `ClassInfo.superclass`
  is a `TypeReference`); **on the wire**, references are encoded by stable `id`
  so cyclic graphs round-trip safely.
- **JSON and YAML** serializers/deserializers plus a validator, so a result can
  be persisted and later re-read or validated independently of the analyzer.

```
tom_reflector  ──►  AnalysisResult (this package)  ──►  JSON / YAML on disk
 (analyzer)          plain Dart objects                  ◄── re-read by any tool
```

## Installation

`tom_reflector_model` is an internal workspace package (`publish_to: none`);
depend on it by path:

```yaml
dependencies:
  tom_reflector_model:
    path: ../tom_reflector_model
```

**SDK:** Dart `^3.10.4`. Dependencies are deliberately minimal: `collection`,
`yaml`. It is also re-exported by `tom_reflector`, so depending on the engine
gives you the model for free.

## The model

### Roots and containers

| Type | Represents |
| ---- | ---------- |
| `AnalysisResult` | The root: `packages`, `libraries`, `files`, plus `timestamp`, `dartSdkVersion`, `analyzerVersion`, `schemaVersion`, `errors`. |
| `PackageInfo` | A package and its libraries. |
| `LibraryInfo` | A library: its classes, enums, mixins, extensions, functions, variables, getters/setters. |
| `FileInfo` | A source file (path, package). |
| `ImportInfo` / `ExportInfo` | Library import/export directives. |

### Type declarations (extend `TypeDeclaration`)

| Type | Represents |
| ---- | ---------- |
| `ClassInfo` | A class — modifiers (`isAbstract`, `isSealed`, `isFinal`, `isBase`, `isInterface`, `isMixin`), `superclass`, `interfaces`, `mixins`, `typeParameters`, `constructors`, `methods`, `fields`, `getters`, `setters`. |
| `EnumInfo` | An enum and its `EnumValueInfo` values. |
| `MixinInfo` | A mixin declaration. |
| `ExtensionInfo` | An extension. |
| `ExtensionTypeInfo` | An extension type. |
| `TypeAliasInfo` | A `typedef`. |

### Members

| Type | Represents |
| ---- | ---------- |
| `MethodInfo` | A method (`isOperator`, `isStatic`, parameters, return type). |
| `ConstructorInfo` | A constructor (named/factory/const). |
| `FunctionInfo` | A top-level function. |
| `FieldInfo` / `VariableInfo` | An instance field / top-level variable. |
| `GetterInfo` / `SetterInfo` | Accessors. |

### Supporting types

| Type | Represents |
| ---- | ---------- |
| `ParameterInfo` | A parameter (named/optional/required, default value). |
| `TypeParameterInfo` | A generic type parameter with its bound. |
| `TypeReference` | A reference to a type (name, type arguments, nullability). |
| `FunctionTypeInfo` | A function-type signature. |
| `AnnotationInfo` / `ArgumentValue` | An annotation and its parsed arguments. |
| `SourceLocation` | Offset/line/column into a source file. |
| `AnalysisError` | A diagnostic captured during analysis. |
| `ElementNotFoundException` / `AmbiguousElementException` | Lookup failures. |

### Navigating a result

```dart
result.allClasses;     // flatten classes across all libraries
result.allEnums;       // … enums, allMixins, allFunctions, allGetters, …
result.findClass('package:my/models.dart::Order');   // by qualified name
result.findClassesByName('Order');                   // by simple name
result.findClassesWithAnnotation('Reflectable');     // by annotation
result.findFunctionsWithAnnotation('entryPoint');
```

## Serialization

Serializers and deserializers are **static**; the validator is an instance.

```dart
import 'dart:io';
import 'package:tom_reflector_model/tom_reflector_model.dart';

void main() {
  // A result is normally produced by tom_reflector; here we re-read one
  // saved to disk.
  final jsonText = File('analysis.json').readAsStringSync();

  // Validate untrusted input before decoding.
  final issues = AnalysisResultValidator().validateJson(jsonText);
  if (issues.isNotEmpty) throw StateError('invalid analysis: $issues');

  // Decode into the in-memory graph (id references rewired to objects).
  final AnalysisResult result = JsonDeserializer.decode(jsonText);

  for (final cls in result.allClasses) {
    print('${cls.qualifiedName}: '
        '${cls.methods.length} methods, ${cls.fields.length} fields');
    // package:my/models.dart::Order: 3 methods, 4 fields
  }

  // Round-trip back out — JSON (pretty) or YAML.
  final json = JsonSerializer.encode(result);   // String
  final yaml = YamlSerializer.encode(result);   // String
  final map  = JsonSerializer.toMap(result);    // Map<String, dynamic>

  // YAML re-reads symmetrically.
  final restored = YamlDeserializer.decode(yaml);
  print(restored.allClasses.length == result.allClasses.length); // true
}
```

| API | Direction |
| --- | --------- |
| `JsonSerializer.encode(result)` / `.toMap(result)` | model → JSON string / map |
| `JsonDeserializer.decode(source)` / `.fromMap(map)` | JSON string / map → model |
| `YamlSerializer.encode(result)` | model → YAML string |
| `YamlDeserializer.decode(source)` | YAML string → model |
| `AnalysisResultValidator().validateJson` / `validateYaml` / `validateMap` | check before decoding → `List<ValidationIssue>` |
| `IdGenerator().nextId(prefix)` | mint stable element ids |

### Cycle-safe references

Code graphs are cyclic (a class refers to types that refer back to it). In
memory the model uses direct object references; for serialization, every element
carries an `id` and references are emitted **by id**, so the writer never
recurses infinitely and the reader rebuilds the object graph by resolving ids.
`IdGenerator` mints those ids.

## Configuration

`TomAnalyzerConfig` is the plain-data configuration record shared by the engine
(barrels, output format/file, re-export following, workspace root):

```dart
const config = TomAnalyzerConfig(
  barrels: ['lib/models.dart'],
  outputFormat: 'yaml',           // or 'json'
  followReExports: true,
  skipReExports: ['dart.core'],
);
```

## Architecture

```
package:tom_reflector_model/tom_reflector_model.dart
├── src/model/           the object graph (AnalysisResult, ClassInfo, …)
├── src/serialization/   JsonSerializer/Deserializer, YamlSerializer/Deserializer,
│                        AnalysisResultValidator, IdGenerator
└── src/config/          TomAnalyzerConfig
```

No analyzer, no build dependency — just data, serialization and config. This is
what keeps downstream tools insulated from analyzer/Dart version churn.

### Key types

| Type | Responsibility |
| ---- | -------------- |
| `AnalysisResult` | Root of the model; flattening getters (`allClasses`, …) and lookups (`findClass`, …). |
| `ClassInfo` / `EnumInfo` / `MixinInfo` / `ExtensionInfo` / `TypeAliasInfo` | Type declarations with full modifiers and members. |
| `MethodInfo` / `FieldInfo` / `ParameterInfo` / `TypeParameterInfo` | Members and their shape. |
| `TypeReference` | Cycle-safe reference to a type. |
| `AnnotationInfo` / `ArgumentValue` | Annotations with parsed arguments. |
| `JsonSerializer` / `JsonDeserializer` | JSON round-trip (static). |
| `YamlSerializer` / `YamlDeserializer` | YAML round-trip (static). |
| `AnalysisResultValidator` | Validate serialized input before decoding. |
| `IdGenerator` | Stable id minting for cycle-safe references. |
| `TomAnalyzerConfig` | Engine configuration as plain data. |

## Ecosystem

```
tom_reflector_model   THIS PACKAGE — pure model + serialization (no analyzer dep)
      ▲ re-exported & produced by
tom_reflector         analyzer engine + `reflector` CLI → AnalysisResult + *.r.dart
```

`tom_reflector_model` is the contract; `tom_reflector` fills it. Tools that only
*read* analysis results can depend on this package alone and stay free of the
`analyzer` dependency. The runtime-mirror engine
([`tom_reflection`](../tom_reflection/README.md)) is a separate technology — see
the repo [`README`](../README.md).

## Status

- **Version:** 1.0.0 (`publish_to: none`, internal workspace package).
- **SDK:** Dart `^3.10.4`.
- **Dependencies:** `collection`, `yaml` only — deliberately analyzer-free.
- **Capabilities:** comprehensive object model, JSON + YAML round-trip,
  validation, cycle-safe id references.

## License

BSD 3-Clause — original Tom Framework work (no `reflectable` lineage). Renamed
from `tom_analyzer_model`. See [`LICENSE`](LICENSE).
