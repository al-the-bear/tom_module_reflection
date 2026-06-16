# Reflector Reflection Introduction Sample

> Part of the Tom Framework reflection toolkit — an original analyzer-based
> build-time reflection engine (BSD 3-Clause). See
> [`LICENSE`](../../tom_reflector/LICENSE).

The code-generation face of **engine 2** —
[`tom_reflector`](../../tom_reflector/README.md) and its pure-data companion
[`tom_reflector_model`](../../tom_reflector_model/README.md).

The sibling
[`reflector_parser_introduction_sample`](../reflector_parser_introduction_sample/README.md)
showed engine 2's **parser** mode: run the analyzer, get a model *in memory*, and
inspect it. This sample shows engine 2's **other** mode — **generate code**. It
takes the model and emits a `*.r.dart` file: pure Dart data (descriptors plus
invoker closures) that you commit, compile, and consume at runtime with **no
analyzer present**. The generated file is the deliverable.

That changes what you can do. The parser model is *read-only structural data* —
you can see that `Product` has a method `discountedPrice`, but you cannot call
it. The generated reflection carries **closures**, so at runtime you can
construct a `Product`, invoke `discountedPrice` by name, read and write its
fields, and serialize any instance generically — all without the type being
known to the calling code. This is the "use case: generating code" path.

---

## Table of contents

