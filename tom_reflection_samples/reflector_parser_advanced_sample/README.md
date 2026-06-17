# Reflector Parser Advanced Sample

> Part of the Tom Framework reflection toolkit — an original analyzer-based
> build-time reflection engine (BSD 3-Clause). See
> [`LICENSE`](../../tom_reflector/LICENSE).

A deep dive into **engine 2's parser model** —
[`tom_reflector`](../../tom_reflector/README.md) and its pure-data companion
[`tom_reflector_model`](../../tom_reflector_model/README.md).

The [introduction sample](../reflector_parser_introduction_sample/README.md)
showed the parser mode on flat classes: analyze source text, get a model, read
names and fields. This sample walks the **hard parts** — the model features you
reach for when you build real tooling over a non-trivial codebase:

- **Nested type arguments** — `Map<String, List<OrderLine>>`, two deep.
- **Generic bounds** — `Node<T extends Entity>`.
- **The full inheritance triad** — `extends` / `with` / `implements`, each a
  separate resolvable type reference.
- **Mixins with `on` clauses** and **extensions** on generic types.
- **Cyclic references** — `Node.next` points back at `Node`; the analyzer
  resolves the cycle in memory without looping, and the serializer encodes it
  safely with id references.
- **A YAML round-trip** — the same cache-the-analysis workflow as JSON.

Then it builds the payoff: a **deterministic API-surface index** — the kind of
artifact a documentation generator, an API-diff tool, or a dependency graph
builder produces — assembled from *re-read* model data.

---

## Table of contents

