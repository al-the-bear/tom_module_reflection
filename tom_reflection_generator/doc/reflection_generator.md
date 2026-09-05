# Reflection Generator

Command-line tool for generating reflection code without build_runner.

## Overview

The Reflection Generator creates `.reflection.dart` files for Dart files that use the `@reflection` annotation from `tom_reflection`. It provides a standalone alternative to the build_runner-based reflection generation, with support for glob patterns, build.yaml configuration, and batch processing.

## Installation

Install the generator from the `tom_reflection_generator` package. Add it to
your workspace (or run it globally via `dart run tom_reflection_generator`).

## Usage

### Command Modes

The tool supports two primary modes:

1. **Generate mode** (default): Process specific files or patterns
2. **Build mode**: Use build.yaml configuration

### Generate Mode

```bash
# Process a single file
dart run tom_reflection_generator lib/main.dart

# Process with explicit generate command
dart run tom_reflection_generator generate lib/main.dart

# Process all Dart files in a directory (recursive)
dart run tom_reflection_generator --all lib/

# Process files matching a glob pattern
dart run tom_reflection_generator "lib/**/*.dart"
```

### Build Mode

```bash
# Use build.yaml configuration
dart run tom_reflection_generator build

# Use a custom config file
dart run tom_reflection_generator build --config custom.yaml
```

### Command Line Options

