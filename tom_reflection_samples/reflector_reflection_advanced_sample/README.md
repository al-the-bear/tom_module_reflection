# Reflector Reflection Advanced Sample

> Part of the Tom Framework reflection toolkit — an original analyzer-based
> build-time reflection engine (BSD 3-Clause). See
> [`LICENSE`](../../tom_reflector/LICENSE).

A deeper dive into the code-generation face of **engine 2** —
[`tom_reflector`](../../tom_reflector/README.md) and its pure-data companion
[`tom_reflector_model`](../../tom_reflector_model/README.md).

The
[`reflector_reflection_introduction_sample`](../reflector_reflection_introduction_sample/README.md)
generated reflection for **flat, unrelated classes** and drove them by name. This
sample raises the difficulty to where real programs live: a **class hierarchy**.
An abstract base, a mixin, an interface, two concrete subtypes, and static
members — and the questions that come with them. How does the generated
reflection represent inheritance? Where do mixed-in members go? How do you tell
an inherited field from a locally declared one? How do you dispatch the same
operation across subtypes without a single `if (obj is User)`? And the one trap
that bites every reflective serializer: **`isInstance` is subtype-inclusive.**

Everything here is consumed at runtime from a committed `*.r.dart` file, with no
analyzer present — the same payoff the introduction sample established. What is
new is the *shape* of the code being reflected, and the patterns you need to work
with it correctly.

---

## Table of contents

