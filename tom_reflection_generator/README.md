# Tom Reflection Generator

`tom_reflection_generator` bundles the Tom reflection builder, a
`build_runner` integration, and the standalone CLI that was previously part of
`tom_build_tools`. The package can be published to pub.dev and consumed by any
Dart or Flutter workspace that needs to generate `.reflection.dart` files for
projects using `tom_reflection`.

## Features

- `builder`: `ReflectionGenerator` with build.yaml wiring for build_runner
- `CLI`: `dart run tom_reflection_generator [...]` for one-off or CI builds
- Shared analyzer infrastructure (`StandaloneLibraryResolver`, `FileId`, etc.)
- Matches the behavior of the original tooling from `tom_build`/`tom_build_tools`

## Installing

Add the dependency:

```yaml
dependencies:
  tom_reflection_generator: ^1.0.0
```

### build_runner configuration

```yaml
targets:
  $default:
    builders:
      tom_reflection_generator|reflection_generator:
        generate_for:
          - lib/**/*.dart
```

### Standalone CLI

```bash
# Generate for a single entry point
dart run tom_reflection_generator lib/main.dart

# Generate recursively (use --all to treat directories as recursive)
dart run tom_reflection_generator --all lib/

# Use build mode with build.yaml
dart run tom_reflection_generator build

# Provide explicit glob patterns
dart run tom_reflection_generator build "lib/**/*.dart" "test/**_test.dart"
```

Key CLI flags:

| Flag | Description |
| --- | --- |
| `--all` | Recursively process a directory |
| `--package`, `-p` | Override reflection package name (default `tom_reflection`) |
| `--extension`, `-e` | Change the generated file extension (default `.reflection.dart`) |
| `--config`, `-c` | Custom config when running in `build` mode |
| `--useAllCapabilities` | Ignore reflector capabilities and emit full metadata |
| `--verbose`, `-v` | Verbose logging |

## Programmatic usage

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
    true,
    const [],
  );

  // Write the generated source somewhere meaningful.
}
```

## Documentation

- [Reflection Generator Usage](doc/reflection_generator.md)
- [Reflection Generator Implementation](doc/reflection_generator_implementation.md)
- [Tom Reflection Test Status](doc/reflection_test_result.md)

## License

BSD-style license, consistent with the rest of the Tom workspace.
