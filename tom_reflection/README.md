# Tom Reflection

Runtime reflection support for Dart based on code generation, using *capabilities*
to specify which operations to support.

This package is a fork of the [reflectable](https://pub.dev/packages/reflectable)
package with modifications to better suit the Tom framework's needs and bug fixes.

## Features

- **Introspection**: Examine object structure at runtime (class members, types, metadata)
- **Dynamic invocation**: Call methods and access properties by name
- **Capability-based**: Only include the reflection support you need, minimizing code size
- **Code generation**: Generates efficient reflection data at build time

## Getting Started

### Prerequisites

- Dart SDK ^3.9.0
- `tom_build_tools` package for code generation

### Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  tom_reflection: ^1.0.0

dev_dependencies:
  build_runner: ^2.4.0
  tom_build:
    path: ../tom_build  # or git/pub reference
  tom_build_tools:
    path: ../tom_build_tools  # or git/pub reference
```

Add a `build.yaml` to configure which files to generate reflection for:

```yaml
targets:
  $default:
    builders:
      tom_build:reflection_generator:
        generate_for:
          - lib/main.dart
          - example/*.dart
        options:
          formatted: true
```

## Usage

### 1. Define a Reflector

Create a class extending `Reflection` with the capabilities you need:

```dart
import 'package:tom_reflection/tom_reflection.dart';

class MyReflector extends Reflection {
  const MyReflector()
      : super(
          invokingCapability,
          declarationsCapability,
        );
}

const myReflector = MyReflector();
```

### 2. Annotate Classes

Mark classes for reflection with your reflector:

```dart
@myReflector
class Person {
  final String name;
  final int age;

  Person(this.name, this.age);

  String greet() => 'Hello, I am $name!';
}
```

### 3. Generate Reflection Data

Run build_runner to generate the reflection code:

```bash
dart run build_runner build
```

Or use the standalone generator directly:

```bash
dart run tom_build_tools:reflection_generator lib/main.dart
```

### 4. Use Reflection

```dart
import 'main.reflection.dart';

void main() {
  initializeReflection();

  final person = Person('Alice', 30);
  final mirror = myReflector.reflect(person);

  // Get member names
  final classMirror = mirror.type;
  print('Class: ${classMirror.simpleName}');

  // Invoke method dynamically
  final greeting = mirror.invoke('greet', []);
  print(greeting); // Hello, I am Alice!
}
```

## Capabilities

Capabilities control what reflection operations are available:

| Capability | Description |
| ---------- | ----------- |
| `invokingCapability` | Invoke methods and constructors |
| `declarationsCapability` | Access class declarations |
| `typeRelationsCapability` | Access superclass/interface info |
| `metadataCapability` | Access metadata annotations |
| `reflectedTypeCapability` | Access `reflectedType` on mirrors |

## License

BSD 3-Clause License. See [LICENSE](LICENSE) for details.

This package is a fork of [reflectable](https://pub.dev/packages/reflectable)
and maintains the same open-source license.

## Additional Information

- Part of the [Tom Framework](https://github.com/al-the-bear/tom)
- Based on [reflectable](https://pub.dev/packages/reflectable)
- See [example/](example/) for complete examples
