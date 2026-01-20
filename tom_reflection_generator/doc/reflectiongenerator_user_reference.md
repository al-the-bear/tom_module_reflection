# Reflection Generator User Reference

Quick reference for Tom reflection code generation.

---

## 1. Overview

The Reflection Generator creates `.reflection.dart` files for Dart files using `@reflection` annotations from `tom_reflection`. Provides runtime reflection without mirrors.

**Key Features:**
- Standalone CLI and build_runner integration
- Glob pattern support for batch processing
- Configurable via build.yaml
- Works with annotations on classes, methods, and properties

---

## 2. Command Line Usage

```bash
dart run tom_reflection_generator [command] [options] <targets...>
```

### Commands

| Command | Description |
|---------|-------------|
| `generate` | Process specific files/patterns (default) |
| `build` | Use build.yaml configuration |

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--all` | — | Process directories recursively |
| `--package` | `-p` | Reflection package name (default: `tom_reflection`) |
| `--extension` | `-e` | Output file extension (default: `.reflection.dart`) |
| `--config` | `-c` | Config file path for build mode (default: `build.yaml`) |
| `--useAllCapabilities` | — | Use all capabilities (full reflection) |
| `--verbose` | `-v` | Enable verbose output |
| `--help` | `-h` | Show usage help |

---

## 3. Generate Mode (Default)

Process specific files, directories, or glob patterns.

```bash
# Single file
dart run tom_reflection_generator lib/main.dart

# With explicit command
dart run tom_reflection_generator generate lib/models/user.dart

# Directory (requires --all)
dart run tom_reflection_generator --all lib/

# Glob patterns (quote to prevent shell expansion)
dart run tom_reflection_generator "lib/**/*.dart"

# Multiple patterns
dart run tom_reflection_generator "lib/**/*.dart" "test/**_test.dart"
```

### Glob Pattern Examples

| Pattern | Matches |
|---------|---------|
| `*.dart` | Dart files in current directory |
| `**/*.dart` | All Dart files recursively |
| `lib/**/*.dart` | All Dart files under lib/ |
| `lib/src/*_model.dart` | Files ending in `_model.dart` in lib/src |
| `{lib,test}/**/*.dart` | All Dart files in lib/ or test/ |

---

## 4. Build Mode

Use build.yaml configuration for consistent builds.

```bash
# Use default build.yaml
dart run tom_reflection_generator build

# Custom config file
dart run tom_reflection_generator build --config reflection.yaml

# Override with glob patterns
dart run tom_reflection_generator build "test/**_test.dart"

# Verbose build
dart run tom_reflection_generator build -v
```

---

## 5. build_runner Integration

### 5.1 Setup

Add to `pubspec.yaml`:

```yaml
dependencies:
  tom_reflection: ^1.0.0

dev_dependencies:
  build_runner: ^2.4.0
  tom_reflection_generator: ^1.0.0
```

### 5.2 Configuration (build.yaml)

Configure in your project's `build.yaml`:

```yaml
targets:
  $default:
    builders:
      tom_reflection_generator|reflection_generator:
        generate_for:
          - lib/**/*.dart
          - test/**_test.dart
        options:
          formatted: true
          extension: .reflection.dart
```

### 5.3 Running build_runner

```bash
# One-time build
dart run build_runner build

# Watch mode (rebuilds on changes)
dart run build_runner watch

# Clean and rebuild
dart run build_runner build --delete-conflicting-outputs
```

---

## 6. Configuration Reference

### 6.1 build.yaml Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `generate_for` | List\<String\> | **required** | Glob patterns for input files |
| `formatted` | bool | `true` | Format generated code |
| `extension` | String | `.reflection.dart` | Output file extension |

### 6.2 Standalone CLI Options

| Option | Default | Description |
|--------|---------|-------------|
| `--package` | `tom_reflection` | Reflection package name |
| `--extension` | `.reflection.dart` | Output file extension |
| `--useAllCapabilities` | `false` | Generate full reflection metadata |

---

## 7. Annotations

### 7.1 Basic Usage

```dart
import 'package:tom_reflection/tom_reflection.dart';

@TomComponent()
class MyClass {
  String name;
  int count;
  
  MyClass(this.name, this.count);
  
  void doSomething() { }
}
```

### 7.2 Common Annotations

| Annotation | Description |
|------------|-------------|
| `@TomComponent()` | Mark class for reflection |
| `@TomReflectable()` | Make class reflectable |
| `@TomIgnore()` | Exclude from reflection |

---

## 8. Generated Output

### 8.1 Output Location

Generated files are placed next to source files:

```
lib/
  models/
    user.dart           # Source
    user.reflection.dart  # Generated
```

### 8.2 Output Content

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// Reflection metadata for User class
class _$UserMirror extends ClassMirror {
  @override
  String get simpleName => 'User';
  
  @override
  List<DeclarationMirror> get declarations => [
    // ... property and method mirrors
  ];
}
```

---

## 9. Programmatic API

### 9.1 Basic Usage

```dart
import 'package:tom_reflection_generator/tom_reflection_generator.dart';

Future<void> main() async {
  final resolver = await StandaloneLibraryResolver.create('/path/to/project');
  
  try {
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

    print('Generated ${source.length} bytes');
  } finally {
    resolver.dispose();
  }
}
```

### 9.2 Using with tom_build

```dart
import 'package:tom_build/tom_build.dart';

final runner = ReflectionGeneratorRunner('/path/to/project');
final result = await runner.generate();

print('Generated: ${result.filesGenerated}');
print('Errors: ${result.errors}');
```

---

## 10. Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| No output generated | Ensure class has `@TomComponent()` annotation |
| Analyzer errors | Fix compilation errors in source first |
| Missing pubspec.yaml | Run from project root directory |
| Part directive missing | Add `part 'file.reflection.dart';` to source |

### Debug Mode

```bash
dart run tom_reflection_generator --all lib/ --verbose
```

### Clean Build

```bash
# Delete generated files
find lib -name "*.reflection.dart" -delete

# Regenerate
dart run tom_reflection_generator --all lib/
```

---

## 11. Best Practices

1. **Add part directives** - Source files need `part 'file.reflection.dart';`
2. **Version control** - Commit generated files for reproducibility
3. **Use build_runner** - For automatic regeneration on file changes
4. **Quote globs** - Prevent shell expansion: `"lib/**/*.dart"`
5. **Fix errors first** - Generator requires valid Dart source
