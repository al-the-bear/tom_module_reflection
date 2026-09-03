# tom_reflector

> Part of the Tom Framework reflection toolkit — an **original** analyzer-based
> build-time reflection engine © 2024–2026 Peter Nicolai Alexis Kyaw
> (BSD-3-Clause). Unlike its engine-1 siblings
> [`tom_reflection`](../tom_reflection/README.md) /
> [`tom_reflection_generator`](../tom_reflection_generator/README.md) — which are
> derived from the [`reflectable`](https://pub.dev/packages/reflectable) package
> by the Dart team ("Copyright (c) 2015, Dart", BSD-3-Clause) — `tom_reflector`
> shares **no lineage or code** with `reflectable`. See [`LICENSE`](LICENSE).

Build-time, **structural** reflection for Dart. `tom_reflector` is **engine 2**
of the Tom reflection toolkit: instead of mirrors on live objects, it walks the
Dart **analyzer** element model and produces a serializable **object graph of
your code's shape** — classes, methods, parameters, types, annotations — plus
optional `*.r.dart` reflection output that tooling consumes at build time.

This is **original work** (renamed from `tom_analyzer`), with no shared lineage
with `reflectable`. For runtime mirrors on real instances, use the sibling
engine [`tom_reflection`](../tom_reflection/README.md) instead — see the repo
[`README`](../README.md) for how to choose.

## Overview

A code generator or workspace tool often needs to know the *shape* of code —
"what classes are here, what do they implement, what are their members and
annotations?" — without running that code. `dart:mirrors` can't help (it's
runtime and unavailable in AOT), and re-running the analyzer in every downstream
tool is slow and couples you to a specific analyzer/Dart version.

`tom_reflector` solves this by analyzing once and emitting a **stable, pre-resolved
model** ([`tom_reflector_model`](../tom_reflector_model/README.md)) that any tool
can read as plain data. The model is comprehensive (modifiers, type parameters
with bounds, annotations with arguments, source locations), round-trips through
JSON/YAML, and uses cycle-safe ID references when serialized. That stability is
the point: downstream generators are insulated from analyzer churn.

```
   your sources           tom_reflector (analyzer)            outputs
lib/models.dart  ─────►  reachability / barrel analysis  ─►  models.r.dart
lib/app.dart             + element walking                   + AnalysisResult graph
                                                               (tom_reflector_model)
```

## Installation

`tom_reflector` is an internal workspace package (`publish_to: none`); depend on
it by path from within the workspace:

```yaml
dependencies:
  tom_reflector:
    path: ../tom_reflector
```

**SDK:** Dart `^3.10.4`; uses `analyzer ^8`. The compiled `reflector` binary is
produced by the workspace build (`~/.tom/bin/<platform>/reflector`) and is also
reachable as `buildkit :reflector`.

## Two generation modes

| Mode | Driven by | Use it when |
| ---- | --------- | ----------- |
| **Legacy (barrel)** | a barrel file whose exports are all analyzed | you want reflection for *everything* a package exports. |
| **Entry-point (reachability)** | entry points + include/exclude filters | you want precise control — reflect only what's reachable and wanted. |

### Legacy (barrel) mode

```yaml
# buildkit.yaml
tom_reflector:
  barrels:
    - lib/my_package.dart
  follow_re_exports: true
  skip_re_exports:
    - dart.core
```

Generates `lib/my_package.r.dart` for all exports of the barrel.

### Entry-point (reachability) mode

Performs reachability analysis from entry points, with rich **filters**,
configurable **transitive dependency resolution**, and fine-grained **coverage**:

```yaml
# buildkit.yaml
tom_reflector:
  entry_points:
    - lib/my_app.dart
  output: lib/generated/reflection.r.dart

  defaults:
    exclude_packages: ['dart.*']
    include_annotations: ['Reflectable']

  filters:
    - include: { packages: ['my_package'] }
    - exclude: { annotations: ['DoNotReflect'] }

  dependency_config:
    superclasses:   { enabled: true, depth: -1 }
    interfaces:     { enabled: true }
    mixins:         { enabled: true }
    type_arguments: { enabled: true }
    code_bodies:    { enabled: false }

  coverage_config:
    instance_members: { enabled: true }
    static_members:   { enabled: true }
    constructors:     { enabled: true }
    metadata:         { enabled: true }
```