1. [What you'll build](#1-what-youll-build)
2. [Project layout](#2-project-layout)
3. [Running it](#3-running-it)
4. [The domain: a small hierarchy](#4-the-domain-a-small-hierarchy)
5. [The generator step](#5-the-generator-step)
6. [How the generated reflection represents a hierarchy](#6-how-the-generated-reflection-represents-a-hierarchy)
7. [Scenario 1 — inspect the hierarchy](#7-scenario-1--inspect-the-hierarchy)
8. [Scenario 2 — dispatch, relations, and the `isInstance` gotcha](#8-scenario-2--dispatch-relations-and-the-isinstance-gotcha)
9. [Scenario 3 — one generic serializer for the whole hierarchy](#9-scenario-3--one-generic-serializer-for-the-whole-hierarchy)
10. [The runtime API at a glance](#10-the-runtime-api-at-a-glance)
11. [The entry-point reachability configuration surface](#11-the-entry-point-reachability-configuration-surface)
12. [What the generated reflection captures (and what it doesn't)](#12-what-the-generated-reflection-captures-and-what-it-doesnt)
13. [The aggregator](#13-the-aggregator)
14. [Where to go next](#14-where-to-go-next)

---

## 1. What you'll build

A small class hierarchy (`lib/store.dart`), a generator script that turns it into
committed reflection (`lib/store.r.dart`), and three runnable scenarios that
consume that reflection:

| Scenario | Demonstrates | Key API |
| -------- | ------------ | ------- |
| `inspect_hierarchy` | Abstract flags, extends/with/implements, own vs inherited members, statics | `superclassQualifiedName`, `mixinQualifiedNames`, `declaringClassQualifiedName`, `staticFields` |
| `dispatch_and_relations` | Concrete-type resolution, type relations, static invocation, polymorphic dispatch | `isSubclassOf`, `implementsInterface`, `hasMixin`, `invokeStatic` |
| `serialize_roundtrip` | One generic serialize/deserialize pair for every subtype | `isInstance`, `newInstance`, `setProperty`, `getStaticProperty` |

Everything is wired into one aggregator, `bin/run_example.dart`, which runs all
three and reports a pass/fail tally.

The recurring theme of the advanced sample: **inheritance is flattened, and
`isInstance` answers "is-a".** Each class descriptor carries its inherited and
mixed-in members directly, tagged with where they came from; and the runtime
type-check is subtype-inclusive, so resolving the *concrete* descriptor of an
object takes a deliberate step. Get those two facts right and the rest composes.

---

## 2. Project layout

```
reflector_reflection_advanced_sample/
  pubspec.yaml                 depends on tom_reflector (by path) + path
  analysis_options.yaml        package:lints/recommended.yaml
  lib/
    store.dart                 THE INPUT — the class hierarchy, compiled AND reflected
    store.r.dart               THE OUTPUT — generated reflection (committed)
  bin/
    generate.dart              regenerates store.r.dart from store.dart
    run_example.dart           aggregator: runs every scenario, tallies pass/fail
  example/
    inspect_hierarchy/
      main.dart                scenario 1 entry point
    dispatch_and_relations/
      main.dart                scenario 2 entry point
    serialize_roundtrip/
      main.dart                scenario 3 entry point
```

Like the introduction sample, **`store.dart` is part of this project** — compiled
*into* the sample and driven at runtime entirely through the generated
reflection. There are no hand-written `User(...)` calls in the scenarios.

`store.r.dart` is a **generated file that is committed.** Committing the output
means the scenarios compile out of the box, with no generation step required
before first run. Regenerate it with `bin/generate.dart` whenever `store.dart`
changes — never hand-edit it.

---

## 3. Running it

From this directory:

```bash
dart pub get

# Run all three scenarios with a pass/fail tally:
dart run bin/run_example.dart

# …or run a single scenario directly:
dart run example/inspect_hierarchy/main.dart
dart run example/dispatch_and_relations/main.dart
dart run example/serialize_roundtrip/main.dart

# Regenerate lib/store.r.dart after editing lib/store.dart:
dart run bin/generate.dart
```

The aggregator finishes with:

```text
--- 3/3 scenarios passed ---
```

and exits `0`; any scenario that throws prints `FAILED: <error>` under its
heading and the run exits `1`.

---

## 4. The domain: a small hierarchy

[`lib/store.dart`](lib/store.dart) is deliberately a *graph* of related types,
not a bag of independent classes. Every relation the reflection has to represent
appears at least once:

```dart
class Persisted {                 // a marker annotation, recorded by name
  final String table;
  const Persisted(this.table);
}

mixin Timestamped {               // contributes a computed getter
  int get epochMillis;
  String get isoDate => DateTime.fromMillisecondsSinceEpoch(
      epochMillis, isUtc: true).toIso8601String();
}

abstract class Entity {           // the abstract base
  final String id;                // inherited final field
  Entity(this.id);
  String get kind;                // abstract getter, overridden per subtype
  static int schemaVersion = 3;   // static field
  static String describe() => 'entity schema v$schemaVersion';  // static method
  Map<String, Object?> baseFields() => {'id': id, 'kind': kind}; // inherited method
}

abstract class Auditable {        // an interface (implemented via `implements`)
  Map<String, Object?> auditFields();
}

@Persisted('users')
class User extends Entity with Timestamped implements Auditable {
  static const String table = 'users';
  String name;
  String email;
  @override final int epochMillis;
  int loginCount = 0;             // writable, NOT a constructor parameter
  User({required String id, required this.name,
        required this.email, required this.epochMillis}) : super(id);
  @override String get kind => 'user';
  void recordLogin() => loginCount++;
  @override Map<String, Object?> auditFields() => {'id': id, 'name': name};
  @override String toString() => 'User($id)';
}

@Persisted('orders')
class Order extends Entity with Timestamped {
  static const String table = 'orders';
  double total;
  @override final int epochMillis;
  Order({required String id, required this.total,
         required this.epochMillis}) : super(id);
  @override String get kind => 'order';
  @override String toString() => 'Order($id)';
}

enum Channel { web, mobile, api }
```

`User` is the interesting one: it `extends` a base, `with` a mixin, and
`implements` an interface — all three relations at once. `Order` shares the base
and the mixin but not the interface, which is exactly what makes the polymorphic
dispatch in scenario 2 and the generic serializer in scenario 3 worth writing:
the same reflective code drives both subtypes, and `Auditable` separates them
where it matters.

---

## 5. The generator step

[`bin/generate.dart`](bin/generate.dart) is the same three-call pipeline as the
introduction sample — the advanced sample is about the richer *domain*, not a
different generation path:

```dart
final analysis = await TomAnalyzer().analyzeBarrel(
  barrelPath: barrel,           // lib/store.dart
  workspaceRoot: projectRoot,
);
final model = ReflectionModel.fromAnalysis(analysis);
final content = ReflectionGenerator().generate(model);
File(output).writeAsStringSync(content);   // lib/store.r.dart
```

Running it prints, e.g.:

```text
Generated lib/store.r.dart (23713 chars)
```

This is the **legacy barrel path**: point the analyzer at a barrel file and
generate reflection for everything it exports. Engine 2 also defines a richer
**entry-point reachability** configuration surface — include/exclude filters,
transitive dependency resolution, and per-member coverage control — described in
[§11](#11-the-entry-point-reachability-configuration-surface). This sample's
*runnable* generation uses the barrel path because that is the path that
currently emits compiling, runnable output; the entry-point surface is documented
as the engine's designed configuration model.

---

## 6. How the generated reflection represents a hierarchy

Two design choices in the generated output shape everything the scenarios do.

**Inherited and mixed-in members are flattened.** Each `ClassDescriptor` carries
*all* of its members — declared, inherited, and mixed-in — in one set of maps;
you never walk the superclass chain to find `id`, it is already on `User.fields`.
The generator records *where* each came from in `declaringClassQualifiedName`:
`null` for a locally declared member, or the declaring type for an inherited one.
So `User.fields['id']` is tagged `Entity`, `User.fields['isoDate']` is
`Timestamped`, and `User.fields['name']` is `null`.

**The three relations are recorded by qualified name.** The descriptor holds
`superclassQualifiedName` (a single string), `interfaceQualifiedNames` (a list),
and `mixinQualifiedNames` (a list). The relation helpers on `ReflectionApi` —
`isSubclassOf`, `implementsInterface`, `hasMixin` — walk those by following the
`superclassQualifiedName` chain, so they give the **subtype-inclusive** answer
(a grandchild reports its grandparent's interfaces). This is the right tool when
you want "is this a kind of X?".

The contrast that follows from flattening: `ClassDescriptor.isInstance(obj)` is a
generated `obj is ThisType` check, so it too is subtype-inclusive — `Entity`'s and
`Auditable`'s descriptors both answer `true` for a `User`. That is correct for
"is-a" queries but wrong when you want the object's *concrete* descriptor. The fix
is to resolve by runtime type, shown next.

---

## 7. Scenario 1 — inspect the hierarchy

[`example/inspect_hierarchy/main.dart`](example/inspect_hierarchy/main.dart)

Start by reading the structure the generator captured. The top-level inventory
shows the annotation class (`Persisted`) sitting alongside the domain classes,
the mixin in its own list, and the enum in its:

```dart
reflectionApi.allClasses.map((c) => c.name);  // [Auditable, Entity, Order, Persisted, User]
reflectionApi.allMixins.map((m) => m.name);   // [Timestamped]
reflectionApi.allEnums.map((e) => e.name);    // [Channel]
```

```text
classes -> [Auditable, Entity, Order, Persisted, User]
mixins  -> [Timestamped]
enums   -> [Channel]
```

Abstract classes are flagged — and an abstract class cannot be constructed
reflectively (its generative constructor carries no invoker closure):

```dart
reflectionApi.findClass('Entity')!.isAbstract;  // true
reflectionApi.findClass('User')!.isAbstract;    // false
```

```text
Entity isAbstract -> true
User isAbstract   -> false
```

The extends/with/implements triad — each relation recorded by qualified name:

```dart
final user = reflectionApi.findClass('User')!;
user.superclassQualifiedName;     // …/store.dart.Entity
user.mixinQualifiedNames;         // [.../store.dart.Timestamped]
user.interfaceQualifiedNames;     // [.../store.dart.Auditable]
```

```text
User extends    -> Entity
User with       -> [Timestamped]
User implements -> [Auditable]
```

Now the flattening, made visible. Partition `User`'s fields by
`declaringClassQualifiedName` — `null` means locally declared, non-`null` names
the type the member was inherited from:

```dart
final own = <String>[];
final inherited = <String>[];
for (final f in user.fields.values) {
  final from = f.declaringClassQualifiedName;
  (from == null ? own : inherited)
      .add(from == null ? f.name : '${f.name}<-${_short(from)}');
}
```

```text
User own fields       -> [name, email, epochMillis, loginCount, kind]
User inherited fields -> [id<-Entity, isoDate<-Timestamped]
```

`id` comes from the base, `isoDate` from the mixin — both already present on
`User` without any chain-walking. Methods flatten identically: `baseFields` shows
up on `User` tagged `from Entity`.

Static members live in **their own maps**, never mixed with instance members:

```dart
final entity = reflectionApi.findClass('Entity')!;
entity.staticFields.keys;   // [schemaVersion]
entity.staticMethods.keys;  // [describe]
entity.methods.keys;        // [baseFields]   ← instance methods only
```

```text
Entity static fields  -> [schemaVersion]
Entity static methods -> [describe]
Entity instance methods (incl inherited) -> [baseFields]
```

Finally, the read-only/writable distinction carries over from the introduction
sample, and now spans inheritance: a getter (`kind`) and a final field
(`epochMillis`) both reflect as read-only fields with no setter; only `isFinal`
separates a stored final from a computed getter:

```text
field epochMillis: final=true writable=false
field kind: final=false writable=false
field loginCount: final=false writable=true
```

---

## 8. Scenario 2 — dispatch, relations, and the `isInstance` gotcha

[`example/dispatch_and_relations/main.dart`](example/dispatch_and_relations/main.dart)

This is the scenario that earns the "advanced" label. It starts with the trap
and then shows the tools.

**The gotcha.** `ClassDescriptor.isInstance` is a generated `is` check, so for a
`User` instance *three* descriptors answer `true` — its class, its base, and its
interface. A naive `firstWhere((c) => c.isInstance(obj))` returns whichever the
map iterates first, which here is an ancestor:

```dart
reflectionApi.allClasses.where((c) => c.isInstance(user)).map((c) => c.name);
// [Auditable, Entity, User]

reflectionApi.allClasses.firstWhere((c) => c.isInstance(user)).name;
// Auditable   ← WRONG: an ancestor, not the concrete class
```

```text
descriptors where isInstance(user) -> [Auditable, Entity, User]
naive firstWhere(isInstance) -> Auditable  (WRONG: an ancestor)
concreteOf(user)             -> User  (correct)
```

**The fix.** Resolve the concrete descriptor by the instance's runtime type:

```dart
ClassDescriptor concreteOf(Object instance) {
  final typeName = instance.runtimeType.toString();
  return reflectionApi.allClasses.firstWhere((c) => c.name == typeName);
}
```

This is the single most important pattern in the advanced sample: **use
`isInstance` for "is-a" questions; resolve by runtime type when you need the
object's own descriptor.** Both scenarios that touch instances (this one and
scenario 3) route through `concreteOf`.

**Type relations** are the *right* tool when you DO want the subtype-inclusive
answer. Each walks the superclass chain:

```dart
reflectionApi.isSubclassOf(userCls.qualifiedName, entityQN);          // true
reflectionApi.implementsInterface(userCls.qualifiedName, auditableQN); // true
reflectionApi.implementsInterface(orderCls.qualifiedName, auditableQN);// false
reflectionApi.hasMixin(userCls.qualifiedName, timestampedQN);          // true
```

```text
User  isSubclassOf Entity       -> true
User  implementsInterface Audit -> true
Order implementsInterface Audit -> false
User  hasMixin Timestamped      -> true
```

`Order implementsInterface Auditable -> false` is the payoff of the interface
relation: the generated reflection knows `User` is auditable and `Order` is not,
without either type being named in the calling code.

**Polymorphic dispatch.** One loop drives both subtypes. `kind` (an overridden
getter) and `isoDate` (a mixed-in getter) resolve per object — no type switch:

```dart
for (final instance in [user, order]) {
  final cls = concreteOf(instance);
  print('${cls.name}: kind=${cls.getProperty(instance, 'kind')} '
        'isoDate=${cls.getProperty(instance, 'isoDate')}');
}
```

```text
User: kind=user isoDate=1970-01-01T00:00:00.000Z
Order: kind=order isoDate=1970-01-01T00:00:00.000Z
```

An **inherited method** is callable through the leaf descriptor (flattening again
— `baseFields` is declared on `Entity` but present on `User`):

```text
user.baseFields() -> {id: U-1, kind: user}
```

**Static members** go through their own channel, never an instance.
`getStaticProperty` / `setStaticProperty` read and write static fields;
`invokeStatic` calls static methods:

```dart
final entityCls = reflectionApi.findClass('Entity')!;
entityCls.getStaticProperty('schemaVersion');   // 3
entityCls.setStaticProperty('schemaVersion', 4);
entityCls.invokeStatic('describe');              // entity schema v4
```

```text
Entity.schemaVersion       -> 3
Entity.describe() after set -> entity schema v4
```

The mutation is real: `describe()` reads the static field that
`setStaticProperty` just changed.

---

## 9. Scenario 3 — one generic serializer for the whole hierarchy

[`example/serialize_roundtrip/main.dart`](example/serialize_roundtrip/main.dart)

The reason you generate reflection over a hierarchy: a **single** serialize /
deserialize pair that handles every subtype, present and future, with no
per-type code. It builds directly on the two lessons above — resolve the concrete
descriptor, and trust that stored state includes inherited fields.

```dart
bool _isStored(FieldDescriptor f) => f.isFinal || f.setInstance != null;

ClassDescriptor _concreteOf(Object instance) =>
    reflectionApi.allClasses
        .firstWhere((c) => c.name == instance.runtimeType.toString());

Map<String, Object?> serialize(Object instance) {
  final cls = _concreteOf(instance);
  final out = <String, Object?>{'_type': cls.name};
  for (final entry in cls.fields.entries) {
    if (!_isStored(entry.value)) continue;
    out[entry.key] = cls.getProperty(instance, entry.key);
  }
  return out;
}
```

One serializer, both types. `id` (inherited from `Entity`) is captured
automatically; the computed `kind` / `isoDate` getters are skipped because they
are not stored state. The record is tagged with `_type` so the reader knows which
descriptor to reconstruct through:

```text
User serialized:
{
  "_type": "User",
  "name": "Ada",
  "email": "ada@example.io",
  "epochMillis": 0,
  "loginCount": 3,
  "id": "U-1"
}

Order serialized: {_type: Order, total: 42.5, epochMillis: 0, id: O-9}
```

**Reconstruction is the interesting half.** Not every stored field is a
constructor parameter — `User.loginCount` is mutable but not in the constructor.
So `deserialize` rebuilds through the constructor for the parameters it accepts,
then re-applies the leftover writable fields via `setProperty`:

```dart
Object deserialize(Map<String, Object?> data) {
  final cls = reflectionApi.findClass(data['_type'] as String)!;
  final ctor = cls.constructors['new']!;
  final ctorParams = ctor.parameters.map((p) => p.name).toSet();

  final named = <Symbol, dynamic>{};
  for (final p in ctor.parameters) {
    if (data.containsKey(p.name)) named[Symbol(p.name)] = data[p.name];
  }
  final instance = cls.newInstance(constructorName: 'new', named: named)!;

  for (final entry in data.entries) {
    if (entry.key == '_type' || ctorParams.contains(entry.key)) continue;
    final field = cls.fields[entry.key];
    if (field != null && field.setInstance != null) {
      cls.setProperty(instance, entry.key, entry.value);
    }
  }
  return instance;
}
```

The round-trip is stable — `loginCount` survives even though it never passes
through the constructor:

```text
rebuilt -> User(U-1) loginCount=3
round-trip stable -> true
```

**A tooling-grade payoff: a table registry.** Find every `@Persisted` class by
annotation name, read its `table` static, and key the descriptors by it — no
per-type code, and the registry can construct any entity by table name:

```dart
final registry = <String, ClassDescriptor>{};
for (final cls in reflectionApi.allClasses) {
  if (!cls.annotations.any((a) => a.name == 'Persisted')) continue;
  registry[cls.getStaticProperty('table') as String] = cls;
}
// registry['orders'].newInstance(constructorName: 'new', named: {...})
```

```text
@Persisted tables -> [orders, users]
built via registry[orders] -> Order(O-42) kind=order
```

Note the registry reads the table name from a **static field**, not from the
`@Persisted` annotation's argument — engine 2 records annotations by name only
(see [§12](#12-what-the-generated-reflection-captures-and-what-it-doesnt)), so the
canonical value lives on the class as a static.

---

## 10. The runtime API at a glance

Everything the scenarios call lives in `tom_reflector` (the runtime reflection
API, distinct from the parser model). The pieces this sample adds beyond the
introduction sample:

| Type / member | What it is | Used here for |
| ------------- | ---------- | ------------- |
| `ClassDescriptor.isAbstract` | Abstract-class flag | Scenario 1 |
| `ClassDescriptor.superclassQualifiedName` | The `extends` target | Scenario 1 |
| `ClassDescriptor.interfaceQualifiedNames` | The `implements` list | Scenario 1 |
| `ClassDescriptor.mixinQualifiedNames` | The `with` list | Scenario 1 |
| `FieldDescriptor.declaringClassQualifiedName` | Origin of a flattened member (`null` = local) | Scenarios 1, 3 |
| `MethodDescriptor.declaringClassQualifiedName` | Origin of a flattened method | Scenario 1 |
| `ClassDescriptor.staticFields` / `staticMethods` | Static members, in their own maps | Scenarios 1, 2, 3 |
| `ClassDescriptor.getStaticProperty` / `setStaticProperty` | Read / write a static field | Scenarios 2, 3 |
| `ClassDescriptor.invokeStatic(name, …)` | Call a static method | Scenario 2 |
| `ReflectionApi.isSubclassOf(a, b)` | Subtype-inclusive `extends` check | Scenario 2 |
| `ReflectionApi.implementsInterface(a, i)` | Subtype-inclusive `implements` check | Scenario 2 |
| `ReflectionApi.hasMixin(a, m)` | Subtype-inclusive `with` check | Scenario 2 |
| `ClassDescriptor.isInstance(obj)` | Generated `is` check (subtype-inclusive!) | Scenario 2 |
| `ClassDescriptor.newInstance` / `invoke` / `getProperty` / `setProperty` | Construct / dispatch by name | Scenarios 2, 3 |

The full surface lives in the [`tom_reflector` README](../../tom_reflector/README.md).

---

## 11. The entry-point reachability configuration surface

The barrel path used by `bin/generate.dart` is the simplest way to drive engine
2: analyze a barrel, reflect everything it exports. For large workspaces that is
too coarse — you want to start from a few **entry points** and pull in exactly
the reachable types, filtered by package/annotation/path, with explicit control
over how far transitive dependencies and member coverage extend. That is the
**entry-point reachability** configuration surface, defined by `ReflectionConfig`
in
[`tom_reflector/lib/src/reflection/generator/reflection_config.dart`](../../tom_reflector/lib/src/reflection/generator/reflection_config.dart)
and loaded from a `tom_analyzer:` / `tom_reflector:` block in `buildkit.yaml` (or
a standalone `tom_analyzer.yaml`) via `ReflectionConfig.load(...)` /
`ReflectionConfig.fromMap(...)`.

> **Status.** This sample's *runnable* generation uses the barrel path because it
> is the path that currently emits compiling, runnable output. The entry-point
> surface below is the engine's **designed** configuration model — described here
> so you can see the intended shape — and is exercised by the engine's own
> reachability/filter tests on the generated string. Treat this section as the
> configuration reference; treat the scenarios above as the runnable contract.

The shape of the configuration, with the YAML keys `fromMap` reads:

```yaml
tom_reflector:
  entry_points:               # roots of the reachability walk
    - lib/store.dart
  output: lib/store.r.dart

  defaults:                   # coarse, applied before per-filter rules
    include_packages: [reflector_reflection_advanced_sample]
    exclude_packages: [analyzer, meta]
    include_annotations: [Persisted]

  filters:                    # ordered include/exclude rules
    - include:
        annotations: [Persisted]    # only @Persisted-marked types …
        packages: [reflector_reflection_advanced_sample]
        paths: [lib/**]
        types: [User, Order]
        elements: [User.recordLogin]
    - exclude:
        types: [Channel]            # … minus these

  dependency_config:          # how far transitive resolution reaches
    superclasses:   { enabled: true, depth: -1, external_depth: 2 }
    interfaces:     { enabled: true, external: true }
    mixins:         { enabled: true, external: true }
    type_arguments: { enabled: true, external: true }
    type_annotations:
      { enabled: true, transitive: false, include_argument_types: true }
    subtypes:       { enabled: false }
    code_bodies:    { enabled: false, depth: 1 }
    marker_annotations:
      { enabled: false, marker_annotations: [Persisted] }

  # which members each covered type exposes — each block independently gated:
  coverage_config:
    instance_members: { ... }   # also: static_members, constructors, top_level,
    metadata:         { ... }   # type_info, declarations

  source_extraction: docOnly  # disabled | docOnly | full
  include_private: false
```

What each block controls:

- **`entry_points` + `filters`** — start from the entry points and keep only the
  types that match the include rules and survive the exclude rules. Filters match
  on `packages`, `annotations`, `paths`, `types`, and `elements`, so you can scope
  generation to, say, "every `@Persisted` class under `lib/`, except `Channel`".
- **`dependency_config`** — transitive resolution. When a covered type references
  another (as a superclass, interface, mixin, type argument, annotation, subtype,
  or inside a method body), these sub-configs decide whether — and how deep, and
  whether across package boundaries (`external`) — to pull the referenced type in.
  `depth: -1` means unbounded; `external_depth` caps how far the walk follows
  types from other packages.
- **`coverage_config`** — for each type that *is* covered, how much of it to emit:
  instance members, static members, constructors, top-level declarations,
  metadata, type info, and declaration lists are each independently gated. This is
  what keeps generated code small — you reflect only the members you will call.
- **`source_extraction`** — whether to embed source text (`disabled`), just
  doc comments (`docOnly`), or full bodies (`full`).

The barrel path is the special case of all this: one barrel as the entry point,
"everything it exports" as the filter, default dependency resolution, full
coverage. The entry-point surface generalises it to a real workspace.

---

## 12. What the generated reflection captures (and what it doesn't)

The introduction sample's edges (unnamed constructor keyed `new`, getters as
read-only fields, annotations by name, enums name-only, writing a read-only
member throws) all still hold. The hierarchy adds a few more:

- **Inherited and mixed-in members are flattened onto each class**, tagged with
  `declaringClassQualifiedName` (`null` = locally declared). You never walk the
  superclass chain to find an inherited member.
- **`isInstance` is subtype-inclusive** — a generated `obj is ThisType` check, so
  a base's and an interface's descriptors both match a subtype's instance. For an
  object's *concrete* descriptor, resolve by `runtimeType.toString()`.
- **The relation helpers walk the superclass chain.** `isSubclassOf`,
  `implementsInterface`, and `hasMixin` follow `superclassQualifiedName`, so a
  grandchild correctly reports an ancestor's interfaces and mixins.
- **Abstract classes cannot be constructed reflectively** — their generative
  constructor has no invoker; `newInstance` throws. The `isAbstract` flag warns
  you in advance.
- **Static members are separate** — in `staticFields` / `staticMethods`, reached
  through `getStaticProperty` / `setStaticProperty` / `invokeStatic`, never via an
  instance.
- **Annotation arguments are still not captured.** `@Persisted('users')` reflects
  as `name: 'Persisted'` with empty arguments; expose the value as a `static` and
  read it with `getStaticProperty`, as scenario 3's registry does.

These are the generated reflection's actual contract; the scenarios are written
to it, not around it.

---

## 13. The aggregator

[`bin/run_example.dart`](bin/run_example.dart) imports each scenario's `main()`
under a prefix, runs them in turn, and counts failures — the same shape as every
sample in this toolkit. As with the introduction sample, these scenarios are
**synchronous**: the analyzer already ran at build time, so consuming the
generated reflection needs no `await`.

```dart
typedef Scenario = ({String name, void Function() run});

for (final scenario in scenarios) {
  stdout.writeln('\n=== ${scenario.name} ===');
  try {
    scenario.run();
    passed++;
  } catch (e, st) {
    failures.add(scenario.name);
    stdout.writeln('  FAILED: $e\n$st');
  }
}
```

A non-zero exit code means at least one scenario threw. The generation step
(`bin/generate.dart`) is intentionally **not** part of the aggregator — the
generated file is committed, so the scenarios run without regenerating.

---

## 14. Where to go next

- [`reflector_reflection_introduction_sample`](../reflector_reflection_introduction_sample/README.md)
  — the gentler codegen sample: flat classes, construct/invoke/serialize by name.
- [`reflector_parser_introduction_sample`](../reflector_parser_introduction_sample/README.md)
  and
  [`reflector_parser_advanced_sample`](../reflector_parser_advanced_sample/README.md)
  — engine 2's *other* mode: analyze source into an in-memory model, no codegen.
- [`tom_reflector`](../../tom_reflector/README.md) — the engine (analyzer runner,
  the two generation modes, the `reflector` CLI, and the `ReflectionConfig`
  surface in full).
- [`tom_reflector_model`](../../tom_reflector_model/README.md) — the pure model
  and its serialization.
- The samples index: [`../README.md`](../README.md).

For the *other* engine — runtime mirrors on live objects — start at
[`reflection_introduction_sample`](../reflection_introduction_sample/README.md).

---

## License

BSD 3-Clause — original work (not derived from `reflectable`). See
[`tom_reflector/LICENSE`](../../tom_reflector/LICENSE).
