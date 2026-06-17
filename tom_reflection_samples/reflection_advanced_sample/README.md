# Reflection Advanced Sample

> Part of the Tom Framework reflection toolkit. **Derived from the
> [`reflectable`](https://pub.dev/packages/reflectable) package by the Dart team**
> ([`google/reflectable.dart`](https://github.com/google/reflectable.dart),
> "Copyright (c) 2015, Dart", BSD-3-Clause); Tom-specific refactoring, fixes and
> enhancements © 2024–2026 Peter Nicolai Alexis Kyaw, released under the same
> BSD-3-Clause terms. See
> [`LICENSE`](../../tom_reflection/LICENSE).

The second stop for **engine 1** of the Tom reflection toolkit —
[`tom_reflection`](../../tom_reflection/README.md), runtime reflection driven by
code generation. The [introduction
sample](../reflection_introduction_sample/README.md) covered the core loop:
annotate, generate, reflect, invoke. This sample goes deeper into the mirror API
and ends with the thing reflection actually earns its keep for — a **tiny,
type-agnostic serializer** built once against the mirror API and reused across
classes.

You will:

- **construct objects by name** with `newInstance` (no `new` in sight),
- **invoke static members** through the class mirror,
- **walk type relations** — the superclass chain and annotated superinterfaces,
- **reflect over generics and mixins**, including reflected return types, and
- tie `declarations` enumeration, `invokeGetter` and `invokeSetter` together into
  a working `toMap` / `fromMap` round-trip.

If you have not read the introduction sample, read it first — this one assumes
the annotate → generate → reflect cycle and the capability model.

---

## Table of contents

1. [What you'll build](#1-what-youll-build)
2. [Project layout](#2-project-layout)
3. [Running it](#3-running-it)
4. [The domain — one reflector, four slices](#4-the-domain--one-reflector-four-slices)
5. [Capabilities — the advanced set](#5-capabilities--the-advanced-set)
6. [Scenario 1 — a reflection-driven serializer](#6-scenario-1--a-reflection-driven-serializer)
7. [Scenario 2 — static members](#7-scenario-2--static-members)
8. [Scenario 3 — type relations](#8-scenario-3--type-relations)
9. [Scenario 4 — generics and mixins](#9-scenario-4--generics-and-mixins)
10. [The aggregator](#10-the-aggregator)
11. [Two gotchas the sample bakes in](#11-two-gotchas-the-sample-bakes-in)
12. [Regenerating after a change](#12-regenerating-after-a-change)
13. [Common errors and what they mean](#13-common-errors-and-what-they-mean)
14. [Where to go next](#14-where-to-go-next)

---

## 1. What you'll build

A small domain split into four themed groups, each exercised by one runnable
scenario:

| Scenario | Demonstrates | Key calls |
| -------- | ------------ | --------- |
| `serializer` | A type-agnostic `toMap` / `fromMap` round-trip | `declarations`, `invokeGetter`, `newInstance`, `invokeSetter` |
| `static_members` | Call static factories through the class mirror | `staticMembers`, `ClassMirror.invoke` |
| `type_relations` | Walk the superclass chain and superinterfaces | `.superclass`, `.superinterfaces` |
| `generics_and_mixins` | Reflect over mixed-in generic members | `instanceMembers`, `reflectedReturnType` |

Everything is wired into one aggregator, `bin/run_example.dart`, which runs all
four scenarios and reports a pass/fail tally.

The serializer is the headline: it is *the* canonical use case for runtime
mirrors. Write the (de)serialization logic once, against the mirror API, and it
works for any annotated class — no hand-written `toMap`/`fromMap` per type.

---

## 2. Project layout

```
reflection_advanced_sample/
  pubspec.yaml                 depends on tom_reflection (runtime) +
                               tom_reflection_generator (dev, generates code)
  build.yaml                   tells build_runner to generate for example/**/main.dart
  reflection_generation.sh     one-liner to regenerate the mirror data
  analysis_options.yaml        package:lints/recommended.yaml
  lib/
    domain.dart                the reflector + all annotated classes
  example/
    serializer/
      main.dart                scenario 1 entry point
      main.reflection.dart     GENERATED mirror data (committed)
    static_members/
      main.dart                scenario 2 entry point
      main.reflection.dart     GENERATED
    type_relations/
      main.dart                scenario 3 entry point
      main.reflection.dart     GENERATED
    generics_and_mixins/
      main.dart                scenario 4 entry point
      main.reflection.dart     GENERATED
  bin/
    run_example.dart           aggregator: runs every scenario, tallies pass/fail
```

The same two structural facts from the introduction sample hold here:

- **The annotated classes live in `lib/domain.dart`, but the generated files live
  next to each scenario `main.dart`** — the generator is *entry-point driven*, so
  it emits mirror data per entry point by walking its import graph.
- **The `*.reflection.dart` files are committed** so the sample runs with a plain
  `dart run`. They are build outputs — never hand-edit them; regenerate (see
  [§12](#12-regenerating-after-a-change)).

---

## 3. Running it

From this directory:

```bash
dart pub get

# Run all four scenarios with a pass/fail tally:
dart run bin/run_example.dart

# …or run a single scenario directly:
dart run example/serializer/main.dart
dart run example/static_members/main.dart
dart run example/type_relations/main.dart
dart run example/generics_and_mixins/main.dart
```

The aggregator prints each scenario under a banner and finishes with:

```text
----------------------------------------
Scenarios: 4  passed: 4  failed: 0
```

and exits `0`. If any scenario throws, it prints `FAILED: <name>: <error>` and
exits `1` — usable as a smoke test in CI.

---

## 4. The domain — one reflector, four slices

[`lib/domain.dart`](lib/domain.dart) declares a single broad reflector and four
groups of classes, one per scenario. Using one reflector keeps the generated data
coherent: every annotation refers to the same reflector, so the generator emits
one consistent table covering all the classes.

```dart
class AdvancedReflector extends Reflection {
  const AdvancedReflector()
      : super(
          invokingCapability,
          declarationsCapability,
          typeRelationsCapability,
          superclassQuantifyCapability,
          newInstanceCapability,
          metadataCapability,
          reflectedTypeCapability,
        );
}

const advancedReflector = AdvancedReflector();
```

The four slices:

**Serialization** — `Product` has *mutable, non-final* fields and an all-optional
constructor, which is exactly what `newInstance('', [])` + `invokeSetter` needs to
reconstruct an instance from data:

```dart
@advancedReflector
class Product {
  String sku;
  String name;
  double price;
  int stock;

  Product({this.sku = '', this.name = '', this.price = 0.0, this.stock = 0});

  String get label => '$name ($sku)'; // derived — deliberately NOT serialized
}
```

**Type relations** — `Circle extends Shape implements Drawable`, so its superclass
chain and its (annotated) superinterface are both observable:

```dart
@advancedReflector
class Shape { const Shape(); double get area => 0; }

@advancedReflector
class Drawable { const Drawable(); } // annotated so it appears in superinterfaces

@advancedReflector
class Circle extends Shape implements Drawable {
  final double radius;
  const Circle(this.radius);
  @override
  double get area => 3.14159 * radius * radius;
}
```

**Static members** — `Temperature` exposes two static factory methods, invoked
through the *class* mirror:

```dart
@advancedReflector
class Temperature {
  final double celsius;
  Temperature(this.celsius);
  static Temperature freezing() => Temperature(0);
  static Temperature boiling() => Temperature(100);
  double get fahrenheit => celsius * 9 / 5 + 32;
}
```

**Generics & mixins** — `Versioned<T>` is a generic mixin; `Note` applies it with
`String`, so `payload` and `version` are mixed-in members:

```dart
@advancedReflector
mixin class Versioned<T> {
  T? payload;
  int version = 0;
}

@advancedReflector
class Note with Versioned<String> {
  String text;
  Note(this.text);
}
```

---

## 5. Capabilities — the advanced set

The introduction sample needed four capabilities; this one adds three more,
because `newInstance`, full superclass walking and reflected return types each
require the generator to emit extra data.

| Capability | Grants | Used by |
| ---------- | ------ | ------- |
| `invokingCapability` | invoke instance **and** static members, getters and setters by name | all scenarios |
| `declarationsCapability` | enumerate members via `declarations` / `instanceMembers` / `staticMembers` | serializer, static, generics |
| `typeRelationsCapability` | read `.superclass` and `.superinterfaces` | type_relations |
| `superclassQuantifyCapability` | follow the superclass chain all the way to `Object` | type_relations |
| `newInstanceCapability` | construct objects via `newInstance` | serializer |
| `metadataCapability` | read annotations off declarations | (kept for completeness) |
| `reflectedTypeCapability` | read `reflectedReturnType` for members | generics_and_mixins |

Ask for an operation the reflector did not declare and you get a
`NoSuchCapabilityError` at runtime — a deliberate, explicit failure. The
[`reflection_capability_sample`](../reflection_capability_sample/README.md)
explores exactly which data each capability adds and the cost trade-off.

---

## 6. Scenario 1 — a reflection-driven serializer

[`example/serializer/main.dart`](example/serializer/main.dart)

This is the realistic use case. Two functions — written once, against the mirror
API — serialize and reconstruct *any* annotated object:

```dart
Map<String, Object?> toMap(Object instance) {
  final mirror = advancedReflector.reflect(instance);
  final classMirror = mirror.type;
  final out = <String, Object?>{};
  for (final entry in classMirror.declarations.entries) {
    final decl = entry.value;
    if (decl is VariableMirror && !decl.isStatic && !decl.isPrivate) {
      out[entry.key] = mirror.invokeGetter(entry.key);
    }
  }
  return out;
}

Object fromMap(ClassMirror classMirror, Map<String, Object?> data) {
  final instance = classMirror.newInstance('', const []); // unnamed ctor = ''
  final mirror = advancedReflector.reflect(instance);
  for (final entry in data.entries) {
    mirror.invokeSetter(entry.key, entry.value);
  }
  return instance;
}
```

Output:

```text
toMap   -> {sku: A-1, name: Widget, price: 9.5, stock: 12}
fromMap -> Product(A-1, Widget, $9.5, x12)
label   -> Widget (A-1)  (never in the map)
```

The mechanics worth internalising:

- **`toMap` filters `declarations` to stored state.** It keeps only entries that
  are a `VariableMirror` (a field, not a method or getter) and are neither static
  nor private. That is why `label` — a *getter*, hence a `MethodMirror` — never
  enters the map. Derived state is not persisted state.
- **`fromMap` constructs with `newInstance('', const [])`.** The unnamed
  constructor is addressed by the **empty string**; named constructors use their
  name. `Product`'s constructor is all-optional, so no positional arguments are
  required — the empty list suffices.
- **Then it writes each field back with `invokeSetter`.** Because the new instance
  is a real `Product`, the round-tripped clone is indistinguishable from the
  original.

This is the entire value proposition of runtime mirrors: the serializer does not
mention `Product` anywhere. Annotate a new class and the same two functions handle
it unchanged.

---

## 7. Scenario 2 — static members

[`example/static_members/main.dart`](example/static_members/main.dart)

Static members are reached through the **class** mirror, not an instance mirror.
`ClassMirror.invoke` targets a *static* method (whereas `InstanceMirror.invoke`
targets an instance method), and `staticMembers` enumerates the static surface the
way `instanceMembers` does for instances.

```dart
final classMirror = advancedReflector.reflect(Temperature(20)).type;

for (final name in (classMirror.staticMembers.keys.toList()..sort())) {
  print('  $name');
}

final freezing = classMirror.invoke('freezing', const []) as Temperature;
final boiling = classMirror.invoke('boiling', const []) as Temperature;
final fahrenheit =
    advancedReflector.reflect(boiling).invokeGetter('fahrenheit');
```

Output:

```text
staticMembers:
  boiling
  freezing
freezing()       -> 0.0C
boiling()        -> 100.0C
boiling.fahrenheit -> 212.0
```

To get the `ClassMirror` we reflect any instance and read `.type` — there is no
separate instance to invoke against, but the class mirror is the same regardless
of which instance produced it. The static factories return live `Temperature`
objects, which we then reflect over to read the `fahrenheit` instance getter —
mixing static and instance reflection in one flow.

---

## 8. Scenario 3 — type relations

[`example/type_relations/main.dart`](example/type_relations/main.dart)

`typeRelationsCapability` exposes `.superclass` and `.superinterfaces`;
`superclassQuantifyCapability` lets the superclass chain continue all the way up
to `Object` (whose own `.superclass` is `null`).

```dart
final classMirror = advancedReflector.reflect(Circle(2)).type;

var current = classMirror.superclass;
while (current != null) {
  print('  ${current.simpleName}');
  current = current.superclass;
}

for (final iface in classMirror.superinterfaces) {
  print('  ${iface.simpleName}');
}
```

Output:

```text
superclass chain:
  Shape
  Object
superinterfaces:
  Drawable
```

Two things to note:

- **The chain terminates cleanly.** `Circle.superclass` is `Shape`,
  `Shape.superclass` is `Object`, and `Object.superclass` is `null` — the loop
  condition. Reaching `Object` at all requires `superclassQuantifyCapability`;
  without it the chain stops short.
- **`superinterfaces` lists only *annotated* interfaces.** `Circle` implements
  `Drawable`, and `Drawable` carries `@advancedReflector`, so it appears. An
  un-annotated interface would simply not show up — which is why the domain
  annotates `Drawable` even though it is an empty marker.

---

## 9. Scenario 4 — generics and mixins

[`example/generics_and_mixins/main.dart`](example/generics_and_mixins/main.dart)

`Note` mixes in `Versioned<String>`, so `payload` (the mixin's `T`, resolved to
`String`) and `version` come from the mixin, not from `Note` itself. Mixed-in
members are reachable through the same mirror API as a class's own members.

```dart
final mirror = advancedReflector.reflect(Note('release notes'));

mirror.invokeSetter('version', 3);
mirror.invokeSetter('payload', 'v3 payload');

final classMirror = mirror.type;
for (final name in ['version', 'payload']) {
  final member = classMirror.instanceMembers[name];
  if (member is MethodMirror && member.hasReflectedReturnType) {
    print('  $name -> ${member.reflectedReturnType}');
  }
}
```

Output:

```text
version -> 3
payload -> v3 payload
note    -> Note(release notes, v3)
reflected return types:
  version -> int
```

The teaching point is the **guard**. `version`'s getter returns a concrete `int`,
so `hasReflectedReturnType` is true and `reflectedReturnType` yields `int`.
`payload`'s getter returns the *type variable* `T` — a bare type parameter is not
a reflectable concrete type, so `hasReflectedReturnType` is false and the loop
skips it. Always guard `reflectedReturnType` behind `hasReflectedReturnType`;
reaching for the type unconditionally throws when the generator did not capture
one. (Reading and writing the mixed-in fields by name works regardless — only the
*reflected return type* of a generic member is unavailable.)

---

## 10. The aggregator

[`bin/run_example.dart`](bin/run_example.dart) imports each scenario's `main()`
under a prefix and runs them in turn, counting failures:

```dart
final List<Scenario> scenarios = [
  (name: 'serializer', run: serializer.main),
  (name: 'static_members', run: static_members.main),
  (name: 'type_relations', run: type_relations.main),
  (name: 'generics_and_mixins', run: generics_and_mixins.main),
];

for (final scenario in scenarios) {
  try {
    scenario.run();
  } catch (e, st) {
    failures++;
    stderr.writeln('FAILED: ${scenario.name}: $e');
  }
}
if (failures > 0) exit(1);
```

Each scenario is a self-contained entry point with its own generated
`main.reflection.dart`. Because `initializeReflection()` simply re-assigns the
runtime globals, running four scenarios back-to-back in one process is safe: each
re-initialises before it reflects.

---

## 11. Two gotchas the sample bakes in

Both of these were real failures hit while building the sample, kept here because
they are easy to trip over:

- **Default values must match the field type.** `Product`'s `price` is a `double`,
  so its default must be `0.0`, not `0`. With `this.price = 0`, `newInstance('',
  [])` applies the `int` literal `0` to a `double` parameter and throws `type
  'int' is not a subtype of type 'double'`. A normal `Product()` call hides this
  (the compiler coerces the literal); reflection's `newInstance` does not, because
  it applies the recorded default value dynamically.
- **Generic return types are not reflected.** A member whose return type is a bare
  type variable (`T`) has no `reflectedReturnType`. Guard every
  `reflectedReturnType` access with `hasReflectedReturnType` — see
  [§9](#9-scenario-4--generics-and-mixins).

---

## 12. Regenerating after a change

The committed `*.reflection.dart` files must stay in lockstep with the *shape* of
the reflected classes. Regenerate when you change members, types, capabilities or
annotations — **not** when you only edit a method body.

```bash
./reflection_generation.sh
# which is just:
dart run build_runner build
```

Then re-run `dart run bin/run_example.dart` and commit the regenerated files
alongside the source change. Treat the generated files as outputs: never edit them
by hand.

---

## 13. Common errors and what they mean

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `type 'int' is not a subtype of type 'double'` from `newInstance` | A constructor default value's type doesn't match the field (e.g. `= 0` for a `double`) | Make the default match the type (`= 0.0`) |
| `type '<X>' is not a subtype of type 'Function'` from `invoke` | You called `invoke` on a field or getter | Use `invokeGetter(name)` instead |
| `NoSuchCapabilityError` | The reflector did not declare the capability the call needs (e.g. `newInstanceCapability`, `superclassQuantifyCapability`) | Add the capability to the reflector's `super(...)` and regenerate |
| `reflectedReturnType` throws | The member's return type is a bare type variable / not captured | Guard with `if (member.hasReflectedReturnType)` |
| An interface is missing from `superinterfaces` | The interface is not annotated | Annotate the interface with the reflector |
| Superclass chain stops before `Object` | `superclassQuantifyCapability` not declared | Add it and regenerate |

---

## 14. Where to go next

- [`reflection_capability_sample`](../reflection_capability_sample/README.md) —
  how each capability gates the generated code, minimal vs `useAllCapabilities`,
  the `NoSuchCapabilityError` path, and pattern capabilities like
  `InstanceInvokeCapability('^get')`.
- [`reflection_introduction_sample`](../reflection_introduction_sample/README.md)
  — the starting point, if you skipped it: annotate → generate → reflect → invoke.
- [`tom_reflection`](../../tom_reflection/README.md) — the runtime library
  reference (full mirror API and capability list).
- [`tom_reflection_generator`](../../tom_reflection_generator/README.md) — the
  generator (builder, CLI, and `build.yaml` / `buildkit.yaml` configuration).
- The samples index: [`../README.md`](../README.md).

For the *other* engine — build-time structural reflection that produces a
serializable model rather than runtime mirrors — start at
[`reflector_parser_introduction_sample`](../reflector_parser_introduction_sample/README.md).

---

## License

BSD-3-Clause. Derived from the
[`reflectable`](https://pub.dev/packages/reflectable) package by the Dart team
([`google/reflectable.dart`](https://github.com/google/reflectable.dart),
"Copyright (c) 2015, Dart") — retaining the upstream copyright alongside Tom's
modifications (© 2024–2026 Peter Nicolai Alexis Kyaw), released under the same
BSD-3-Clause terms. See
[`tom_reflection/LICENSE`](../../tom_reflection/LICENSE).