1. [What you'll build](#1-what-youll-build)
2. [Project layout](#2-project-layout)
3. [Running it](#3-running-it)
4. [The big idea: model in, runnable reflection out](#4-the-big-idea-model-in-runnable-reflection-out)
5. [The domain](#5-the-domain)
6. [The generator step](#6-the-generator-step)
7. [Scenario 1 — inspect the generated index](#7-scenario-1--inspect-the-generated-index)
8. [Scenario 2 — drive live objects by name](#8-scenario-2--drive-live-objects-by-name)
9. [Scenario 3 — one generic serializer, every type](#9-scenario-3--one-generic-serializer-every-type)
10. [The runtime API at a glance](#10-the-runtime-api-at-a-glance)
11. [What the generated reflection captures (and what it doesn't)](#11-what-the-generated-reflection-captures-and-what-it-doesnt)
12. [The aggregator](#12-the-aggregator)
13. [Engine 2's two modes, and engine 1](#13-engine-2s-two-modes-and-engine-1)
14. [Where to go next](#14-where-to-go-next)

---

## 1. What you'll build

A small domain (`lib/catalog.dart`), a generator script that turns it into
committed reflection (`lib/catalog.r.dart`), and three runnable scenarios that
consume that reflection:

| Scenario | Demonstrates | Key API |
| -------- | ------------ | ------- |
| `inspect_generated` | Query the generated index — classes, members, annotations | `reflectionApi.allClasses`, `findClass`, `ClassDescriptor` |
| `invoke_dynamically` | Construct, invoke, read/write by name | `newInstance`, `invoke`, `getProperty`, `setProperty` |
| `serialize_with_reflection` | One generic serializer for every `@Entity` type | `isInstance`, `fields`, `getProperty` |

Everything is wired into one aggregator, `bin/run_example.dart`, which runs all
three and reports a pass/fail tally.

The recurring theme: **the generated file is ordinary Dart data.** There is no
analyzer at runtime, no mirrors, no `dart:mirrors`. `catalog.r.dart` is a tree of
plain descriptor objects holding closures — you import it like any other library
and call it.

---

## 2. Project layout

```
reflector_reflection_introduction_sample/
  pubspec.yaml                 depends on tom_reflector (by path) + path
  analysis_options.yaml        package:lints/recommended.yaml
  lib/
    catalog.dart               THE INPUT — the domain that is compiled AND reflected
    catalog.r.dart             THE OUTPUT — generated reflection (committed)
  bin/
    generate.dart              regenerates catalog.r.dart from catalog.dart
    run_example.dart           aggregator: runs every scenario, tallies pass/fail
  example/
    inspect_generated/
      main.dart                scenario 1 entry point
    invoke_dynamically/
      main.dart                scenario 2 entry point
    serialize_with_reflection/
      main.dart                scenario 3 entry point
```

The key structural difference from the parser sample: **`catalog.dart` is part of
this project.** Unlike the parser sample's `sample_source/` (analyzed as *text*
and never executed), this domain is compiled *into* the sample and its instances
are created and driven at runtime — entirely through the generated reflection.
There are no hand-written `Product(...)` calls in the scenarios.

`catalog.r.dart` is a **generated file that is committed.** That is deliberate
and consistent with the engine-1 samples (which also commit their
`*.reflection.dart`): committing the output means the scenarios compile out of
the box, with no generation step required before first run. Regenerate it with
`bin/generate.dart` whenever `catalog.dart` changes — never hand-edit it.

---

## 3. Running it

From this directory:

```bash
dart pub get

# Run all three scenarios with a pass/fail tally:
dart run bin/run_example.dart

# …or run a single scenario directly:
dart run example/inspect_generated/main.dart
dart run example/invoke_dynamically/main.dart
dart run example/serialize_with_reflection/main.dart

# Regenerate lib/catalog.r.dart after editing lib/catalog.dart:
dart run bin/generate.dart
```

The aggregator finishes with:

```text
--- 3/3 scenarios passed ---
```

and exits `0`; any scenario that throws prints `FAILED: <error>` under its
heading and the run exits `1`.

---

## 4. The big idea: model in, runnable reflection out

The code-generation path is a three-stage pipeline that ends in a source file:

```
  Dart source          analyze + model + generate            committed Dart
  ───────────          ──────────────────────────            ──────────────
  lib/catalog.dart ──► TomAnalyzer.analyzeBarrel       ──►   lib/catalog.r.dart
                       ReflectionModel.fromAnalysis           ├─ ClassDescriptors
                       ReflectionGenerator.generate           ├─ + invoker closures
                                                              └─ final reflectionApi
```

Three calls do the work (see [§6](#6-the-generator-step)):

1. **`TomAnalyzer().analyzeBarrel(...)`** walks the package's element model —
   the same analyzer entry point the parser sample uses.
2. **`ReflectionModel.fromAnalysis(...)`** distils the analysis into a
   *reflection model*: classes, members, constructors and globals, each paired
   with the invoker closures needed to drive them at runtime.
3. **`ReflectionGenerator().generate(model)`** emits the `.r.dart` source text.

The crucial difference from the parser model is what comes out the far end: not
an in-memory `AnalysisResult` you query and discard, but a **source file** that
becomes part of your program. At runtime you import it and get a top-level
`reflectionApi` — a ready-to-use index with live closures. The analyzer ran once,
at build time; it is nowhere near the running program.

---

## 5. The domain

[`lib/catalog.dart`](lib/catalog.dart) is the code we reflect. It is ordinary
Dart, chosen to exercise the parts of the reflection this sample teaches:

```dart
/// Marks a class as a persistable entity.
class Entity {
  final String table;
  const Entity(this.table);
}

@Entity('products')
class Product {
  final String sku;        // final field → read-only in reflection
  String name;             // mutable fields → readable AND writable
  double price;
  int stock;

  Product({required this.sku, this.name = '', this.price = 0, this.stock = 0});

  Product.sample()         // named constructor → keyed 'sample'
      : sku = 'SKU-0001', name = 'Sample Widget', price = 9.99, stock = 5;

  double discountedPrice(double pct) => price * (1 - pct);  // method
  String get label => '$name ($sku)';                       // getter

  @override
  String toString() => 'Product($sku)';
}

@Entity('warehouses')
class Warehouse {
  final String code;
  int capacity;
  Warehouse(this.code, {this.capacity = 100});
  bool get isFull => capacity <= 0;
  void receive(int units) => capacity -= units;
}

enum Availability { inStock, backordered, discontinued }

int catalogVersion() => 7;
```

Enough surface to show: a final field vs mutable fields, two constructors (one
unnamed, one named), an instance method, a getter, a marker annotation on two
classes, an enum, and a top-level function. Each one surfaces in the generated
reflection and is exercised at runtime by a scenario below.

---

## 6. The generator step

[`bin/generate.dart`](bin/generate.dart) is the whole code-generation use case in
one script. It resolves paths from `Platform.script` so it runs from any working
directory, then drives the three-call pipeline:

```dart
final analysis = await TomAnalyzer().analyzeBarrel(
  barrelPath: barrel,           // lib/catalog.dart
  workspaceRoot: projectRoot,
);
final model = ReflectionModel.fromAnalysis(analysis);
final content = ReflectionGenerator().generate(model);
File(output).writeAsStringSync(content);   // lib/catalog.r.dart
```

Running it prints, e.g.:

```text
Generated lib/catalog.r.dart (13677 chars)
```

The generated file imports `package:tom_reflector/tom_reflector.dart` (aliased
`ta`) plus the source library, then builds non-`const` maps of descriptors and
assembles them into a single top-level value:

```dart
import 'package:tom_reflector/tom_reflector.dart' as ta;
import 'package:reflector_reflection_introduction_sample/catalog.dart' as ...;

final _classes = <String, ta.ClassDescriptor>{ /* Entity, Product, Warehouse */ };
final _enums   = <String, ta.MemberContainerDescriptor>{ /* Availability */ };
final _globals = <String, ta.GlobalDescriptor>{ /* catalogVersion */ };

final reflectionApi = ta.ReflectionApi(
  classesByQualifiedName: _classes,
  enumsByQualifiedName: _enums,
  globalsByQualifiedName: _globals,
  // …mixins, extensions, typeAliases…
);
```

The maps are non-`const` because each descriptor carries closures that capture
the real constructors, methods and accessors — that is what makes the generated
reflection *runnable* rather than merely descriptive. `reflectionApi` is the one
symbol the scenarios import.

---

## 7. Scenario 1 — inspect the generated index

[`example/inspect_generated/main.dart`](example/inspect_generated/main.dart)

The entry point to a generated reflection: import `catalog.r.dart`, query
`reflectionApi`. There is no analyzer here — this is the build-time engine's
payoff, a ready-to-use index.

```dart
import 'package:reflector_reflection_introduction_sample/catalog.r.dart';

reflectionApi.allClasses.map((c) => c.name);   // [Entity, Product, Warehouse]
reflectionApi.allEnums.map((e) => e.name);     // [Availability]
reflectionApi.allGlobals.map((g) => g.name);   // [catalogVersion]
```

Output:

```text
classes -> [Entity, Product, Warehouse]
enums   -> [Availability]
globals -> [catalogVersion]
```

Drill into one class. `findClass` is the by-name lookup; every member group is a
name-keyed map:

```dart
final product = reflectionApi.findClass('Product')!;

product.qualifiedName;                 // package:…/catalog.dart.Product
product.annotations.map((a) => a.name); // [Entity]
product.constructors.keys;             // [new, sample]
product.methods.keys;                  // [discountedPrice, toString]
product.fields.keys;                   // [sku, name, price, stock, label]
```

Output:

```text
Product.qualifiedName -> package:reflector_reflection_introduction_sample/catalog.dart.Product
Product annotations   -> [@Entity]
Product constructors  -> [new, sample]
Product methods       -> [discountedPrice, toString]
Product fields        -> [sku, name, price, stock, label]
```

Two things worth noting up front. The unnamed constructor is keyed **`new`**, not
the empty string — passing `''` to `newInstance` throws. And the getter `label`
appears under `fields`, alongside the real fields; [§11](#11-what-the-generated-reflection-captures-and-what-it-doesnt)
explains why and how to tell them apart:

```dart
for (final name in ['sku', 'name', 'label']) {
  final f = product.fields[name]!;
  print('$name: final=${f.isFinal} writable=${f.setInstance != null} '
        'type=${f.typeQualifiedName}');
}
```

Output:

```text
field sku: final=true writable=false type=dart:core.String
field name: final=false writable=true type=dart:core.String
field label: final=false writable=false type=dart:core.String
```

A *final* field (`sku`) and a *getter* (`label`) both reflect as read-only —
neither has a setter closure. Only `isFinal` tells them apart: the final field is
`isFinal=true`, the getter `isFinal=false`.

Constructor parameters are captured too — names, types and defaults:

```dart
final ctor = product.constructors['new']!;
ctor.parameters.map((p) => '${p.name}:${p.typeQualifiedName}');
```

Output:

```text
Product() params -> [sku:dart:core.String, name:dart:core.String, price:dart:core.double, stock:dart:core.int]
```

And the dominant code-generation query — *find every class carrying a marker
annotation, by name*:

```dart
reflectionApi.allClasses
    .where((c) => c.annotations.any((a) => a.name == 'Entity'))
    .map((c) => c.name);            // [Product, Warehouse]
```

Output:

```text
@Entity classes -> [Product, Warehouse]
```

Enums reflect as named types — the generator records their presence, not their
constant values:

```dart
final availability = reflectionApi.allEnums.single;
'${availability.kind.name} fields=${availability.fields.length}';
```

Output:

```text
enum Availability: kind=enumType fields=0
```

---

## 8. Scenario 2 — drive live objects by name

[`example/invoke_dynamically/main.dart`](example/invoke_dynamically/main.dart)

This is where generated reflection earns its keep over the parser model. No
`Product(...)` or `product.discountedPrice(...)` appears in this file — every
construction, method call and property access goes through the descriptors. A
generic caller can operate on a type it was never compiled against.

```dart
final product = reflectionApi.findClass('Product')!;

// Construct via the UNNAMED constructor — keyed 'new', not ''.
final widget = product.newInstance(
  constructorName: 'new',
  named: {#sku: 'A-100', #name: 'Widget', #price: 20.0, #stock: 7},
)!;

// Invoke an instance method by name, with positional args.
product.invoke(widget, 'discountedPrice', positional: [0.25]);  // 15.0

// Read a field and a getter (both via getProperty).
product.getProperty(widget, 'price');   // 20.0
product.getProperty(widget, 'label');   // Widget (A-100)

// Mutate a writable field.
product.setProperty(widget, 'price', 8.0);
```

Output so far:

```text
built -> Product(A-100)
discountedPrice(0.25) -> 15.0
price -> 20.0
label -> Widget (A-100)
price after set -> 8.0
```

Writing a read-only member is rejected — the descriptor carries no setter closure
for a final field, so `setProperty` throws `StateError`:

```dart
try {
  product.setProperty(widget, 'sku', 'NOPE');
} on StateError catch (e) {
  print(e.message);
}
```

```text
setProperty(sku) rejected -> No instance property named sku for package:reflector_reflection_introduction_sample/catalog.dart.Product
```

The named constructor is reached by its key, and type queries run against the
qualified name the generator recorded:

```dart
final sample = product.newInstance(constructorName: 'sample')!;
product.getProperty(sample, 'name');   // Sample Widget
product.isInstance(widget);            // true
```

```text
Product.sample() -> Product(SKU-0001) name=Sample Widget
widget isInstanceOf Product -> true
```

Globals are invoked through their own descriptor — `invokeFunction` takes a
positional list and a named map:

```dart
final version = reflectionApi.findGlobal('catalogVersion')!;
version.invokeFunction!([], {});       // 7
```

```text
catalogVersion() -> 7
```

Construct, invoke, read, write, guard, query, call a global — the full dynamic
dispatch surface, none of it requiring the caller to know the concrete types.

---

## 9. Scenario 3 — one generic serializer, every type

[`example/serialize_with_reflection/main.dart`](example/serialize_with_reflection/main.dart)

The reason you generate reflection: write a serializer **once** and have it work
for every reflected type, present and future, with zero per-class code. A
hand-written `toJson` per class is exactly the boilerplate this replaces.

```dart
/// A field is "stored" if it holds real state: a final field (set once) or a
/// mutable field (has a setter). A getter such as Product.label has neither
/// isFinal nor a setter, so it is computed, not stored — and we skip it.
bool _isStored(FieldDescriptor f) => f.isFinal || f.setInstance != null;

Map<String, Object?> toMap(Object instance) {
  // Discover the descriptor from the live instance.
  final cls = reflectionApi.allClasses.firstWhere((c) => c.isInstance(instance));
  final result = <String, Object?>{};
  for (final entry in cls.fields.entries) {
    if (!_isStored(entry.value)) continue;
    result[entry.key] = cls.getProperty(instance, entry.key);
  }
  return result;
}
```

The same `toMap` handles both `Product` and `Warehouse` — both built
reflectively, neither named in the serializer:

```dart
final p = product.newInstance(
  constructorName: 'new',
  named: {#sku: 'A-100', #name: 'Widget', #price: 19.99, #stock: 7},
)!;
final w = warehouse.newInstance(
  constructorName: 'new', positional: ['WH-1'], named: {#capacity: 250},
)!;

final encoder = JsonEncoder.withIndent('  ');
print(encoder.convert(toMap(p)));
print(encoder.convert(toMap(w)));
```

Output:

```text
Product as JSON:
{
  "sku": "A-100",
  "name": "Widget",
  "price": 19.99,
  "stock": 7
}
Warehouse as JSON:
{
  "code": "WH-1",
  "capacity": 250
}
Product stored fields -> [sku, name, price, stock]
```

Note what is *absent*: the computed getters `Product.label` and `Warehouse.isFull`
never appear — `_isStored` filters them out. The serializer captures state, not
derived values, and it learned the difference from the descriptors, not from any
type-specific code.

---

## 10. The runtime API at a glance

Everything the scenarios call lives in `tom_reflector` (the runtime reflection
API, distinct from the parser model). The pieces this sample touches:

| Type / member | What it is | Used here for |
| ------------- | ---------- | ------------- |
| `reflectionApi` | Top-level value in `catalog.r.dart` | The generated index |
| `ReflectionApi.allClasses` / `allEnums` / `allGlobals` | Flat lists of descriptors | Inventory queries |
| `ReflectionApi.findClass(name)` | By-name (short or qualified) lookup | Locate a `ClassDescriptor` |
| `ReflectionApi.findGlobal(name)` | By-name global lookup | Locate a `GlobalDescriptor` |
| `ClassDescriptor.name` / `qualifiedName` / `annotations` | Class identity + markers | Inspection |
| `ClassDescriptor.constructors` / `methods` / `fields` | Name-keyed descriptor maps | Member access |
| `ClassDescriptor.newInstance(...)` | Construct via a named constructor | Scenarios 2, 3 |
| `ClassDescriptor.invoke(instance, name, ...)` | Call an instance method by name | Scenario 2 |
| `ClassDescriptor.getProperty` / `setProperty` | Read / write a field or getter | Scenarios 2, 3 |
| `ClassDescriptor.isInstance(obj)` | Generated runtime type-check | Scenarios 2, 3 |
| `FieldDescriptor.isFinal` / `setInstance` / `typeQualifiedName` | Field shape | Read-only vs writable |
| `ConstructorDescriptor.parameters` | Constructor parameter list | Scenario 1 |
| `ParameterDescriptor.name` / `typeQualifiedName` | Parameter shape | Scenario 1 |
| `GlobalDescriptor.invokeFunction` | Call a top-level function | Scenario 2 |
| `MemberContainerDescriptor.kind` / `fields` | Enum (and mixin) shape | Scenario 1 |
| `AnnotationDescriptor.name` | Marker annotation, by name | Scenario 1 |

The full surface lives in the [`tom_reflector` README](../../tom_reflector/README.md).

---

## 11. What the generated reflection captures (and what it doesn't)

Being precise about the edges saves you surprises:

- **The unnamed constructor is keyed `new`, not `''`.** `constructors['new']`
  is the default constructor; `newInstance(constructorName: 'new', …)` invokes
  it. Passing `''` throws `No constructor named  for …`.
- **Getters surface as read-only fields.** `Product.label` is a getter, but it
  folds into `fields` as a `FieldDescriptor` with a getter closure and **no**
  setter (`setInstance == null`) and `isFinal == false`. A *final field* is the
  other read-only shape: `setInstance == null` but `isFinal == true`. Use those
  two flags to discriminate (see `_isStored` in scenario 3).
- **Annotations are recorded by name, not by argument value.** `@Entity('products')`
  becomes an `AnnotationDescriptor` with `name: 'Entity'`; the string
  `'products'` is **not** captured (`positionalArguments` is empty). This matches
  the parser model and is sufficient for the dominant "which classes carry this
  marker?" query.
- **Enums reflect as name-only containers.** `Availability` appears in
  `allEnums` with `kind == TypeKind.enumType` and **empty** `fields` — the
  generator records the enum's presence as a named type, not its constant values.
- **Writing a read-only member throws.** `setProperty` on a final field or a
  getter raises `StateError` — there is no setter closure to call.

None of these are bugs to route around; they are the generated reflection's
current shape, and the scenarios are written to its actual contract.

---

## 12. The aggregator

[`bin/run_example.dart`](bin/run_example.dart) imports each scenario's `main()`
under a prefix, runs them in turn, and counts failures — the same shape as every
sample in this toolkit. Unlike the parser sample, these scenarios are
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

## 13. Engine 2's two modes, and engine 1

Engine 2 (`tom_reflector`) has **two modes**, and this sample is the second:

| | Parser mode | Reflection codegen mode (this) |
| --- | --- | --- |
| Sample | [`reflector_parser_introduction_sample`](../reflector_parser_introduction_sample/README.md) | this sample |
| Output | `AnalysisResult` (in memory) | `*.r.dart` (committed source) |
| What you can do | *Read* the code's structure | *Read and run* — construct, invoke, get/set |
| Carries closures? | No — pure data | Yes — descriptors hold invoker closures |
| Typical consumer | Indexers, API-diff, doc tools | Serializers, DI, dynamic dispatch |

Both build on the same analyzer; the codegen mode goes one step further and emits
a runnable artifact.

And both are distinct from **engine 1** (`tom_reflection`), the runtime
mirror-based fork of `reflectable`:

| | Engine 1 — `tom_reflection` | Engine 2 codegen — `tom_reflector` (this) |
| --- | --- | --- |
| When the model is built | At build time, via `build_runner` | At build time, via the generator script |
| Output file | `*.reflection.dart` | `*.r.dart` |
| API shape | Mirrors (`reflect(obj).invoke(...)`) | Descriptors (`findClass(...).invoke(...)`) |
| Lineage | Derived from `reflectable` | Original work |

They are different technologies that happen to share a repo. Keep their concepts
— and their generated-file conventions (`*.reflection.dart` vs `*.r.dart`) —
distinct.

---

## 14. Where to go next

- [`reflector_parser_introduction_sample`](../reflector_parser_introduction_sample/README.md)
  — engine 2's *other* mode: analyze source into an in-memory model, no codegen.
- [`reflector_reflection_advanced_sample`](../reflector_reflection_advanced_sample/README.md)
  — a deeper dive into the generated reflection: inheritance, mixins, static
  members, richer dispatch.
- [`tom_reflector`](../../tom_reflector/README.md) — the engine (analyzer runner,
  the two generation modes, the `reflector` CLI).
- [`tom_reflector_model`](../../tom_reflector_model/README.md) — the pure model
  and its serialization, in full.
- The samples index: [`../README.md`](../README.md).

For the *other* engine — runtime mirrors on live objects — start at
[`reflection_introduction_sample`](../reflection_introduction_sample/README.md).

---

## License

BSD 3-Clause — original work (not derived from `reflectable`). See
[`tom_reflector/LICENSE`](../../tom_reflector/LICENSE).
