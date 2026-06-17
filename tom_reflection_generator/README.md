# tom_reflection_generator

> Part of the Tom Framework reflection toolkit. **Derived from the
> [`reflectable`](https://pub.dev/packages/reflectable) package by the Dart team**
> ([`google/reflectable.dart`](https://github.com/google/reflectable.dart),
> "Copyright (c) 2015, Dart", BSD-3-Clause); Tom-specific refactoring, fixes and
> enhancements © 2024–2026 Peter Nicolai Alexis Kyaw, released under the same
> BSD-3-Clause terms. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

The code generator for **engine 1** of the Tom reflection toolkit. It reads the
`@reflector` annotations produced with [`tom_reflection`](../tom_reflection/README.md)
and emits the `*.reflection.dart` files that hold the precomputed,
capability-gated mirror data.

It ships **two interchangeable surfaces over one generation pipeline**:

- a **`build_runner` builder** for the usual `dart run build_runner build` flow, and
- a standalone **`reflectiongenerator` CLI** (built on `tom_build_base` v2) that
  also nests under buildkit as `buildkit :reflectiongenerator`.

## Overview

`tom_reflection` keeps generated code small by gating it behind *capabilities*.
This package is the tool that does the gating: it runs the Dart **analyzer** over
your sources, finds classes annotated with a `Reflection` subclass, reads the
capabilities that reflector declares, and writes exactly the mirror data those
capabilities require into a sibling `*.reflection.dart` file. Your app then calls
the generated `initializeReflection()` once and reflects at runtime.

```
   your sources                 tom_reflection_generator              output
@myReflector class Foo  ──►  analyze → read capabilities → emit  ──►  foo.reflection.dart
                             (builder  OR  reflectiongenerator CLI)
```

Both surfaces share the same analyzer infrastructure
(`StandaloneLibraryResolver`, `FileId`) and the same generation core, so the
builder and the CLI produce byte-identical output for the same input. The package
was extracted from `tom_build_tools`; the CLI was rebuilt on the
[`tom_build_base`](../../basics/tom_build_base/README.md) v2 tool framework so it
gains standard arg parsing, `--help`/`--version` and buildkit nesting for free.

## Installation

The generator is a **development-time** dependency — your shipped package depends
only on `tom_reflection`.

```yaml
dev_dependencies:
  build_runner: ^2.4.0
  tom_reflection_generator: ^1.1.1
```

Or:

```bash
dart pub add --dev build_runner tom_reflection_generator
```

**SDK:** Dart `^3.10.4`. Pulls in `analyzer ^8`, `build ^4`,
[`tom_analyzer_shared`](https://pub.dev/packages/tom_analyzer_shared) (summary
cache), `tom_build_base` (v2 tool framework) and `tom_reflection`.

## Features

| Surface | Entry point | Use it for |
| ------- | ----------- | ---------- |
| `build_runner` builder | `reflectionGenerator(BuilderOptions)` (`tom_reflection_generator:reflection_generator`) | The standard generate-on-build workflow. |
| Standalone CLI | binary `reflectiongenerator` / `dart run tom_reflection_generator` | One-off and CI generation, scriptable. |
| Buildkit-nested CLI | `buildkit :reflectiongenerator` | Workspace-wide generation across many projects. |
| Programmatic API | `package:tom_reflection_generator/tom_reflection_generator.dart` | Embedding the pipeline in your own tool. |

Other features: analyzer **summary caching** for dependencies (faster repeat
runs), capability-gated output, configurable output extension, and a
`--useAllCapabilities` escape hatch that ignores the declared capabilities and
emits full metadata.

## Quick start

### As a build_runner builder

Add `build.yaml` to the package that has the annotated classes:

```yaml
targets:
  $default:
    builders:
      tom_reflection_generator:reflection_generator:
        generate_for:
          - lib/**.dart
          - example/**.dart
```

Then:

```bash
dart run build_runner build
# writes lib/<file>.reflection.dart next to each annotated source
```

The builder is `auto_apply: dependents` and `build_to: source`, so any package
that depends on `tom_reflection_generator` gets the builder and the generated
files land in the source tree (committable).

### As the standalone CLI

```bash
# Generate for a single entry point
reflectiongenerator lib/main.dart

# Treat a directory as recursive
reflectiongenerator --all lib/

# Build mode: drive generation from build.yaml generate_for patterns
reflectiongenerator build

# Explicit globs in build mode
reflectiongenerator build "lib/**.dart" "test/**_test.dart"

# Self-describe (version + build timestamp, see Versioning below)
reflectiongenerator version
```

`dart run tom_reflection_generator <args>` is equivalent before the binary is
compiled.

## Configuration

### build.yaml (build_runner / CLI build mode)

The builder maps `.dart` → `.reflection.dart` and is configured by the standard
`generate_for` glob list shown above.

### buildkit.yaml (nested / traversal mode)

In nested or traversal mode the generator reads a `tom_reflection_generator:`
section from each project's `buildkit.yaml`:

```yaml
tom_reflection_generator:
  generate_for:
    - lib/**/*.dart
  package: tom_reflection          # reflector package whose annotations trigger generation
  extension: .reflection.dart      # output file extension
  use_all_capabilities: false      # emit only declared capabilities
```

**Target-resolution precedence** (per project, in nested/traversal mode):

1. If `buildkit.yaml` has a `tom_reflection_generator:` section, its
   `generate_for` patterns are used.
2. Otherwise the generator falls back to the project's `build.yaml`
   `generate_for` patterns.
3. If neither is present, the project is **skipped**.

### CLI options

Tool-specific options (framework options like `--verbose`/`-v`, `--help`/`-h`,
`--version`, `--nested` and project-traversal flags are contributed by
`tom_build_base`):

| Option | Description |
| ------ | ----------- |
| `--all` | Process directory targets recursively. |
| `--package` | Reflection package whose annotations trigger generation (default `tom_reflection`). No `-p` — `-p` is the standard `--project` traversal flag. |
| `--extension`, `-e` | Output file extension (default `.reflection.dart`). |
| `--config`, `-c` | `build.yaml` path for the build-mode fallback (default `build.yaml`). |
| `--useAllCapabilities` | Emit full metadata regardless of declared capabilities. |
| `--no-cache` | Disable analyzer summary caching for dependencies. |
| `--rebuild-cache` | Force regeneration of all cached summaries. |
| `--show-cache-status` | List which packages have cached summaries, then stop. |
| `--cache-only <package>` | Restrict summary caching to the given package(s) (repeatable). |

> **Summary caching:** caching speeds up repeat runs by reusing analyzer
> summaries of unchanged dependencies (via `tom_analyzer_shared`). If a run in a
> compiled/AOT environment misbehaves on summary discovery, `--no-cache` is the
> reliable fallback while still producing correct output.

## Versioning

`buildkit.yaml` declares a `versioner` block so the compiled binary always
embeds the current version, build number, git commit and build timestamp:

```yaml
versioner:
  variable-prefix: reflectionGen   # → generated class ReflectionGenVersionInfo
```

The `:v` stage runs before `:comp`, regenerating
`lib/src/version.versioner.dart`, so `reflectiongenerator version` reports the
exact build it was compiled from.

## Programmatic usage

Embed the pipeline in your own tool:

```dart
import 'package:tom_reflection_generator/tom_reflection_generator.dart';

Future<void> main() async {
  final resolver = await StandaloneLibraryResolver.create('path/to/project');

  final generator = GeneratorImplementation();
  final inputId = FileId('my_package', 'lib/main.dart');
  final outputId = inputId.changeExtension('.reflection.dart');
  final library = await resolver.libraryFor(inputId);
  final visibleLibraries = await resolver.libraries;

  final source = await generator.buildMirrorLibrary(
    resolver,
    inputId,
    outputId,
    library,
    visibleLibraries.cast(),
    true,        // formatted
    const [],    // extra suppress-warnings
  );
  // Write `source` to outputId.
}
```

For the buildkit-nestable tool surface, import the v2 library instead:

```dart
import 'package:tom_reflection_generator/reflection_generator_v2.dart';
// exposes reflectionGeneratorTool and ReflectionGeneratorExecutor
```

## Architecture

```
package:tom_reflection_generator/
├── reflection_generator.dart   build_runner builder:
│   ├── ReflectionGenerator (implements Builder)
│   └── reflectionGenerator(BuilderOptions) factory
├── reflection_generator_v2.dart  tom_build_base v2 tool surface:
│   ├── reflectionGeneratorTool (ToolDefinition, single-command)
│   └── ReflectionGeneratorExecutor (CommandExecutor)
├── src/generation/             shared generation core (capability gating)
└── src/reflection_generator/   analyzer infra: StandaloneLibraryResolver, FileId

bin/tom_reflection_generator.dart  → ToolRunner(reflectionGeneratorTool)  → `reflectiongenerator`
```

Both surfaces converge on the same generation core, which is why builder and CLI
output match byte-for-byte. The CLI's single-command tool routes a `--nested`
invocation to `ReflectionGeneratorExecutor.executeWithoutTraversal`, and a
traversal invocation to `execute` per project.

### Key types

| Type | Responsibility |
| ---- | -------------- |
| `ReflectionGenerator` | The `build_runner` `Builder`: maps `.dart` → `.reflection.dart`. |
| `reflectionGenerator(BuilderOptions)` | Builder factory referenced from `build.yaml`. |
| `reflectionGeneratorTool` | `tom_build_base` `ToolDefinition` (single-command) — the CLI surface and its options/help. |
| `ReflectionGeneratorExecutor` | `CommandExecutor` that runs the generation per target / nested invocation. |
| `StandaloneLibraryResolver` | Analyzer-backed resolver that loads libraries outside a build_runner context. |
| `FileId` | Package-relative file identity (`changeExtension`, etc.). |
| `GeneratorImplementation` | The generation core (`buildMirrorLibrary`). |

## Ecosystem

```
tom_reflection            runtime mirror library — defines the annotations & capabilities
      ▲ reads its annotations
tom_reflection_generator  THIS PACKAGE — emits *.reflection.dart
      │ builds on
      ├── tom_build_base        v2 tool framework (CLI, nesting, version flags)
      └── tom_analyzer_shared   analyzer summary cache (shared with tom_d4rt_generator)
      ▲ exercised end-to-end by
tom_reflection_test       fixture suite (input + committed expected output)
```

This is the engine-1 generator. The build-time *structural* engine
([`tom_reflector`](../tom_reflector/README.md)) is a separate technology with its
own generator emitting `*.r.dart` — see the repo [`README`](../README.md).

## Further documentation

- Usage guide: [`doc/reflection_generator.md`](doc/reflection_generator.md)
- CLI reference: [`doc/reflectiongenerator_user_reference.md`](doc/reflectiongenerator_user_reference.md)
- Implementation notes: [`doc/reflection_generator_implementation.md`](doc/reflection_generator_implementation.md)
- Analyzer summary caching: [`doc/analyzer_summary_integration.md`](doc/analyzer_summary_integration.md)
- Test status: [`doc/reflection_test_result.md`](doc/reflection_test_result.md)
- Runtime library it generates for: [`../tom_reflection/README.md`](../tom_reflection/README.md)
- Capability gating in action: [`reflection_capability_sample`](../tom_reflection_samples/reflection_capability_sample/README.md)

## Status

- **Version:** 1.1.1 (published to pub.dev).
- **SDK:** Dart `^3.10.4`; `analyzer ^8`.
- **Surfaces:** `build_runner` builder + `reflectiongenerator` CLI (standalone
  and `buildkit :reflectiongenerator`).
- **Verification:** output validated against the
  [`tom_reflection_test`](../tom_reflection_test/README.md) fixture suite, where
  CLI output matches the `build_runner`-generated reference.

## License

BSD-3-Clause. Derived from the
[`reflectable`](https://pub.dev/packages/reflectable) package by the Dart team
([`google/reflectable.dart`](https://github.com/google/reflectable.dart),
"Copyright (c) 2015, Dart") — retaining the upstream copyright alongside Tom's
modifications (© 2024–2026 Peter Nicolai Alexis Kyaw), released under the same
BSD-3-Clause terms. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
