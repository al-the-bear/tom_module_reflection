# Tom Reflection — runtime and build-time reflection for Dart

> Part of the Tom Framework. This repository carries **mixed license lineage**:
> the `tom_reflection*` packages are **derived from the
> [`reflectable`](https://pub.dev/packages/reflectable) package by the Dart team**
> ([`google/reflectable.dart`](https://github.com/google/reflectable.dart),
> "Copyright (c) 2015, Dart", BSD-3-Clause) — with Tom-specific refactoring, fixes
> and enhancements © 2024–2026 Peter Nicolai Alexis Kyaw, released under the same
> BSD-3-Clause terms — while the `tom_reflector*` packages are **original work**
> (© 2024–2026 Peter Nicolai Alexis Kyaw, BSD-3-Clause) sharing no lineage with
> `reflectable`. Each derived package retains the upstream copyright in its
> `LICENSE` and records the derivation in a `NOTICE` file. See
> [`LICENSE.md`](LICENSE.md).

This document is the **map**. It orients you to the whole reflection ecosystem
and routes you to the one package you actually want — each package then has its
own README with the full manual.

**New here?** Start with the samples:
[`tom_reflection_samples/reflection_introduction_sample`](tom_reflection_samples/reflection_introduction_sample/README.md)
for runtime mirrors, or
[`tom_reflection_samples/reflector_parser_introduction_sample`](tom_reflection_samples/reflector_parser_introduction_sample/README.md)
for the build-time structural model.

## What you can do with Tom Reflection

- **Invoke members by name on a live object** — call methods, read/write
  fields, construct instances and read metadata at runtime, without knowing the
  type at compile time (engine 1).
- **Get a serializable model of your code's shape** — classes, methods,
  parameters, types and annotations as plain data a code generator or tool can
  consume at build time (engine 2).
- **Keep generated code small** — declare exactly which reflective operations
  you need via *capabilities*, so only the necessary mirror data is emitted.
- **Generate `*.reflection.dart` and `*.r.dart`** from `build_runner`, a
  standalone CLI, or nested under `buildkit`.

## Two engines (the one thing to understand first)

This repo holds **two distinct reflection technologies**. They are not two
versions of one thing — they have different origins, run at different times, and
serve different consumers. Pick the right one before reading any package README.

| | **Engine 1 — `tom_reflection`** | **Engine 2 — `tom_reflector`** |
|---|---|---|
| Origin | fork of `reflectable` (Dart team) | original work (ex `tom_analyzer`) |
| When it runs | **runtime** — mirrors on live objects | **build time** — static analysis |
| Output | `*.reflection.dart` | `*.r.dart` + `tom_reflector_model` object graph |
| Driven by | capabilities + annotations | barrels **or** entry-point reachability |
| Primary consumer | app code doing dynamic dispatch | code generators / tooling |
| License lineage | BSD 3-Clause (retains © Dart) | BSD 3-Clause (Tom ©) |

**Use engine 1** when code must invoke members / read metadata *by name at
runtime* on real instances (serialization, dependency injection, dynamic
dispatch). **Use engine 2** when a *code generator or tool* needs a stable,
pre-resolved view of code structure at build time (bridge generation, doc
generation, workspace indexing), insulated from analyzer/Dart version churn.

## Components

### Engine 1 — runtime mirrors

| Package | What it is | Binary |
|---------|-----------|--------|
| [`tom_reflection`](tom_reflection/README.md) | Runtime mirror-based reflection library — the `reflectable` fork. Defines `Reflection`, the capability set, and the mirror API. | — |
| [`tom_reflection_generator`](tom_reflection_generator/README.md) | Code generator for engine 1: a `build_runner` builder **and** standalone/buildkit-nested CLI that emits `*.reflection.dart`. | `reflectiongenerator` |
| [`tom_reflection_test`](tom_reflection_test/README.md) | End-to-end fixture suite exercising the engine-1 generator (not user-facing samples). | — |

### Engine 2 — build-time structural model

| Package | What it is | Binary |
|---------|-----------|--------|
| [`tom_reflector`](tom_reflector/README.md) | Analyzer-based reflection engine + CLI. Two modes: legacy barrels and entry-point reachability. Emits `*.r.dart`. | `reflector` |
| [`tom_reflector_model`](tom_reflector_model/README.md) | Pure, serializable object model for engine-2 results (classes, methods, parameters, types) with JSON/YAML round-trip. | — |

### Samples

| Folder | What it is |
|--------|-----------|
| [`tom_reflection_samples`](tom_reflection_samples/README.md) | Seven runnable sample projects with long-form tutorials, split across both engines. |

## Getting started

### Engine 1 — reflect on a live object

```dart
import 'package:tom_reflection/tom_reflection.dart';
import 'person.reflection.dart'; // generated

class MyReflector extends Reflection {
  const MyReflector()
      : super(invokingCapability, declarationsCapability, typeCapability);
}

const myReflector = MyReflector();

@myReflector
class Person {
  String greet(String who) => 'Hello, $who!';
}

void main() {
  initializeReflection();
  final mirror = myReflector.reflect(Person());
  print(mirror.invoke('greet', ['Alice'])); // Hello, Alice!
}
```

Generate the `*.reflection.dart` with the builder
(`dart run build_runner build`) or the CLI (`reflectiongenerator` /
`buildkit :reflectiongenerator`).

### Engine 2 — analyze code into a model

```dart
import 'package:tom_reflector/tom_reflector.dart';

void main() async {
  final runner = AnalyzerRunner();
  final AnalysisResult result = await runner.analyze(['lib/models.dart']);
  for (final cls in result.allClasses) {
    print('${cls.name}: ${cls.methods.length} methods'); // Order: 3 methods
  }
}
```

Or run the CLI over a configured project: `reflector` / `buildkit :reflector`,
which emits `*.r.dart` plus the serializable `tom_reflector_model` graph.

## Samples — learning path

Ordered beginner → advanced; engine 1 first, then engine 2.

| Sample | Engine | Demonstrates |
|--------|--------|--------------|
| [`reflection_introduction_sample`](tom_reflection_samples/reflection_introduction_sample/README.md) | 1 | Annotate → generate → reflect → invoke; read a getter on a small domain. |
| [`reflection_advanced_sample`](tom_reflection_samples/reflection_advanced_sample/README.md) | 1 | Declarations, `newInstance`, static members, type relations, generics & mixins. |
| [`reflection_capability_sample`](tom_reflection_samples/reflection_capability_sample/README.md) | 1 | How each capability gates generated code; minimal vs `useAllCapabilities`; pattern capabilities. |
| [`reflector_parser_introduction_sample`](tom_reflection_samples/reflector_parser_introduction_sample/README.md) | 2 | Analyze sources → `AnalysisResult` → JSON round-trip → walk the model. |
| [`reflector_reflection_introduction_sample`](tom_reflection_samples/reflector_reflection_introduction_sample/README.md) | 2 | Generate `*.r.dart` for a project and consume the reflection at runtime. |
| [`reflector_parser_advanced_sample`](tom_reflection_samples/reflector_parser_advanced_sample/README.md) | 2 | Deep model dive: type-argument resolution, annotations, mixins/extensions, cycle-safe IDs, YAML. |
| [`reflector_reflection_advanced_sample`](tom_reflection_samples/reflector_reflection_advanced_sample/README.md) | 2 | Entry-point reachability with filters, transitive resolution, coverage config. |

## Documentation index

| Topic | Document |
|-------|----------|
| Engine-1 generator (builder + CLI) | [`tom_reflection_generator/doc/reflection_generator.md`](tom_reflection_generator/doc/reflection_generator.md) |
| Engine-1 generator CLI reference | [`tom_reflection_generator/doc/reflectiongenerator_user_reference.md`](tom_reflection_generator/doc/reflectiongenerator_user_reference.md) |
| Engine-1 generator internals | [`tom_reflection_generator/doc/reflection_generator_implementation.md`](tom_reflection_generator/doc/reflection_generator_implementation.md) |
| Analyzer summary caching | [`tom_reflection_generator/doc/analyzer_summary_integration.md`](tom_reflection_generator/doc/analyzer_summary_integration.md) |
| Engine-2 CLI usage | [`tom_reflector/doc/reflector_usage_guide.md`](tom_reflector/doc/reflector_usage_guide.md) |
| Engine-2 reflection guide | [`tom_reflector/doc/reflection_user_guide.md`](tom_reflector/doc/reflection_user_guide.md) |
| Engine-2 design (ex `tom_analyzer`) | [`tom_reflector/doc/tom_analyzer_design.md`](tom_reflector/doc/tom_analyzer_design.md) |

## Repository layout

```
tom_reflection/                  # this repo (GitHub: al-the-bear/tom_reflection, public, BSD 3-Clause)
├── tom_reflection/              # engine 1: runtime mirror library (reflectable fork)
├── tom_reflection_generator/    # engine 1: *.reflection.dart generator (builder + `reflectiongenerator` CLI)
├── tom_reflection_test/         # engine 1: end-to-end fixture suite
├── tom_reflector/               # engine 2: analyzer-based engine + `reflector` CLI → *.r.dart
├── tom_reflector_model/         # engine 2: pure serializable object model
├── tom_reflection_samples/      # seven runnable sample projects (both engines)
└── LICENSE.md                   # points at each package's own LICENSE
```

## License

BSD-3-Clause, public. Lineage is load-bearing: `tom_reflection*` retain the
upstream `reflectable` copyright ("Copyright (c) 2015, Dart" — `reflectable` is
by the Dart team, [`google/reflectable.dart`](https://github.com/google/reflectable.dart))
alongside Tom's modifications (© 2024–2026 Peter Nicolai Alexis Kyaw) and record
the derivation in each derived package's `NOTICE`; `tom_reflector*` are Tom's own
work. See [`LICENSE.md`](LICENSE.md) and each package's `LICENSE`.
