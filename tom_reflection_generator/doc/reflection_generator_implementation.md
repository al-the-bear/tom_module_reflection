# Reflection Generator Implementation

Technical documentation for the Reflection Generator component in
`tom_reflection_generator`.

## Architecture

```text
tom_reflection_generator/lib/src/reflection_generator/
├── reflection_generator.dart     # Public exports
├── generator_implementation.dart # Core generation logic
├── library_resolver.dart         # Abstract resolver interface
├── standalone_resolver.dart      # CLI resolver implementation
├── build_runner_resolver.dart    # build_runner integration
├── capabilities.dart             # Capability handling
├── domain_classes.dart           # Domain model
├── reflection_world.dart         # Reflection world model
├── reflector_domain.dart         # Reflector processing
├── type_descriptors.dart         # Type description generation
├── encoding_constants.dart       # Output encoding
└── ... (additional implementation files)
```

## Classes

### GeneratorImplementation

The core class that performs reflection code generation.

```dart
class GeneratorImplementation {
  /// Package name of the reflection library.
  final String reflectionPackageName;
  
  /// If true, use all capabilities regardless of reflector.
  final bool useAllCapabilities;
  
  /// The library resolver for element analysis.
  final LibraryResolver resolver;
  
  /// Creates a generator implementation.
  GeneratorImplementation({
    required this.resolver,
    this.reflectionPackageName = 'tom_reflection',
    this.useAllCapabilities = false,
  });
  
  /// Generates reflection code for a library.
  Future<String> generateForLibrary(LibraryElement library);
  
  /// Generates reflection code for a file.
  Future<String> generateForFile(String filePath);
}
```

### LibraryResolver

Abstract interface for resolving library information.

```dart
abstract class LibraryResolver {
  /// Gets the FileId for a library element.
  Future<FileId?> fileIdForElement(LibraryElement library);
  
  /// Checks if a library can be imported from a file.
  Future<bool> isImportable(LibraryElement library, FileId fromFile);
  
  /// Gets all libraries in the project.
  Future<List<LibraryElement>> get libraries;
  
  /// Resolves a file path to a library element.
  Future<LibraryElement?> resolveFile(String filePath);
  
  /// Disposes resources.
  void dispose();
}

class FileId {
  final String package;
  final String path;
}
```

### StandaloneLibraryResolver

CLI implementation using the Dart analyzer.

```dart
class StandaloneLibraryResolver implements LibraryResolver {
  final AnalysisContextCollection _collection;
  final String _projectRoot;
  final String _packageName;
  
  /// Creates a resolver for the project at [projectRoot].
  static Future<StandaloneLibraryResolver> create(String projectRoot);
  
  @override
  Future<LibraryElement?> resolveFile(String filePath) async {
    final context = _collection.contextFor(filePath);
    final result = await context.currentSession.getResolvedUnit(filePath);
    if (result is ResolvedUnitResult) {
      return result.libraryElement;
    }
    return null;
  }
}
```

### BuildRunnerLibraryResolver

Integration with build_runner for incremental builds.

```dart
class BuildRunnerLibraryResolver implements LibraryResolver {
  final Resolver _resolver;
  final BuildStep _buildStep;
  
  /// Creates a resolver from build_runner context.
  BuildRunnerLibraryResolver(this._resolver, this._buildStep);
}
```

## Generation Process

### 1. Discover Reflectors

Find all classes annotated with `@Reflectable()`:

```dart
Future<List<ReflectorDomain>> _findReflectors(LibraryElement library) async {
  final reflectors = <ReflectorDomain>[];
  
  for (final unit in library.units) {
    for (final element in unit.classes) {
      final annotation = _findReflectableAnnotation(element);
      if (annotation != null) {
        reflectors.add(ReflectorDomain(element, annotation));
      }
    }
  }
  
  return reflectors;
}
```

### 2. Build Reflection World

Collect all types that need reflection:

```dart
class _ReflectionWorld {
  /// All classes that need mirrors.
  final Set<ClassElement> reflectedClasses;
  
  /// All libraries containing reflected elements.
  final Set<LibraryElement> reflectedLibraries;
  
  /// Capability requirements per class.
  final Map<ClassElement, Set<ec.ReflectCapability>> capabilities;
}
```