**Configuration reference (entry-point mode):**

| Section | Key | Default | Purpose |
| ------- | --- | ------- | ------- |
| top-level | `entry_points` | `[]` | Roots for reachability analysis. |
| | `output` | *(derived)* | Output path; `.r.dart` appended automatically. |
| | `include_private` | `false` | Include private members. |
| `defaults` | `exclude_packages` / `include_packages` | `[]` | Package globs always excluded / included. |
| | `include_annotations` | `[]` | Annotations that auto-include their target. |
| `filters` | `include` / `exclude` selectors | `[]` | Ordered rules by `packages`, `annotations`, `paths`, `types`, `elements`. |
| `dependency_config` | `superclasses`, `interfaces`, `mixins`, `type_arguments`, `code_bodies` | varies | Transitive resolution (`enabled`, `depth`, `external_depth`, `exclude_types`). |
| `coverage_config` | `instance_members`, `static_members`, `constructors`, `metadata` | `enabled: true` | Which invokers/data to generate. |

## CLI

Run over a configured project, or scan the whole workspace:

```bash
reflector                 # generate for the current project (reads buildkit.yaml)
reflector -R              # recursively scan the workspace for tom_reflector: projects
reflector -e lib/app.dart # entry-point mode (bypasses barrel config)
reflector --list          # list projects that would be processed (no action)
buildkit :reflector       # equivalent, nested under buildkit
```

`dart run bin/reflector.dart [options]` is equivalent before the binary is
compiled.

**Options** (navigation flags like `-R`, `-s`, `-p` come from `tom_build_base`):

| Option | Short | Default | Description |
| ------ | ----- | ------- | ----------- |
| `--config=<path>` | `-c` | `buildkit.yaml` | Config file path. |
| `--entry=<file>` | `-e` | | Entry point(s), repeatable/comma-separated — switches to entry-point mode. |
| `--barrel=<path>` | | *(from config)* | Barrel for legacy mode (overrides config). |
| `--output=<path>` | | *(auto)* | Output file path. |
| `--list` | `-l` | `false` | List target projects, take no action. |
| `--verbose` | `-v` | `false` | Verbose output. |

**Override precedence:** `buildkit.yaml` `tom_reflector:` loads first → `--barrel`
overrides `barrels` → `--output` overrides the derived path → `--entry`
**bypasses** barrel config entirely and switches to entry-point mode.

## Programmatic usage

### Barrel analysis → model

```dart
import 'package:tom_reflector/tom_reflector.dart';

Future<void> main() async {
  final runner = AnalyzerRunner();
  final AnalysisResult result = await runner.analyzeBarrel(
    barrelPath: 'lib/models.dart',
    skipReExports: const ['dart.core'],
  );

  for (final cls in result.allClasses) {
    print('${cls.name}: ${cls.methods.length} methods'); // Order: 3 methods
  }
}
```

### Entry-point reachability → model

```dart
import 'package:tom_reflector/tom_reflector.dart';

Future<void> main() async {
  final config = ReflectionConfig(
    entryPoints: const ['lib/my_app.dart'],
    defaults: const ReflectionDefaults(includeAnnotations: ['Reflectable']),
  );
  final analyzer = EntryPointAnalyzer(config);
  final result = await analyzer.analyze();
  // result holds the reachable, filtered set; feed it to ReflectionGenerator.
}
```

## `.r.dart` output

In either mode the `ReflectionGenerator` emits a `*.r.dart` file holding the
reflection data alongside the source. Treat `*.r.dart` as a **build output** —
never hand-edit it; fix the generator/config and regenerate.

## Architecture

```
package:tom_reflector/tom_reflector.dart   (public API; re-exports tom_reflector_model)
├── src/analyzer/         drive the analyzer & build the model
│   ├── AnalyzerRunner            barrel analysis → AnalysisResult
│   ├── AnalyzerContextBuilder    analysis context setup
│   ├── BarrelAnalyzer            legacy barrel mode
│   ├── ElementVisitor / TypeResolver, AnnotationParser
├── src/reflection/generator/    entry-point reachability
│   ├── EntryPointAnalyzer        reachability + filters → ReflectionAnalysisResult
│   ├── ReflectionConfig          filters, dependency & coverage config
│   └── ReflectionGenerator       emits *.r.dart
└── src/v2/   reflectorTool + ReflectorExecutor (tom_build_base CLI)

bin/reflector.dart  → ToolRunner(reflectorTool)  → `reflector` / `buildkit :reflector`
```

