# Reflection Introduction Sample

> Part of the Tom Framework reflection toolkit. **Derived from the
> [`reflectable`](https://pub.dev/packages/reflectable) package by the Dart team**
> ([`google/reflectable.dart`](https://github.com/google/reflectable.dart),
> "Copyright (c) 2015, Dart", BSD-3-Clause); Tom-specific refactoring, fixes and
> enhancements © 2024–2026 Peter Nicolai Alexis Kyaw, released under the same
> BSD-3-Clause terms. See
> [`LICENSE`](../../tom_reflection/LICENSE).

The first stop for **engine 1** of the Tom reflection toolkit —
[`tom_reflection`](../../tom_reflection/README.md), runtime reflection driven by
code generation. In about a hundred lines of domain code you will annotate two
classes, generate their mirror data, and then — at runtime — reflect over live
objects to **invoke methods by name**, **read and write fields by name**, and
**enumerate a class's declarations**.

If you have used `dart:mirrors` before, this will feel familiar — except it
works in AOT builds and Flutter, because the mirror data is generated ahead of
time and gated by *capabilities* so it stays small.

---

## Table of contents

1. [What you'll build](#1-what-youll-build)
2. [Project layout](#2-project-layout)
3. [Running it](#3-running-it)
4. [The mental model: annotate → generate → reflect](#4-the-mental-model-annotate--generate--reflect)
5. [The domain, line by line](#5-the-domain-line-by-line)
6. [Capabilities — why the reflector lists them](#6-capabilities--why-the-reflector-lists-them)
7. [Generation: how `*.reflection.dart` is produced](#7-generation-how-reflectiondart-is-produced)
8. [Scenario 1 — reflect and invoke](#8-scenario-1--reflect-and-invoke)
9. [Scenario 2 — read and write fields](#9-scenario-2--read-and-write-fields)
10. [Scenario 3 — introspect declarations](#10-scenario-3--introspect-declarations)
11. [The aggregator](#11-the-aggregator)
12. [Regenerating after a change](#12-regenerating-after-a-change)
13. [Common errors and what they mean](#13-common-errors-and-what-they-mean)
14. [Where to go next](#14-where-to-go-next)

---

## 1. What you'll build

A tiny domain — a `User` and an `Order` — annotated for reflection, plus three
runnable scenarios that exercise the core of the runtime-mirror API:

| Scenario | Demonstrates | Key calls |
| -------- | ------------ | --------- |
| `reflect_and_invoke` | Call methods by name on a live object | `reflect`, `invoke`, `invokeGetter` |
| `read_fields` | Read and write fields by name | `invokeGetter`, `invokeSetter`, `invoke` with args |
| `introspect` | Examine a class's own structure | `.type`, `declarations`, `MethodMirror` / `VariableMirror` |

Everything is wired into a single aggregator, `bin/run_example.dart`, which runs
all three and reports a pass/fail tally.

The whole point of runtime reflection is **dynamic dispatch**: working with a
value whose exact shape you did not know when you wrote the code — the basis of
serializers, dependency injection, form binders, and object inspectors.

---

## 2. Project layout

```
reflection_introduction_sample/
  pubspec.yaml                 depends on tom_reflection (runtime) +
                               tom_reflection_generator (dev, generates code)
  build.yaml                   tells build_runner to generate for example/**/main.dart
  reflection_generation.sh     one-liner to regenerate the mirror data
  analysis_options.yaml        package:lints/recommended.yaml
  lib/
    domain.dart                the reflector + the annotated User / Order classes
  example/
    reflect_and_invoke/
      main.dart                scenario 1 entry point
      main.reflection.dart     GENERATED mirror data (committed)
    read_fields/
      main.dart                scenario 2 entry point
      main.reflection.dart     GENERATED
    introspect/
      main.dart                scenario 3 entry point
      main.reflection.dart     GENERATED
  bin/
    run_example.dart           aggregator: runs every scenario, tallies pass/fail
```

Two things are worth calling out now, because they explain the rest of the
sample:

- **The annotated classes live in `lib/domain.dart`, but the generated files
  live next to each scenario `main.dart`.** That is not arbitrary — the
  generator is *entry-point driven* (see [§7](#7-generation-how-reflectiondart-is-produced)).
- **The `*.reflection.dart` files are committed.** They are build outputs, but a
  sample should run with a plain `dart run` and no build step, so we check them
  in. Never hand-edit them — regenerate (see [§12](#12-regenerating-after-a-change)).

---

## 3. Running it

From this directory:

```bash
dart pub get

# Run all three scenarios with a pass/fail tally:
dart run bin/run_example.dart

# …or run a single scenario directly:
dart run example/reflect_and_invoke/main.dart
dart run example/read_fields/main.dart
dart run example/introspect/main.dart
```

The aggregator prints each scenario under a banner and finishes with:

```text
----------------------------------------
Scenarios: 3  passed: 3  failed: 0
```

and exits `0`. If any scenario throws, it prints `FAILED: <name>: <error>` and
exits `1` — which is what makes it usable as a smoke test in CI.

---

## 4. The mental model: annotate → generate → reflect

Runtime reflection here is a three-beat cycle:

```
   ┌─ annotate ─────────┐   ┌─ generate ──────────┐   ┌─ reflect ───────────┐
   │ @introReflector    │   │ build_runner reads  │   │ initializeReflection│
   │ class User { … }   │ → │ the annotations and │ → │ reflector.reflect(o)│
   │ (in domain.dart)   │   │ emits the mirror    │   │ → mirror.invoke(…)  │
   └────────────────────┘   │ data (*.reflection) │   └─────────────────────┘
                            └─────────────────────┘
```

1. **Annotate.** You mark classes with a `const` reflector instance
   (`@introReflector`). The reflector declares *capabilities* — the operations
   you want to be able to perform.
2. **Generate.** `build_runner` (driving `tom_reflection_generator`) scans your
   entry points, finds the annotated classes, and writes a `*.reflection.dart`
   holding exactly the mirror data the declared capabilities require.
3. **Reflect.** At runtime you call `initializeReflection()` once (it wires the
   generated data in), then `reflector.reflect(object)` to get an
   `InstanceMirror` and operate on it by name.

The generator does the expensive work ahead of time; at runtime the mirrors are
just lookups into the generated tables. That is why it works in AOT and Flutter,
where `dart:mirrors` does not.

---

## 5. The domain, line by line

[`lib/domain.dart`](lib/domain.dart) declares the reflector once and the two
classes it covers.

```dart
import 'package:tom_reflection/tom_reflection.dart';

class IntroReflector extends Reflection {
  const IntroReflector()
      : super(
          invokingCapability,
          declarationsCapability,
          typeRelationsCapability,
          metadataCapability,
        );
}

const introReflector = IntroReflector();
```

`IntroReflector` is a subclass of `Reflection` with a **`const` constructor** —
that is mandatory, because the instance is used as an annotation, and Dart
annotations must be compile-time constants. The arguments to `super(...)` are the
capabilities (next section).

`introReflector` is the single `const` instance. Reusing one instance keeps the
generated data unambiguous: every `@introReflector` annotation refers to the same
reflector, so the generator emits one coherent table.

```dart
@introReflector
class User {
  String name;
  String email;
  int loginCount;

  User(this.name, this.email, {this.loginCount = 0});

  String greet() => 'Hi, I am $name';   // invoked by name in scenario 1
  void recordLogin() => loginCount++;   // a *mutating* method
  bool get isActive => loginCount > 0;  // a getter
}

@introReflector
class Order {
  final String id;
  final User customer;   // a field whose type is itself reflected
  double amount;

  Order(this.id, this.customer, this.amount);

  String summary() => 'Order $id for ${customer.name}: \$${amount.toStringAsFixed(2)}';
  double applyDiscount(double percent) => amount = amount * (1 - percent / 100);
}
```

Nothing here is reflection-specific except the `@introReflector` annotation —
these are ordinary classes. That is the point: you write normal Dart and opt
specific classes into reflection.

---

## 6. Capabilities — why the reflector lists them

Unlimited reflection is expensive: to support *everything* on *every* class, the
generator would have to emit data for every member, type relation and piece of
metadata in your program. Capabilities let you ask for only what you need, so the
generated code stays small.

This sample uses four:

| Capability | Grants | Used by |
| ---------- | ------ | ------- |
| `invokingCapability` | invoke methods, getters and setters by name | scenarios 1 & 2 |
| `declarationsCapability` | enumerate a class's members via `declarations` | scenario 3 |
| `typeRelationsCapability` | walk superclass / interface relations | (enables `.type`, superclass) |
| `metadataCapability` | read annotations off declarations | (kept for completeness) |

If you call an operation the reflector did not ask for, you get a
`NoSuchCapabilityError` at runtime — a deliberate, explicit failure rather than
silent wrong behaviour. The dedicated
[`reflection_capability_sample`](../reflection_capability_sample/README.md)
explores this trade-off in depth, including pattern capabilities like
`InstanceInvokeCapability('^get')`.

---

## 7. Generation: how `*.reflection.dart` is produced

The single most surprising thing about the generator is that it is **entry-point
driven**: it emits mirror data for a `.dart` file *only if that file has a
`main()`*. A plain library with annotated classes but no `main` produces nothing
(the generator literally writes "No output from reflection, there is no `main`").

That is why the annotated classes live in `lib/domain.dart` but the generated
files sit next to each scenario's `main.dart`. The generator starts at each entry
point, walks its import graph, finds the `@introReflector` classes reachable from
there, and writes the mirror data into a sibling `main.reflection.dart`.

[`build.yaml`](build.yaml) points the builder at the entry points:

```yaml
targets:
  $default:
    builders:
      tom_reflection_generator:reflection_generator:
        generate_for:
          - example/**/main.dart
        options:
          formatted: true
```

Each scenario then imports its generated file and calls the `initializeReflection()`
it defines:

```dart
import 'package:reflection_introduction_sample/domain.dart';
import 'main.reflection.dart';

void main() {
  initializeReflection(); // wires the generated data into the runtime
  // … reflect …
}
```

`initializeReflection()` is tiny — it just assigns the generated tables to the
reflection runtime's globals — so calling it more than once (as the aggregator
does, once per scenario) is harmless.

---

## 8. Scenario 1 — reflect and invoke

[`example/reflect_and_invoke/main.dart`](example/reflect_and_invoke/main.dart)

```dart
final user = User('Ada', 'ada@example.com');
final mirror = introReflector.reflect(user);

final greeting = mirror.invoke('greet', []);   // call a method by name
mirror.invoke('recordLogin', []);              // mutating method
mirror.invoke('recordLogin', []);
final active = mirror.invokeGetter('isActive'); // a getter → invokeGetter
```

Output:

```text
invoke greet()      -> Hi, I am Ada
loginCount before   -> 0
loginCount after    -> 2
invokeGetter active -> true
reflected greeting  -> Hi, I am Ada
```

Three things to take away:

- `reflect(object)` returns an **`InstanceMirror`** that wraps the live object.
- `invoke(name, positionalArgs)` calls a **method**; the argument list is
  positional (named args are passed via the optional `namedArgs` map).
- A **getter** is *not* a zero-arg method — read it with `invokeGetter('isActive')`.
  Calling `invoke('isActive', [])` throws `type 'bool' is not a subtype of type
  'Function'`, because the mirror finds a field/getter where it expected a method.

Because the mirror wraps the *real* object, invoking `recordLogin` actually
mutates `user.loginCount` — reflection is not a read-only view.

---

## 9. Scenario 2 — read and write fields

[`example/read_fields/main.dart`](example/read_fields/main.dart)

```dart
final mirror = introReflector.reflect(user);

mirror.invokeGetter('name');                       // read a field
mirror.invokeSetter('email', 'grace.hopper@…');    // write a field
mirror.invoke('applyDiscount', [10.0]);            // method with an argument
```

Output:

```text
name   -> Grace
email  -> grace@example.com
logins -> 3
updated email (object) -> grace.hopper@example.com
updated email (mirror) -> grace.hopper@example.com
order id     -> A-100
order amount -> 42.5
after 10% off -> 38.25
```

`invokeGetter` / `invokeSetter` treat fields and accessors uniformly: from the
caller's side, reading `name` (a field) and reading `isActive` (a getter) are the
same call. After `invokeSetter('email', …)`, both the object and a subsequent
`invokeGetter('email')` report the new value — confirming the mirror operates on
the real instance.

The last line shows passing an argument: `invoke('applyDiscount', [10.0])`
forwards `10.0` to `applyDiscount(double percent)` and returns its result.

---

## 10. Scenario 3 — introspect declarations

[`example/introspect/main.dart`](example/introspect/main.dart)

```dart
import 'package:tom_reflection/tom_reflection.dart'; // for MethodMirror / VariableMirror

final classMirror = mirror.type;                  // InstanceMirror → ClassMirror
for (final name in classMirror.declarations.keys) {
  final decl = classMirror.declarations[name];
  final kind = switch (decl) {
    MethodMirror m when m.isGetter => 'getter',
    MethodMirror m when m.isConstructor => 'constructor',
    MethodMirror() => 'method',
    VariableMirror() => 'field',
    _ => 'other',
  };
  print('  $name $kind');
}
```

Output:

```text
simpleName    -> Order
qualifiedName -> .Order
declarations:
  Order         constructor
  amount        field
  applyDiscount method
  customer      field
  id            field
  summary       method
  toString      method
```

`mirror.type` gives the `ClassMirror`; `declarations` is a map from member name
to a `DeclarationMirror`. Switching on the mirror's concrete type
(`MethodMirror` vs `VariableMirror`, plus the `isGetter`/`isConstructor` flags)
classifies each member. Note the import of
`package:tom_reflection/tom_reflection.dart` — `domain.dart` imports the
reflection library but does not *re-export* it, so the mirror types are not in
scope through the domain import alone.

`declarations` is only available because the reflector asked for
`declarationsCapability`. Drop that capability and this scenario fails with a
`NoSuchCapabilityError`.

---

## 11. The aggregator

[`bin/run_example.dart`](bin/run_example.dart) imports each scenario's `main()`
under a prefix and runs them in turn, counting failures:

```dart
final List<Scenario> scenarios = [
  (name: 'reflect_and_invoke', run: reflect_and_invoke.main),
  (name: 'read_fields', run: read_fields.main),
  (name: 'introspect', run: introspect.main),
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

Each scenario is a self-contained entry point — its own `main`, its own generated
`main.reflection.dart`. Because `initializeReflection()` simply re-assigns the
runtime globals, running three scenarios back-to-back in one process is safe: each
re-initialises before it reflects.

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
alongside the source change. Treat the generated files as outputs: never edit
them by hand.

---

## 13. Common errors and what they mean

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `type '<X>' is not a subtype of type 'Function'` from `invoke` | You called `invoke` on a field or getter | Use `invokeGetter(name)` instead |
| `NoSuchCapabilityError` | The reflector did not declare the capability the call needs | Add the capability to the reflector's `super(...)` and regenerate |
| `'MethodMirror' isn't a type` | The mirror types are not imported | `import 'package:tom_reflection/tom_reflection.dart';` |
| Generated file says "No output … there is no `main`" | You pointed `generate_for` at a library without a `main()` | Generate for entry-point files (`example/**/main.dart`) |
| Reflection calls fail at runtime with no data | `initializeReflection()` was never called | Call it once before any reflection |

---

## 14. Where to go next

- [`reflection_advanced_sample`](../reflection_advanced_sample/README.md) —
  declarations enumeration, `newInstance`, static members, type relations,
  generics and mixins, in a realistic use case.
- [`reflection_capability_sample`](../reflection_capability_sample/README.md) —
  how each capability gates the generated code, minimal vs `useAllCapabilities`,
  the `NoSuchCapabilityError` path, and pattern capabilities.
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