### 3. Generate Mirror Code

Generate `ClassMirrorImpl` for each reflected class:

```dart
String _generateClassMirror(ClassElement classElement) {
  final buffer = StringBuffer();
  
  buffer.writeln('class _\$${classElement.name}ClassMirror '
      'extends ClassMirrorBase {');
  
  // Generate declarations
  buffer.writeln('  @override');
  buffer.writeln('  List<DeclarationMirror> get declarations => [');
  // ... declarations
  buffer.writeln('  ];');
  
  // Generate instance invoker
  buffer.writeln('  @override');
  buffer.writeln('  InstanceMirror invoke(');
  // ... invocation logic
  buffer.writeln('  }');
  
  buffer.writeln('}');
  
  return buffer.toString();
}
```

### 4. Generate Type Descriptors

Create type descriptors for generic types:

```dart
String _generateTypeDescriptor(DartType type) {
  if (type is InterfaceType && type.typeArguments.isNotEmpty) {
    return '_GenericType<${type.element.name}, '
        '[${type.typeArguments.map(_generateTypeDescriptor).join(', ')}]>';
  }
  return type.element?.name ?? 'dynamic';
}
```

## Capabilities

Reflection capabilities control what metadata is generated:

```dart
enum ReflectCapability {
  invokingCapability,       // Method invocation
  declarationsCapability,   // Class declarations
  instanceMembersCapability, // Instance field access
  staticMembersCapability,   // Static members
  metadataCapability,        // Annotation metadata
  typeCapability,            // Type information
  typeRelationsCapability,   // Superclass/interface info
  reflectedTypeCapability,   // Runtime type access
  newInstanceCapability,     // Constructor invocation
}
```

### Capability Parsing

Capabilities are parsed from reflector annotations:

```dart
Set<ec.ReflectCapability> _parseCapabilities(DartObject annotation) {
  final capabilities = <ec.ReflectCapability>{};
  
  final capabilityList = annotation.getField('capabilities')?.toListValue();
  if (capabilityList != null) {
    for (final cap in capabilityList) {
      // Parse capability from DartObject
    }
  }
  
  return capabilities;
}
```

## Output Format

Generated files contain:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'original_file.dart';

// Mirror implementations
class _$MyClassClassMirror extends ClassMirrorBase { ... }

// Library mirror
class _$LibraryMirror extends LibraryMirrorBase { ... }

// Initializer
void _initializeReflection() {
  Reflector.registerLibrary(_$LibraryMirror());
}
```

## Encoding Constants

The `encoding_constants.dart` file defines constants for compact output:

```dart
class EncodingConstants {
  static const int classKind = 0;
  static const int methodKind = 1;
  static const int getterKind = 2;
  static const int setterKind = 3;
  static const int constructorKind = 4;
  // ...
}
```

## Error Handling

Generation errors are collected and reported:

```dart
class ReflectionError {
  final String message;
  final Element? element;
  final SourceSpan? span;
}
```

Warning kinds that can be suppressed:

| Warning | Description |
| --------- | ------------- |
| `badSuperclass` | Unsupported superclass |
| `badNamePattern` | Invalid member name pattern |
| `badMetadata` | Unparseable annotation |
| `badReflectorClass` | Invalid reflector setup |
| `unsupportedType` | Type that cannot be reflected |
| `unusedReflector` | Reflector with no targets |

## Performance Considerations

- **Lazy resolution**: Libraries are resolved on-demand
- **Caching**: Resolved libraries are cached in resolver
- **Incremental**: build_runner integration supports incremental builds
- **Parallel**: Multiple files can be processed in parallel

## Testing

Tests live under `tom_reflection_generator/test/` (for example,
`file_id_test.dart` validates `FileId` behavior):

| Test Group | Coverage |
| ------------ | ---------- |
| `StandaloneResolver` | File resolution, library listing |
| `Capability parsing` | All capability types |
| `Code generation` | Mirror output, type descriptors |
| `Error handling` | Invalid annotations, missing types |

## See Also

- [Reflection Generator Usage](reflection_generator.md)
- [Compare Mirrors Utility](../../tom_build_tools/doc/compare_mirrors.md)
- [Tom Reflection Package](../../tom_reflection/README.md)