### Key types

| Type | Responsibility |
| ---- | -------------- |
| `AnalyzerRunner` | Entry point for **barrel** analysis (`analyzeBarrel`) → `AnalysisResult`. |
| `AnalyzerContextBuilder` | Builds the analyzer `AnalysisContextCollection`. |
| `BarrelAnalyzer` | Legacy barrel-export walking. |
| `EntryPointAnalyzer` | **Reachability** analysis from entry points (`analyze()`). |
| `ReflectionConfig` | Entry-point configuration: `entryPoints`, `filters`, `dependencyConfig`, `coverageConfig`, `includePrivate`; `load()` / `fromMap()`. |
| `ReflectionGenerator` | Emits `*.r.dart` from the analyzed model. |
| `ReflectionModel` | In-memory reflection model for generation. |
| `reflectorTool` / `ReflectorExecutor` | `tom_build_base` CLI surface (`reflector`). |

The pure data model itself (`AnalysisResult`, `ClassInfo`, …) lives in
[`tom_reflector_model`](../tom_reflector_model/README.md) and is re-exported here.

## Ecosystem

```
tom_reflector_model   pure serializable model (AnalysisResult, ClassInfo, …)
      ▲ re-exports
tom_reflector         THIS PACKAGE — analyzer engine + `reflector` CLI → *.r.dart
      │ builds on
      ├── tom_build_base   v2 tool framework (CLI, navigation, version flags)
      └── tom_ast_model    serializable mirror AST (cross-repo: tom_ai/d4rt/)
```

> `tom_ast_model` lives in the **d4rt** repo; changes there can affect this
> package — coordinate with the d4rt quest on breaking changes. It is consumed
> hosted, with a version floor, so what this package was tested against is on
> the record rather than being whatever the sibling checkout holds.

This is the engine-2 generator. The runtime mirror engine
([`tom_reflection`](../tom_reflection/README.md)) is a separate technology with
its own generator emitting `*.reflection.dart`.

## Further documentation

- CLI usage: [`doc/reflector_usage_guide.md`](doc/reflector_usage_guide.md)
- Reflection guide: [`doc/reflection_user_guide.md`](doc/reflection_user_guide.md)
- Analyzer usage & config reference: [`doc/analyzer_usage_guide.md`](doc/analyzer_usage_guide.md)
- Implementation notes: [`doc/reflection_implementation.md`](doc/reflection_implementation.md)
- Design (pre-rename `tom_analyzer`): [`doc/tom_analyzer_design.md`](doc/tom_analyzer_design.md)
- Analyzer element API: [`doc/analyzer_element_api.md`](doc/analyzer_element_api.md)

### Runnable samples (engine 2)

- Parser mode (no codegen): [`reflector_parser_introduction_sample`](../tom_reflection_samples/reflector_parser_introduction_sample/README.md)
  → [`reflector_parser_advanced_sample`](../tom_reflection_samples/reflector_parser_advanced_sample/README.md)
- Codegen mode (`*.r.dart`): [`reflector_reflection_introduction_sample`](../tom_reflection_samples/reflector_reflection_introduction_sample/README.md)
  → [`reflector_reflection_advanced_sample`](../tom_reflection_samples/reflector_reflection_advanced_sample/README.md)

> **Naming note:** some `doc/` files predate the `tom_analyzer → tom_reflector`
> rename and still say "tom_analyzer"/"tom_analyzer_model". Read those names as
> the pre-rename identity of `tom_reflector`/`tom_reflector_model`.

## Status

- **Version:** 1.0.0 (`publish_to: none`, internal workspace package).
- **SDK:** Dart `^3.10.4`; `analyzer ^8`.
- **Modes:** legacy barrel + entry-point reachability, both implemented.
- **CLI:** `reflector` standalone and `buildkit :reflector`, on `tom_build_base`
  navigation.

## License

BSD 3-Clause — original Tom Framework work (no `reflectable` lineage). See
[`LICENSE`](LICENSE).
