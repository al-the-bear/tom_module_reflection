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
