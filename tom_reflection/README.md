# tom_reflection

> Part of the Tom Framework reflection toolkit. **Derived from the
> [`reflectable`](https://pub.dev/packages/reflectable) package by the Dart team**
> ([`google/reflectable.dart`](https://github.com/google/reflectable.dart),
> "Copyright (c) 2015, Dart", BSD-3-Clause); Tom-specific refactoring, fixes and
> enhancements © 2024–2026 Peter Nicolai Alexis Kyaw, released under the same
> BSD-3-Clause terms. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

Runtime reflection for Dart based on code generation, using *capabilities* to
declare exactly which reflective operations to support — so the generated code
stays small.

`tom_reflection` is **engine 1** of the Tom reflection toolkit: it gives you
**mirrors on live objects** at runtime. You can invoke a method by name, read or
write a field by name, construct an instance, walk a class hierarchy, and read
metadata — all without knowing the type at compile time. For the build-time
*structural* model (a serializable graph of code shape for tooling), see the
sibling engine [`tom_reflector`](../tom_reflector/README.md).

## Overview

Dart's built-in `dart:mirrors` is unavailable in AOT/Flutter and bloats output
because the compiler cannot know which members you will reflect on. This package
solves that with **generated, capability-gated reflection**:

1. You declare a **reflector** — a `const` subclass of `Reflection` whose
   constructor lists the *capabilities* you need (invoke methods? read
   declarations? walk type relations?).
2. You **annotate** target classes with that reflector (`@myReflector`).
3. A **generator** ([`tom_reflection_generator`](../tom_reflection_generator/README.md))
   reads those annotations and emits a `*.reflection.dart` file holding the
   precomputed mirror data — only for the capabilities you asked for.
4. At startup you call the generated `initializeReflection()`, then use
   `myReflector.reflect(obj)` to get an `InstanceMirror` and drive it.

Because capabilities gate what the generator emits, a reflector that only needs
`invokingCapability` produces far less code than one asking for everything. This
is the core idea inherited from `reflectable`: pay only for the reflection you
use.

```
   annotate            generate                 run
@myReflector  ─────►  *.reflection.dart  ─────►  myReflector.reflect(obj)
   class Foo          (capability-gated)          .invoke('bar', [...])
```

## Installation

```yaml
dependencies:
  tom_reflection: ^1.0.2

dev_dependencies:
  build_runner: ^2.4.0
  tom_reflection_generator: ^1.1.1
```

Or:

```bash
dart pub add tom_reflection
dart pub add --dev build_runner tom_reflection_generator
```

**SDK:** Dart `^3.9.0`. The generator is a dev-only dependency — your shipped
package depends on `tom_reflection` alone.

Configure which files to generate reflection for via `build.yaml`:

```yaml
targets:
  $default:
    builders:
      tom_reflection_generator:
        generate_for:
          - lib/**.dart
          - example/**.dart
```

## Features

### Reflective operations

| Operation | Mirror API | Capability required |
| --------- | ---------- | ------------------- |
| Invoke a method by name | `InstanceMirror.invoke('m', [...])` | `invokingCapability` / `instanceInvokeCapability` |
| Read a field/getter | `InstanceMirror.invokeGetter('f')` | `invokingCapability` |
| Write a field/setter | `InstanceMirror.invokeSetter('f', v)` | `invokingCapability` |
| Construct an instance | `ClassMirror.newInstance('', [...])` | `newInstanceCapability` |
| Call a static method | `ClassMirror.invoke('m', [...])` | `staticInvokeCapability` |
| Enumerate declarations | `ClassMirror.declarations` | `declarationsCapability` |
| Class of an instance | `InstanceMirror.type` | `typeCapability` |
| Superclass / interfaces | `ClassMirror.superclass`, `.superinterfaces` | `typeRelationsCapability` |
| Read metadata | `DeclarationMirror.metadata` | `metadataCapability` |
| `reflectedType` on mirrors | `TypeMirror.reflectedType` | `reflectedTypeCapability` |
| Library mirrors | `reflector.findLibrary(...)` | `libraryCapability` |

### Capabilities

Capabilities are passed to your reflector's `super(...)` constructor (up to ten
positional, or `Reflection.fromList([...])` for more).

| Capability | What it enables |
| ---------- | --------------- |
| `invokingCapability` | Instance + static method/constructor invocation (the common all-rounder) |
| `instanceInvokeCapability` | Instance method / getter / setter invocation only |
| `staticInvokeCapability` | Static method invocation |
| `topLevelInvokeCapability` | Top-level function invocation |
| `newInstanceCapability` | Construct instances via `newInstance` |
| `declarationsCapability` | Enumerate fields, methods, constructors |
| `typeCapability` | Obtain class/type mirrors (`instance.type`) |
| `typeRelationsCapability` | Superclass, interfaces, type arguments |
| `metadataCapability` | Read annotation metadata |
| `reflectedTypeCapability` | `reflectedType` on type mirrors |
| `libraryCapability` | Library mirrors |
| `uriCapability` | Library URIs |
| `libraryDependenciesCapability` | Import/export dependency mirrors |
| `typingCapability` | Full type-information support |

**Pattern capabilities** restrict to members matching a regular expression, so
the generator emits even less:

```dart
class GettersOnly extends Reflection {
  const GettersOnly() : super(const InstanceInvokeCapability('^get'));
}
```

**Metadata-quantified capabilities** (`InstanceInvokeMetaCapability(Annotation)`)
restrict to members carrying a given annotation. **Quantifier capabilities**
(`superclassQuantifyCapability`, `subtypeQuantifyCapability`,
`typeAnnotationQuantifyCapability`, `admitSubtypeCapability`) widen the reflected
*set of classes* beyond the directly-annotated ones.

## Quick start

```dart
import 'package:tom_reflection/tom_reflection.dart';
import 'quick_start.reflection.dart'; // generated

class MyReflector extends Reflection {
  const MyReflector() : super(invokingCapability, declarationsCapability);
}
const myReflector = MyReflector();

@myReflector
class Person {
  String name;
  Person(this.name);
  String greet() => 'Hello, I am $name!';
}

void main() {
  initializeReflection(); // generated; call once before reflecting

  final mirror = myReflector.reflect(Person('Alice'));
  print(mirror.invoke('greet', []));   // Hello, I am Alice!
  print(mirror.invokeGetter('name'));  // Alice
  mirror.invokeSetter('name', 'Bob');
  print(mirror.invoke('greet', []));   // Hello, I am Bob!
}
```

Generate the `quick_start.reflection.dart` first:

```bash
dart run build_runner build           # build_runner
# or:
reflectiongenerator lib/quick_start.dart   # standalone CLI
# or:
buildkit :reflectiongenerator         # nested under buildkit
```

## Example projects

| Sample | Demonstrates |
| ------ | ------------ |
| [`example/tom_reflection_example.dart`](example/tom_reflection_example.dart) | Thirteen scenarios: invoke, getters/setters, declarations, subclass reflection, type reflection, `isSubtype<S>()`, `isInstanceOf`, typed-collection creation, superclass-chain walking. |
| [`reflection_introduction_sample`](../tom_reflection_samples/reflection_introduction_sample/README.md) | Guided beginner tutorial — annotate → generate → reflect → invoke. |
| [`reflection_advanced_sample`](../tom_reflection_samples/reflection_advanced_sample/README.md) | Declarations, `newInstance`, static members, type relations, generics & mixins. |
| [`reflection_capability_sample`](../tom_reflection_samples/reflection_capability_sample/README.md) | How each capability gates generated code; minimal vs all capabilities. |

## Usage

### Define a reflector and annotate

```dart
class MyReflector extends Reflection {
  const MyReflector()
      : super(
          invokingCapability,
          declarationsCapability,
          typeRelationsCapability,
          metadataCapability,
        );
}
const myReflector = MyReflector();

@myReflector
class Employee {
  String name;
  String department;
  Employee(this.name, this.department);
  String jobInfo() => '$name works in $department';
}
```

The reflector class must have a **zero-argument `const` constructor** (so it is a
singleton the generator can encode). Use it as `@MyReflector()` or as a top-level
`const myReflector` identifier (`@myReflector`).

### Invoke methods, getters and setters

```dart
final m = myReflector.reflect(Employee('Bob', 'Engineering'));

m.invoke('jobInfo', []);          // 'Bob works in Engineering'
m.invokeGetter('department');     // 'Engineering'
m.invokeSetter('department', 'Sales');
m.invokeGetter('department');     // 'Sales'
```

`invoke` also takes named arguments: `m.invoke('f', [pos], {#named: v})`.

### Enumerate declarations

With `declarationsCapability`, walk the members of a class:

```dart
final cls = m.type; // ClassMirror, requires typeCapability
for (final entry in cls.declarations.entries) {
  final kind = switch (entry.value) {
    MethodMirror mm when mm.isGetter => 'getter',
    MethodMirror mm when mm.isConstructor => 'constructor',
    MethodMirror() => 'method',
    VariableMirror() => 'field',
    _ => 'other',
  };
  print('${entry.key} ($kind)');
}
// name (field)
// department (field)
// jobInfo (method)
// ...
```

### Construct instances

With `newInstanceCapability`, build objects reflectively:

```dart
final cls = myReflector.reflectType(Employee) as ClassMirror;
final e = cls.newInstance('', ['Carol', 'Product']); // unnamed constructor
print((e as Employee).jobInfo()); // Carol works in Product
```

### Type relations

With `typeRelationsCapability`, walk the hierarchy:

```dart
final cls = m.type;
print(cls.simpleName);                       // Employee
print(cls.superclass?.simpleName ?? 'none'); // Person (or 'none' at an unmarked base)
```

`ClassMirror` also offers convenience checks that need no extra capability:

```dart
final personType   = myReflector.reflectType(Person)   as ClassMirror;
final employeeType = myReflector.reflectType(Employee) as ClassMirror;

personType.isSubtype<Employee>();      // true  — Employee is-a Person
employeeType.isSubtype<Person>();      // false
personType.isInstanceOf(Employee(...)); // true
```

### Metadata

With `metadataCapability`, read annotations off declarations:

```dart
for (final entry in cls.declarations.entries) {
  final meta = entry.value.metadata; // List<Object>
  if (meta.isNotEmpty) print('${entry.key}: $meta');
}
```

### Typed collections

`ClassMirror` can build correctly-typed collections of its reflectee type:

```dart
final list = personType.createList();              // List<Person>
final set  = personType.createSet();               // Set<Person>
final map  = personType.createValuedMap<String>(); // Map<String, Person>
```

### Reflect a type, and list covered classes

```dart
final tm = myReflector.reflectType(Person);
print(tm.simpleName);              // Person
print(tm.isOriginalDeclaration);   // true

for (final c in myReflector.annotatedClasses) {
  print(c.simpleName);             // every class covered by this reflector
}
```

## Architecture

```
package:tom_reflection/tom_reflection.dart   (public API)
├── Reflection / ReflectionInterface         the reflector base + contract
├── capability.dart  ─────────────────────►  ReflectCapability hierarchy
└── mirrors.dart     ─────────────────────►  Mirror hierarchy (interfaces)

generated *.reflection.dart  (per target file, by tom_reflection_generator)
├── ReflectorData          precomputed member/type tables
└── initializeReflection()  installs the data into the runtime
```

The public library re-exports `capability.dart` and `mirrors.dart`. Generated
files import the internal `generated.dart` barrel (mirror implementation classes,
`ReflectorData`) — never import that directly from app code.

### Key types

| Type | Responsibility |
| ---- | -------------- |
| `Reflection` | Abstract base for your reflector; its `const` constructor takes the capabilities. Used as the annotation. |
| `ReflectionInterface` | The reflector contract: `reflect`, `reflectType`, `findLibrary`, `annotatedClasses`, `canReflect`. |
| `InstanceMirror` | Mirror on a live object: `invoke`, `invokeGetter`, `invokeSetter`, `type`. |
| `ClassMirror<T>` | Mirror on a class: `newInstance`, `declarations`, `superclass`, `superinterfaces`, `isSubtype<S>`, `isInstanceOf`, collection factories. |
| `TypeMirror<T>` | Mirror on a type: `simpleName`, `qualifiedName`, `isOriginalDeclaration`, `reflectedType`. |
| `MethodMirror` | A method/getter/setter/constructor declaration (`isGetter`, `isSetter`, `isConstructor`, `parameters`). |
| `VariableMirror` | A field declaration (`type`, `isFinal`, `isStatic`). |
| `ParameterMirror` | A parameter (`isNamed`, `isOptional`, `hasDefaultValue`). |
| `LibraryMirror` | A library declaration and its members. |
| `ReflectCapability` | Base of the capability hierarchy gating what the generator emits. |

## Ecosystem

```
tom_reflection            (this package — runtime mirror library)
      ▲
      │ dev-dependency (generation only)
tom_reflection_generator  (emits *.reflection.dart: builder + `reflectiongenerator` CLI)
      ▲
      │ exercised end-to-end by
tom_reflection_test       (fixture suite)
```

`tom_reflection` is the only runtime dependency your code needs. The generator
and test suite are development-time companions. The build-time *structural*
engine ([`tom_reflector`](../tom_reflector/README.md)) is a separate technology —
see the repo [`README`](../README.md) for when to use which.

## Further documentation

- Generator usage (builder + CLI): [`tom_reflection_generator/doc/reflection_generator.md`](../tom_reflection_generator/doc/reflection_generator.md)
- Generator CLI reference: [`tom_reflection_generator/doc/reflectiongenerator_user_reference.md`](../tom_reflection_generator/doc/reflectiongenerator_user_reference.md)
- Repo map and engine selection: [`../README.md`](../README.md)
- Upstream design rationale (capabilities): the
  [`reflectable`](https://pub.dev/packages/reflectable) documentation, which this
  package's capability model follows.

## Status

- **Version:** 1.0.2 (published to pub.dev).
- **SDK:** Dart `^3.9.0`.
- **Tests:** exercised end-to-end by **72 fixture suites** in
  [`tom_reflection_test`](../tom_reflection_test/README.md) (basic invocation,
  capabilities, declarations, `newInstance`, static members, metadata, type
  relations, `reflectType`, enums, generic mixins, and more).

## License

BSD-3-Clause. This package is derived from the
[`reflectable`](https://pub.dev/packages/reflectable) package by the Dart team
([`google/reflectable.dart`](https://github.com/google/reflectable.dart),
"Copyright (c) 2015, Dart") and **retains the upstream copyright** alongside
Tom's modifications (© 2024–2026 Peter Nicolai Alexis Kyaw), released under the
same BSD-3-Clause terms. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