1. [What you'll build](#1-what-youll-build)
2. [Project layout](#2-project-layout)
3. [Running it](#3-running-it)
4. [The big idea: the model is a graph](#4-the-big-idea-the-model-is-a-graph)
5. [The source set](#5-the-source-set)
6. [Scenario 1 — resolve the hard types](#6-scenario-1--resolve-the-hard-types)
7. [Scenario 2 — the YAML round-trip and cycle-safe ids](#7-scenario-2--the-yaml-round-trip-and-cycle-safe-ids)
8. [Scenario 3 — a deterministic API-surface index](#8-scenario-3--a-deterministic-api-surface-index)
9. [The model at a glance](#9-the-model-at-a-glance)
10. [What this engine captures (and what it doesn't)](#10-what-this-engine-captures-and-what-it-doesnt)
11. [The aggregator](#11-the-aggregator)
12. [Three reflection shapes — when to reach for which](#12-three-reflection-shapes--when-to-reach-for-which)
13. [Where to go next](#13-where-to-go-next)

---

## 1. What you'll build

Three runnable scenarios over one deliberately gnarly domain:

| Scenario | Demonstrates | Key API |
| -------- | ------------ | ------- |
| `resolve_types` | Generics, bounds, inheritance triad, mixins, extensions, in-memory cycle | `superclass`, `mixins`, `interfaces`, `typeParameters`, `TypeReference` |
| `yaml_roundtrip` | Serialize a cyclic graph to YAML and read it back | `YamlSerializer` / `YamlDeserializer` |
| `api_surface` | Walk the re-read model into a stable API index | `buildApiSurface` (the tool) |

Everything is wired into one aggregator, `bin/run_example.dart`, which runs all
three and reports a pass/fail tally.

The recurring theme: **the model is a graph of plain data.** Once analyzed, you
hold an ordinary Dart object graph — cyclic, fully typed, serializable — that you
can query, cache, re-read, and project into whatever artifact your tool needs.

---

## 2. Project layout

```
reflector_parser_advanced_sample/
  pubspec.yaml                 depends on tom_reflector (by path) + path
  analysis_options.yaml        package:lints/recommended.yaml
  sample_source/               THE INPUT — a tiny pure-Dart package, analyzed
    pubspec.yaml               (no dependencies; read as text, never run)
    lib/
      shop.dart                the domain: generics, mixins, extensions, a cycle
  lib/
    shop_analysis.dart         shared helpers: analyze, render types, build index
  example/
    resolve_types/
      main.dart                scenario 1 entry point
    yaml_roundtrip/
      main.dart                scenario 2 entry point
    api_surface/
      main.dart                scenario 3 entry point
  bin/
    run_example.dart           aggregator: runs every scenario, tallies pass/fail
```

As in the introduction sample, **`sample_source/` is input, not part of this
project.** It is a separate, dependency-free package that exists only to be
*read* by the analyzer, and it sits **outside `lib/`** so it is never confused
with this sample's own code. The sample's real code lives in
`lib/shop_analysis.dart` and the three `example/**/main.dart` entry points.

There are **no generated files** here. Parser mode produces its model *in memory
at runtime*; nothing is committed alongside the source. (The code-generation
mode that emits `*.r.dart` is the
[`reflector_reflection_introduction_sample`](../reflector_reflection_introduction_sample/README.md).)

---

## 3. Running it

From this directory:

```bash
dart pub get

# Run all three scenarios with a pass/fail tally:
dart run bin/run_example.dart

# …or run a single scenario directly:
dart run example/resolve_types/main.dart
dart run example/yaml_roundtrip/main.dart
dart run example/api_surface/main.dart
```

> Run the scenarios from inside this directory. Each one locates `sample_source/`
> by walking up from the current directory, so the working directory must be at
> or below the sample root.

The aggregator finishes with:

```text
----------------------------------------
Scenarios: 3  passed: 3  failed: 0
```

and exits `0`; any scenario that throws prints `FAILED: <name>: <error>` and
exits `1`.

`sample_source/` needs **no `dart pub get` of its own** — it has no dependencies,
so the analyzer resolves it against the SDK alone.

---

## 4. The big idea: the model is a graph

In the introduction sample the model looked like a tree — libraries holding
classes holding fields. Real code is not a tree. A field points at its declaring
type; a type reference points at its resolved declaration; a class points at its
superclass, mixins and interfaces; and a self-referential type
(`Node<T>? next`) points back at itself. The model mirrors all of that, which
makes it a **graph with cycles**.

Engine 2 handles the graph on two fronts:

- **In memory**, every `TypeReference` can carry a `resolvedElement` — a direct
  pointer to the `ClassInfo` / `MixinInfo` / `EnumInfo` it names. The analyzer
  links these as it builds the model, so you can hop from `Node.next`'s type
  straight to the `Node` declaration. Cycles are fine: the pointer just closes
  the loop.
- **On the wire**, every element has a stable **`id`**, and cross-references are
  serialized *as ids* rather than inlined. That is what lets a cyclic graph be
  encoded to JSON or YAML without looping forever, and rebuilt on the far side.

This sample's three scenarios trace exactly these properties: scenario 1 reads
the resolved in-memory graph, scenario 2 round-trips it through YAML, and
scenario 3 builds a tool from the re-read result.

---

## 5. The source set

[`sample_source/lib/shop.dart`](sample_source/lib/shop.dart) is the domain we
analyze — ordinary, dependency-free Dart, chosen to exercise every advanced
feature this sample teaches:

```dart
class Table {
  final String name;
  final String schema;
  const Table(this.name, {this.schema = 'public'});   // annotation w/ args
}

abstract class Entity { String get id; }

mixin Timestamped on Entity {                          // on-clause mixin
  DateTime get createdAt;
  int ageInDays(DateTime now) => now.difference(createdAt).inDays;
}

@Table('orders', schema: 'sales')
class Order extends Entity with Timestamped             // extends + with +
    implements Comparable<Order> {                      //   implements
  @override final String id;
  @override final DateTime createdAt;
  final List<OrderLine> lines;                          // type argument
  Order(this.id, this.createdAt, this.lines);
  @override int compareTo(Order other) => id.compareTo(other.id);
  Map<String, List<OrderLine>> groupedByDay() => {};    // nested type args
}

@Table('order_lines')
class OrderLine extends Entity {
  @override final String id;
  final int quantity;
  OrderLine(this.id, this.quantity);
}

class Node<T extends Entity> {                          // generic bound
  final T value;
  Node<T>? next;                                         // self-reference
  Node(this.value, [this.next]);
}

extension OrderQuery on List<Order> {                   // extension on generic
  List<Order> openOnly() => this;
  int get lineCount => fold(0, (sum, o) => sum + o.lines.length);
}

enum Status { open, paid, closed }
int recordCount() => 0;
```

Every line is there to land on a model feature: an annotation carrying
arguments, an abstract contract, an `on`-clause mixin, the full
extends/with/implements triad, a field with a type argument, a method nesting
type arguments two deep, a bounded generic with a cyclic field, and an extension
on a generic type.

---

## 6. Scenario 1 — resolve the hard types

[`example/resolve_types/main.dart`](example/resolve_types/main.dart)

Analyze, then read the resolved graph. The whole domain inventory first:

```dart
final result = await analyzeShop();
result.allClasses.map((c) => c.name);     // [Table, Id, Entity, Order, OrderLine, Node]
result.allMixins.map((m) => m.name);      // [Timestamped]
result.allExtensions.map((e) => e.name);  // [OrderQuery]
```

Output:

```text
classes    -> [Table, Id, Entity, Order, OrderLine, Node]
mixins     -> [Timestamped]
extensions -> [OrderQuery]
```

`Order` carries the full inheritance triad — three independent, resolvable type
references:

```dart
final order = result.findClassesByName('Order').single;
renderType(order.superclass!);                 // Entity
order.mixins.map(renderType);                  // [Timestamped]
order.interfaces.map(renderType);              // [Comparable<Order>]
```

Output:

```text
Order extends    -> Entity
Order with       -> [Timestamped]
Order implements -> [Comparable<Order>]
```

Note `Comparable<Order>` — the interface keeps its type argument. Nested
arguments survive arbitrarily deep:

```dart
final grouped = order.methods.firstWhere((m) => m.name == 'groupedByDay');
renderType(grouped.returnType);                // Map<String, List<OrderLine>>
```

```text
groupedByDay() -> Map<String, List<OrderLine>>
```

`renderType` (in `shop_analysis.dart`) is a five-line recursion over
`TypeReference.typeArguments`; the model did the hard work of capturing the
structure. **Crucially it reads only the inline data** — `name`,
`typeArguments`, `isNullable` — never `resolvedElement`. That is what makes the
same renderer work before *and* after a serialization round-trip ([§7](#7-scenario-2--the-yaml-round-trip-and-cycle-safe-ids)).

Generics keep their bounds, and type parameters are flagged as such:

```dart
final node = result.findClassesByName('Node').single;
node.typeParameters.map(renderTypeParameter);  // [T extends Entity]

final value = node.fields.firstWhere((f) => f.name == 'value');
renderType(value.type);                         // T
value.type.isTypeParameter;                      // true
```

```text
Node type params -> [T extends Entity]
Node.value type  -> T (isTypeParameter=true)
```

And the self-referential field shows the **in-memory cycle resolved**:

```dart
final next = node.fields.firstWhere((f) => f.name == 'next');
renderType(next.type);                 // Node<T>?
next.type.isResolved;                  // true
next.type.resolvedElement?.name;       // Node   ← points back at the declaration
```

```text
Node.next type   -> Node<T>?
Node.next resolved -> true (-> Node)
```

`Node.next` is a `Node<T>?` whose `resolvedElement` is the very `Node` class we
are standing in — a closed loop the analyzer walked without looping. This
cross-link is an **in-memory convenience**; [§7](#7-scenario-2--the-yaml-round-trip-and-cycle-safe-ids)
shows what happens to it across a serialization boundary.

Finally, the mixin's `on` clause and the extension's target — both resolvable
references:

```dart
final mixin = result.allMixins.single;
mixin.onTypes.map(renderType);          // [Entity]
mixin.methods.map((m) => m.name);       // [ageInDays]

final ext = result.allExtensions.single;
renderType(ext.extendedType);           // List<Order>
ext.methods.map((m) => m.name);         // [openOnly]
```

```text
Timestamped on -> [Entity] methods=[ageInDays]
OrderQuery on  -> List<Order> methods=[openOnly]
```

---

## 7. Scenario 2 — the YAML round-trip and cycle-safe ids

[`example/yaml_roundtrip/main.dart`](example/yaml_roundtrip/main.dart)

Because the model is pure data, it can be written to disk and re-read without
re-running the analyzer — the realistic "cache the analysis" workflow. This is
the JSON round-trip from the introduction sample, in YAML, over a **cyclic**
model:

```dart
final original = await analyzeShop();

// Encode the cyclic model — terminates because cross-references are ids.
final yaml = YamlSerializer.encode(original);

// Persist (build/ is gitignored), then read back from disk.
final outFile = File(p.join('build', 'shop.analysis.yaml'));
outFile.parent.createSync(recursive: true);
outFile.writeAsStringSync(yaml);
final restored = YamlDeserializer.decode(outFile.readAsStringSync());
```

Output:

```text
encoded YAML -> ~65000 chars
classes    6 -> 6
mixins     1 -> 1
extensions 1 -> 1

restored Order extends    -> Entity
restored Order implements -> [Comparable<Order>]
restored groupedByDay()   -> Map<String, List<OrderLine>>
restored Node param       -> [T extends Entity]
restored Node.next type     -> Node<T>?
restored Node.next resolved -> false

round-trip -> identical structure
```

**Why encoding a cycle terminates.** `Node.next` references `Node`, which
references `Node.next`… a naive serializer would recurse forever.
`YamlSerializer` (and `JsonSerializer`) give every element a stable **id** and
write cross-references *as ids* (`declaringTypeId`, `resolvedElementId`,
`mainSourceFileId`, …) rather than inlining the referenced object. The cycle
becomes two elements that mention each other's ids — finite text. This is the
`IdGenerator` / id-reference design at the heart of `tom_reflector_model`.

**What survives, and what doesn't.** Everything *structural* round-trips: the
counts match, and the restored model renders **identical** type strings —
`Map<String, List<OrderLine>>`, `Comparable<Order>`, `Node<T>?`,
`T extends Entity`. That is because `renderType` reads the inline `TypeReference`
data, all of which is serialized.

The one thing that does **not** survive is the in-memory `resolvedElement`
cross-link: after the round-trip, `Node.next.type.isResolved` is `false`. The
type still *renders* as `Node<T>?` (inline data), but the resolved-object pointer
is not rebuilt. The practical rule: **across a serialization boundary, key on
names and qualified names, not object identity.** Within a single in-memory
analysis, `resolvedElement` is the fast path; once you cache and re-read, fall
back to lookups by name. Scenario 3 is written to that rule — it uses only data
that survives.

> **YAML vs JSON.** The two serializers are interchangeable in shape; pick YAML
> for human-reviewable caches, JSON for compactness and speed. The byte length
> printed above is approximate — the encoding embeds absolute file paths and
> timestamps, so the exact count differs by machine and run. When you need a
> *stable* artifact, project the model down to its shape, which is exactly what
> scenario 3 does.

---

## 8. Scenario 3 — a deterministic API-surface index

[`example/api_surface/main.dart`](example/api_surface/main.dart)

The advanced engine-2 deliverable: walk the model into a **deterministic**
API-surface index — names, type relationships, generic shapes, mixins and
extensions — with every collection sorted so the output bytes are identical on
every run. We build it from **re-read** data (round-trip through YAML first), so
the report is demonstrably assembled from a cached model, exactly as a downstream
tool would work:

```dart
final analysed = await analyzeShop();
final model = YamlDeserializer.decode(YamlSerializer.encode(analysed));
final surface = buildApiSurface(model);             // projects + sorts
print(const JsonEncoder.withIndent('  ').convert(surface));
```

`buildApiSurface` (in `shop_analysis.dart`) keeps names, kinds, type
relationships and members, drops every volatile field, and sorts every
collection. The result (abridged — the full output is what the scenario prints):

```json
{
  "package": "shop_domain",
  "classes": [
    { "name": "Entity", "isAbstract": true,
      "fields": [ { "name": "id", "type": "String", "isFinal": false } ],
      "methods": [] },
    { "name": "Node",
      "typeParameters": [ "T extends Entity" ],
      "fields": [
        { "name": "next", "type": "Node<T>?", "isFinal": false },
        { "name": "value", "type": "T", "isFinal": true }
      ],
      "methods": [] },
    { "name": "Order",
      "extends": "Entity",
      "with": [ "Timestamped" ],
      "implements": [ "Comparable<Order>" ],
      "annotations": [ "Table" ],
      "fields": [
        { "name": "createdAt", "type": "DateTime", "isFinal": true },
        { "name": "id", "type": "String", "isFinal": true },
        { "name": "lines", "type": "List<OrderLine>", "isFinal": true }
      ],
      "methods": [
        { "name": "compareTo", "returnType": "int" },
        { "name": "groupedByDay", "returnType": "Map<String, List<OrderLine>>" }
      ] }
  ],
  "mixins": [
    { "name": "Timestamped", "on": [ "Entity" ], "methods": [ "ageInDays" ] }
  ],
  "extensions": [
    { "name": "OrderQuery", "on": "List<Order>", "methods": [ "openOnly" ] }
  ],
  "enums": [
    { "name": "Status", "values": [ "open", "paid", "closed" ] }
  ],
  "functions": [
    { "name": "recordCount", "returnType": "int" }
  ]
}
```

This projection is the heart of the advanced use case. Everything a docs
generator or an API-diff tool needs is here, in a form you could check into a
repo and diff against the next run: `Order` keeps its full inheritance triad and
its `@Table` marker; `Node` keeps `T extends Entity` and its `Node<T>?` cycle;
`groupedByDay` keeps `Map<String, List<OrderLine>>`; the mixin keeps its `on`
clause; the extension keeps its `List<Order>` target. Because it is built from
re-read data and uses only names/inline-types, it is **stable across the
serialization boundary** — the deterministic artifact the volatile raw encoding
could never be.

---

## 9. The model at a glance

The objects this sample walks all come from `tom_reflector_model` (re-exported by
`tom_reflector`). Beyond the introduction sample's set, the advanced features
live here:

| Type / member | What it is | Used here for |
| ------------- | ---------- | ------------- |
| `ClassInfo.superclass` | The `extends` clause | `Order extends Entity` |
| `ClassInfo.mixins` | The `with` clause | `Order with Timestamped` |
| `ClassInfo.interfaces` | The `implements` clause | `Order implements Comparable<Order>` |
| `ClassInfo.typeParameters` | Generic parameters | `Node<T>` |
| `MixinInfo.onTypes` | A mixin's `on` clause | `Timestamped on Entity` |
| `ExtensionInfo.extendedType` | An extension's target | `OrderQuery on List<Order>` |
| `TypeParameterInfo.bound` | A generic bound | `T extends Entity` |
| `TypeReference.typeArguments` | Nested type arguments | `Map<String, List<OrderLine>>` |
| `TypeReference.isNullable` | Nullability | `Node<T>?` |
| `TypeReference.isTypeParameter` | Is this a `T`? | `value: T` |
| `TypeReference.resolvedElement` | In-memory resolved declaration | the `Node` cycle |
| `TypeReference.isResolved` | Is the cross-link present? | survives in memory, not the wire |
| `YamlSerializer` / `YamlDeserializer` | YAML round-trip | scenario 2 / 3 |
| `IdGenerator` | Stable element ids | cycle-safe references |

The full inventory lives in the
[`tom_reflector_model` README](../../tom_reflector_model/README.md).

---

## 10. What this engine captures (and what it doesn't)

Being precise about the model's edges saves you surprises:

- **`resolvedElement` is in-memory only.** Within a single analysis, a
  `TypeReference` carries a live pointer to its declaration (`Node.next`
  → `Node`). After a JSON/YAML round-trip that pointer is **not** rebuilt
  (`isResolved` → `false`), even though the type still *renders* correctly from
  inline data. Across a serialization boundary, look declarations up by
  qualified name.
- **Annotations are recorded by name, not by argument value.** `@Table('orders',
  schema: 'sales')` becomes an `AnnotationInfo` with `name: 'Table'`. The model
  *has* slots for arguments (`positionalArguments`, `namedArguments`), but this
  analyzer version leaves them empty — the captured fact is "this element is
  marked `@Table`", which is what the dominant *"find every element with this
  marker"* query needs. If you need argument values, that is a job for richer
  metadata extraction, not this model.
- **Getters surface as fields on classes.** As in the introduction sample,
  property accessors fold into `ClassInfo.fields` rather than a separate list;
  use the `isFinal` / accessor flags to discriminate. (Extension getters such as
  `OrderQuery.lineCount` are not surfaced under `ExtensionInfo.getters` in this
  version — read extension *methods*, which are captured reliably.)
- **`errors` is part of the result.** `AnalysisResult.errors` holds diagnostics;
  here it is empty, your signal the source resolved cleanly.

None of these are bugs to route around; they are the model's current shape, and
the scenarios — especially the API-surface tool — are written to what it reliably
provides.

---

## 11. The aggregator

[`bin/run_example.dart`](bin/run_example.dart) imports each scenario's `main()`
under a prefix, awaits them in turn, and counts failures — the same shape as the
introduction sample, and **asynchronous** because the analyzer is async:

```dart
typedef Scenario = ({String name, Future<void> Function() run});

for (final scenario in scenarios) {
  stdout.writeln('\n=== ${scenario.name} ===');
  try {
    await scenario.run();
  } catch (e, st) {
    failures++;
    stderr.writeln('FAILED: ${scenario.name}: $e');
  }
}
```

Running the analyzer three times in one process is safe — each `analyzeShop()`
builds its own context and returns an independent model.

---

## 12. Three reflection shapes — when to reach for which

This sample is one of three engine-2 / engine-1 shapes in the toolkit:

| | Engine 2 — parser | Engine 2 — codegen | Engine 1 — mirrors |
| --- | --- | --- | --- |
| Package | `tom_reflector` | `tom_reflector` | `tom_reflection` |
| When it runs | Build time, on source text | Build time (emits `*.r.dart`) | Runtime, on live objects |
| Output | `AnalysisResult` (in memory) | committed `*.r.dart` | generated `*.reflection.dart` |
| What you do | *Read* code structure | *Read and run* generated code | invoke by name on instances |
| This sample | **yes** | — | — |
| Typical consumer | Docs / API-diff / indexers | Serializers, DI | Dynamic dispatch |

Reach for the **parser** (this sample's mode) when you are building tooling that
needs to reason about code structure *before* the program runs and wants a stable
model it can cache, diff, and re-read — exactly the API-surface index built here.
Reach for **codegen** when you want that structure compiled into runnable
reflection, and for **engine 1** when running code must invoke members it knows
only by name.

They are different technologies sharing a repo. Keep their concepts — and their
generated-file conventions (`*.reflection.dart` vs `*.r.dart`) — distinct.

---

## 13. Where to go next

- [`reflector_parser_introduction_sample`](../reflector_parser_introduction_sample/README.md)
  — the gentle introduction to parser mode (flat classes, the JSON round-trip).
- [`reflector_reflection_introduction_sample`](../reflector_reflection_introduction_sample/README.md)
  — engine 2's *other* mode: generate `*.r.dart` and run the reflection.
- [`reflector_reflection_advanced_sample`](../reflector_reflection_advanced_sample/README.md)
  — the codegen counterpart to this deep dive.
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