| Option | Description |
| ------ | ----------- |
| `<files/patterns>` | Files, directories, or glob patterns to process |
| `--all` | Process directories recursively |
| `--help`, `-h` | Show help message |
| `-p`, `--package=NAME` | Reflection package name (default: tom_reflection) |
| `-e`, `--extension=EXT` | Output extension (default: .reflection.dart) |
| `-c`, `--config=FILE` | Config file for build mode (default: build.yaml) |
| `--verbose`, `-v` | Enable verbose output |
| `--useAllCapabilities` | Use all capabilities instead of reflector-specified |
| `--check` | Verify committed output instead of writing it (see [Check Mode](#check-mode)) |

### Examples

```bash
# Generate for a single file
dart run tom_reflection_generator lib/models/user.dart

# Generate for all files in lib
dart run tom_reflection_generator --all lib/

# Generate with custom output extension
dart run tom_reflection_generator lib/models/*.dart -e .ref.dart

# Generate using glob pattern
dart run tom_reflection_generator "lib/src/**/*_model.dart"

# Build mode with custom config
dart run tom_reflection_generator build --config reflection.yaml

# Verbose output
dart run tom_reflection_generator --all lib/ --verbose
```

## Check Mode

`--check` answers one question: **does the committed `*.reflection.dart` still
match what the generator would emit for its source?**

```bash
# Verify this project's committed output
dart run tom_reflection_generator --check

# Or through the project's own script
./reflection_generation.sh --check
```

Everything up to the final write is an ordinary run — same resolver, same
capabilities, same generated string. Only the last step differs: the string is
compared with the file on disk instead of replacing it. The run exits non-zero
and names every file that differs or is missing, and **modifies nothing**.

### Why it exists

A generated file that has fallen behind its source is invisible to every other
signal. When a reflected parameter was widened from `String?` to `Object?` in
two packages, the generated seeds kept the old type indices and were committed
stale. Measured at the time: `dart analyze` was clean and both suites were fully
green, with identical test counts before and after regeneration. The stale part
is metadata the tests never read.

So "remember to regenerate after changing a reflected signature" was the only
thing preventing a committed mismatch — and a habit is not a control. This is
the control.

### Cost

A check is a full generation run (roughly 20–30 s per package, dominated by
analysis), because comparing against what the generator *would* emit means
actually running it. That cost is the reason this is a deliberate step rather
than something on every save.

### Reading a failure

```text
  STALE (differs): lib/src/reflection_entry.reflection.dart
Reflection check FAILED after 21.0s — 1 generated file(s) no longer match
their source, 0 up to date, 0 skipped.
```

The remedy is always the same: run the generator normally and commit the
result. A missing output is reported as stale too — a source that should have a
generated counterpart and has none is the same drift with the same fix.

Comparison is exact, so a formatting difference is reported as drift. That is
deliberate: normalising first would mean guessing which differences are benign,
and a wrong guess hides exactly what this exists to catch. Regenerating settles
it permanently.

## Diagnostics

A run that writes a file has not necessarily written a *complete* one. When the
generator meets a construct it cannot render — a private constructor it may not
call, a record type in a reflected type argument — it leaves that piece out and
reports a **SEVERE** diagnostic. The file still compiles; it simply describes
less than the source does.

Those diagnostics are printed to stderr as they happen, and the closing line
counts them:

```text
  SEVERE: [constant.constructor.private] Cannot access private constructor ...
Reflection generation succeeded after 5m 29s — 1 generated, 0 skipped,
226 SEVERE diagnostic(s) in 4 distinct case(s) — the generated mirror is
incomplete.
```

Each distinct message is printed once, however many elements provoke it: one
unsupported construct used across a widget library accounts for hundreds of
records, and printing them all would bury the rest.

A severe does **not** fail the run. It is a statement about coverage, not about
correctness of what was emitted, and a project may legitimately reflect over
code with constructs the generator does not support. What it must never be is
invisible: for a long while nothing subscribed to the generator's logger at all,
so a run could silently drop a constructor's default value — together with the
imports that existed only to render it — and still report success. That is how
`tom_flutter_form_test`'s committed mirror came to differ from its own
regeneration by 143k lines with no explanation on record.

### Reproducibility

Generation is a function of the sources. In particular it does not depend on
whether a given dependency happened to be served from the analyzer summary cache
on this run: where a construct is reachable both from a library's source AST and
from the element's own serialized data, the generator reads whichever is
available and emits the same text either way. `--rebuild-cache` and a warm cache
produce byte-identical output, which is what makes `--check` a meaningful gate
rather than a report on cache state.

## Glob Patterns

The generator supports standard glob patterns:

| Pattern | Description |
| ------- | ----------- |
| `*.dart` | All Dart files in current directory |
| `**/*.dart` | All Dart files recursively |
| `lib/**/*.dart` | All Dart files under lib |
| `lib/src/*_model.dart` | Files ending in _model.dart in lib/src |
| `{lib,test}/**/*.dart` | All Dart files in lib or test |

## build.yaml Configuration

For build mode, configure reflection generation in `build.yaml`:

```yaml
targets:
  $default:
    builders:
      tom_reflection_generator|reflection_generator:
        enabled: true
        generate_for:
          - lib/**/*.dart
        options:
          entry_points:
            - lib/main.dart
          capabilities:
            - invokingCapability
            - declarationsCapability
```

### Configuration Options

| Option | Type | Description |
| ------ | ---- | ----------- |
| `entry_points` | List | Entry point files for analysis |
| `capabilities` | List | Reflection capabilities to include |
| `exclude` | List | Patterns to exclude |
| `extension` | String | Output file extension |

## File Processing

### What Files Are Processed

The generator processes Dart files that:

1. End with `.dart`
2. Contain `@Reflectable()` or similar annotations
3. Import from `tom_reflection`

### What Files Are Excluded

- `*.reflection.dart` (generated files)
- `*.g.dart` (build_runner generated files)
- Files in excluded directories:
  - `.dart_tool/`
  - `build/`
  - `.git/`

### Generated Output

For each source file `lib/models/user.dart`, the generator creates:

```text
lib/models/user.reflection.dart
```

The generated file contains:

- Mirror class implementations
- Reflection metadata
- Type descriptors
- Capability implementations

## Capabilities

Reflection capabilities control what metadata is generated:

| Capability | Description |
| ---------- | ----------- |
| `invokingCapability` | Method invocation |
| `declarationsCapability` | Class/member declarations |
| `instanceMembersCapability` | Instance field access |
| `staticMembersCapability` | Static member access |
| `metadataCapability` | Annotation metadata |
| `typeCapability` | Type information |

Use `--useAllCapabilities` to include all capabilities regardless of reflector specification.

## Programmatic Usage

```dart
import 'package:tom_reflection_generator/tom_reflection_generator.dart';

Future<void> main() async {
  final resolver = await StandaloneLibraryResolver.create('/path/to/project');

  try {
    final implementation = GeneratorImplementation();
    final code = await implementation.buildMirrorLibrary(
      resolver,
      FileId('my_package', 'lib/models/user.dart'),
      FileId('my_package', 'lib/models/user.reflection.dart'),
      await resolver.libraryFor(
        FileId('my_package', 'lib/models/user.dart'),
      ),
      await resolver.libraries,
      true,
      const [],
    );

    await File('/path/to/project/lib/models/user.reflection.dart')
        .writeAsString(code);
  } finally {
    resolver.dispose();
  }
}
```

## Comparison with build_runner

| Feature | Standalone Generator | build_runner |
| ------- | -------------------- | ------------ |
| Setup | No setup required | Requires build.yaml |
| Speed | Fast (single file) | Slower (full build) |
| Watch mode | Not supported | Supported |
| Incremental | Manual | Automatic |
| CI/CD | Easy integration | Requires setup |
| Dependencies | Fewer | More |

Use the **standalone generator** for:

- CI/CD pipelines
- Quick regeneration
- Projects without build_runner
- Custom build workflows

Use **build_runner** for:

- Development watch mode
- Multi-builder setups
- Automatic incremental builds

## Troubleshooting

### "Could not find project root"

Ensure you're running from within a Dart project with a `pubspec.yaml`:

```bash
cd /path/to/project
dart run tom_reflection_generator lib/main.dart
```

### "No annotated elements found"

Ensure your files contain `@Reflectable()` annotations:

```dart
import 'package:tom_reflection/tom_reflection.dart';

@Reflectable()
class MyClass {
  String name;
}
```

### "Import not resolved"

Run `dart pub get` before generating reflection code.

## See Also

- [Reflection Generator Implementation](reflection_generator_implementation.md)
- [Tom Reflection Package](../../tom_reflection/README.md)
- [Compare Mirrors Utility](../tom_build_tools/doc/compare_mirrors.md)
