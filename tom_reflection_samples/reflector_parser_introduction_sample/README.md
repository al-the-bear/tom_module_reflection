# Reflector Parser Introduction Sample

> Part of the Tom Framework reflection toolkit — an original analyzer-based
> build-time reflection engine (BSD 3-Clause). See
> [`LICENSE`](../../tom_reflector/LICENSE).

The starting point for **engine 2** of the Tom reflection toolkit —
[`tom_reflector`](../../tom_reflector/README.md) and its pure-data companion
[`tom_reflector_model`](../../tom_reflector_model/README.md).

Where [engine 1](../reflection_introduction_sample/README.md) gives you *runtime
mirrors* on live objects, engine 2 does something different: it runs the Dart
**analyzer** over source *text* and hands back a **serializable object model** of
the code's shape — every class, method, field, type parameter and annotation, as
plain data you can query, cache, ship, and re-read. Nothing in the analyzed
source is ever executed.

This sample is the gentle introduction. It analyzes a tiny domain, walks the
resulting model, round-trips it through JSON, and emits a stable JSON report —
the canonical "use case: JSON" for build-time reflection.

---

## Table of contents

1. [What you'll build](#1-what-youll-build)
2. [Project layout](#2-project-layout)
3. [Running it](#3-running-it)
4. [The big idea: source in, data out](#4-the-big-idea-source-in-data-out)
5. [The source set](#5-the-source-set)
6. [Scenario 1 — analyze and inspect](#6-scenario-1--analyze-and-inspect)
7. [Scenario 2 — the JSON round-trip](#7-scenario-2--the-json-round-trip)
8. [Scenario 3 — a stable model report](#8-scenario-3--a-stable-model-report)
9. [The model at a glance](#9-the-model-at-a-glance)
10. [What this engine captures (and what it doesn't)](#10-what-this-engine-captures-and-what-it-doesnt)
11. [The aggregator](#11-the-aggregator)
12. [Engine 2 vs engine 1 — when to reach for which](#12-engine-2-vs-engine-1--when-to-reach-for-which)
13. [Where to go next](#13-where-to-go-next)

---

## 1. What you'll build

Three runnable scenarios over one small, self-contained domain:

| Scenario | Demonstrates | Key API |
| -------- | ------------ | ------- |
| `analyze_and_inspect` | Run the analyzer, query the model | `TomAnalyzer.analyzeBarrel`, `AnalysisResult` |
| `json_roundtrip` | Serialize to JSON and read it back | `JsonSerializer` / `JsonDeserializer` |
| `model_report` | Walk the model into a stable JSON report | the query API + a deterministic projection |

Everything is wired into one aggregator, `bin/run_example.dart`, which runs all
three and reports a pass/fail tally.

The recurring theme: **the model is just data.** Once you have an
`AnalysisResult`, you are holding an ordinary Dart object graph — no analyzer, no
live objects, no magic. You can query it, serialize it, diff it, or feed it to a
code generator.

---

## 2. Project layout

```
reflector_parser_introduction_sample/
  pubspec.yaml                 depends on tom_reflector (by path) + path
  analysis_options.yaml        package:lints/recommended.yaml
  sample_source/               THE INPUT — a tiny pure-Dart package, analyzed
    pubspec.yaml               (no dependencies; read as text, never run)
    lib/
      catalog.dart             the domain: classes, an enum, a generic, a func
  lib/
    catalog_analysis.dart      shared helpers: analyze, render types, build report
  example/
    analyze_and_inspect/
      main.dart                scenario 1 entry point
    json_roundtrip/
      main.dart                scenario 2 entry point
    model_report/
      main.dart                scenario 3 entry point
  bin/
    run_example.dart           aggregator: runs every scenario, tallies pass/fail
```

The single most important structural point: **`sample_source/` is input, not part
of this project.** It is a separate, dependency-free Dart package that exists only
to be *read* by the analyzer. It deliberately sits **outside `lib/`** so it is
never confused with this sample's own library code (which the analyzer does not
touch). The sample's real code lives in `lib/catalog_analysis.dart` and the three
`example/**/main.dart` entry points.

There are **no generated files** in this sample. Engine 2's parser mode produces
its model *in memory at runtime*; there is nothing to commit alongside the
source. (The sibling
[`reflector_reflection_introduction_sample`](../reflector_reflection_introduction_sample/README.md)
covers the *code-generation* mode, which does emit `*.r.dart`.)

---

## 3. Running it

From this directory:

```bash
dart pub get

# Run all three scenarios with a pass/fail tally:
dart run bin/run_example.dart

# …or run a single scenario directly:
dart run example/analyze_and_inspect/main.dart
dart run example/json_roundtrip/main.dart
dart run example/model_report/main.dart
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

## 4. The big idea: source in, data out

Engine 2 is a pipeline with three stages:

```
  Dart source            analyzer + mapper            pure object model
  ───────────            ─────────────────            ─────────────────
  sample_source/   ──►   TomAnalyzer.analyzeBarrel ──►   AnalysisResult
  lib/catalog.dart        (resolves & walks the         ├─ libraries
                           element model)               ├─ allClasses / allEnums
                                                         ├─ allFunctions
                                                         └─ query helpers
```

`TomAnalyzer.analyzeBarrel` takes two paths:

- **`barrelPath`** — the entry file to analyze (here, the package's
  `lib/catalog.dart`). The analyzer resolves it and every library the package
  owns.
- **`workspaceRoot`** — the package root, so the analyzer can read its
  `pubspec.yaml` and learn the package name.

It returns a `Future<AnalysisResult>`: the root of the model. From there the
`AnalysisResult` flattens every library's members into convenient queries —
`allClasses`, `allEnums`, `allFunctions`, `findClassesWithAnnotation`,
`annotationNames`, `getClassOrThrow` — so you rarely have to descend through
libraries by hand.

The crucial property is what `AnalysisResult` is *not*: it is not tied to the
analyzer, not tied to a running program, and not tied to the source files once
built. It is a tree of plain Dart objects. That is exactly why it can be
serialized (scenario 2) and projected into a report (scenario 3).

---

## 5. The source set

[`sample_source/lib/catalog.dart`](sample_source/lib/catalog.dart) is the domain
we analyze. It is ordinary, dependency-free Dart — chosen to exercise the parts
of the model this sample teaches:

```dart
/// Marks a class as a persistable entity.
class Entity {
  final String table;
  const Entity(this.table);
}

/// A product in the catalog.
@Entity('products')
class Product {
  final String sku;
  String name;
  double price;
  final List<String> tags;

  Product({required this.sku, this.name = '', this.price = 0.0,
           this.tags = const []});

  double discounted(double pct) => price * (1 - pct);
  String get label => '$name ($sku)';
}

/// Availability states for a product.
enum Availability { inStock, backordered, discontinued }

/// A generic repository contract.
abstract class Repository<T> {
  T? findById(String id);
  List<T> findAll();
}

int catalogVersion() => 3;
```

Five things to analyze: an annotation class (`Entity`), an annotated class with
mixed fields and a getter (`Product`), an enum (`Availability`), a generic
abstract contract (`Repository<T>`), and a top-level function (`catalogVersion`).
Small, but enough to show classes, enums, functions, type parameters, nullable
and generic field types, and annotations all flowing through the model.

---

## 6. Scenario 1 — analyze and inspect

[`example/analyze_and_inspect/main.dart`](example/analyze_and_inspect/main.dart)

The entry point to engine 2: analyze, then query.

```dart
final result = await analyzeCatalog(); // wraps TomAnalyzer.analyzeBarrel

result.rootPackage.name;                       // catalog_domain
result.errors.length;                          // 0
result.allClasses.map((c) => c.name);          // [Entity, Product, Repository]
result.allEnums.map((e) => e.name);            // [Availability]
result.allFunctions.map((f) => f.name);        // [catalogVersion]
```

Output:

```text
package   -> catalog_domain
errors    -> 0
classes   -> [Entity, Product, Repository]
enums     -> [Availability]
functions -> [catalogVersion]
```

Then drill into one class. `getClassOrThrow` is the by-name lookup; members are
plain typed lists:

```dart
final product = result.getClassOrThrow('Product');

product.isAbstract;                            // false
product.fields.map((f) => '${f.name}: ${renderType(f.type)}');
product.methods.map((m) => m.name);            // [discounted]
```

Output:

```text
Product.isAbstract -> false
Product fields     -> [sku: String, name: String, price: double, tags: List<String>, label: String]
Product methods    -> [discounted]
```

Note `tags: List<String>` — the field's generic type argument survives into the
model, recovered by `renderType` (a helper in `catalog_analysis.dart` that
collapses a structured `TypeReference` back into source-like text). Note too that
`label` — a *getter* — shows up under `fields`; [§10](#10-what-this-engine-captures-and-what-it-doesnt)
explains why.

Annotations are resolved **by name**, which is exactly what a code generator keys
on — "find every class marked `@Entity`":

```dart
product.annotations.map((a) => '@${a.name}');           // [@Entity]
result.findClassesWithAnnotation('Entity').map((c) => c.name); // [Product]
```

Output:

```text
Product annotations -> [@Entity]
@Entity classes     -> [Product]
```

And the generic contract keeps its type parameter:

```dart
result.getClassOrThrow('Repository').typeParameters.map((t) => t.name); // [T]
```

```text
Repository type params -> [T]
```

That last query — *find the classes carrying a marker annotation* — is the
single most common reason tools reach for engine 2. A serializer generator asks
"which classes are `@Serializable`?"; a DI container asks "which are
`@Injectable`?". The answer is one `findClassesWithAnnotation` call over a model
you built once.

---

## 7. Scenario 2 — the JSON round-trip

[`example/json_roundtrip/main.dart`](example/json_roundtrip/main.dart)

Because the model is pure data, it can be written to disk and re-read without
re-running the analyzer — the realistic "cache the analysis" workflow. This
scenario proves the round-trip preserves structure.

```dart
final original = await analyzeCatalog();

// Encode to a JSON string.
final json = JsonSerializer.encode(original);

// Persist, then read back from disk (build/ is gitignored).
final outFile = File(p.join('build', 'catalog.analysis.json'));
outFile.parent.createSync(recursive: true);
outFile.writeAsStringSync(json);
final restored = JsonDeserializer.decode(outFile.readAsStringSync());
```

Output:

```text
encoded JSON -> 40801 chars
classes   3 -> 3
enums     1 -> 1
functions 1 -> 1
Product fields  5 -> 5
Product methods 1 -> 1
Product @Entity preserved -> true
round-trip   -> identical structure
```

The counts on each side of the `->` are *before* and *after* the round-trip, and
they match: three classes in, three classes out; Product's five members and its
`@Entity` annotation all survive.

**How cycles survive.** The model is a graph, not a tree — a field points at its
declaring type, a type reference points at its resolved element, and those can
form cycles. `JsonSerializer` handles this by giving every element a stable **id**
and serializing cross-references *as ids* (`declaringTypeId`,
`resolvedElementId`, `mainSourceFileId`, …) rather than inlining the referenced
object. `JsonDeserializer` rebuilds the objects first, then re-links them by id.
The result round-trips safely no matter how tangled the references are. This is
the `IdGenerator` / id-reference design that `tom_reflector_model` is built
around.

**Stable structure vs volatile bytes.** The round-trip preserves *structure*, but
the raw JSON itself is **not** byte-stable across runs: `JsonSerializer.encode`
records a `timestamp`, absolute file `path`s, file `modified` times and content
hashes. That is faithful, but it means you should not diff two raw encodings and
expect equality. When you want a stable artifact, project the model down to just
its shape — which is precisely what scenario 3 does.

---

## 8. Scenario 3 — a stable model report

[`example/model_report/main.dart`](example/model_report/main.dart)

The canonical engine-2 deliverable: walk the model and emit a **deterministic**
JSON report. We first round-trip through JSON, so the report is demonstrably
built from *re-read* data — exactly as a downstream tool consuming a cached model
would work:

```dart
final analysed = await analyzeCatalog();
final model = JsonDeserializer.decode(JsonSerializer.encode(analysed));

final report = buildCatalogReport(model);          // projects + sorts
print(const JsonEncoder.withIndent('  ').convert(report));
```

`buildCatalogReport` (in `catalog_analysis.dart`) keeps only names, kinds and
members, drops every volatile field (ids, timestamps, paths, hashes), and **sorts
every collection** so the output bytes are identical on every run. The result:

```json
{
  "package": "catalog_domain",
  "annotationNames": [
    "Entity"
  ],
  "classes": [
    {
      "name": "Entity",
      "isAbstract": false,
      "fields": [
        { "name": "table", "type": "String", "isFinal": true }
      ],
      "methods": []
    },
    {
      "name": "Product",
      "isAbstract": false,
      "annotations": [ "Entity" ],
      "fields": [
        { "name": "label", "type": "String", "isFinal": false },
        { "name": "name", "type": "String", "isFinal": false },
        { "name": "price", "type": "double", "isFinal": false },
        { "name": "sku", "type": "String", "isFinal": true },
        { "name": "tags", "type": "List<String>", "isFinal": true }
      ],
      "methods": [
        { "name": "discounted", "returnType": "double", "parameters": ["pct"] }
      ]
    },
    {
      "name": "Repository",
      "isAbstract": true,
      "typeParameters": ["T"],
      "fields": [],
      "methods": [
        { "name": "findAll", "returnType": "List<T>", "parameters": [] },
        { "name": "findById", "returnType": "T?", "parameters": ["id"] }
      ]
    }
  ],
  "enums": [
    { "name": "Availability",
      "values": ["inStock", "backordered", "discontinued"] }
  ],
  "functions": [
    { "name": "catalogVersion", "returnType": "int" }
  ]
}
```

Everything the model captured is here in a form you could check into a repo and
diff against the next run: `Repository<T>` keeps its type parameter and its
`List<T>` / `T?` signatures; the enum keeps its values *in declaration order*;
`Product` keeps its `@Entity` marker. This projection is the heart of the JSON use
case — a code generator, an API-surface tracker, or a documentation index would
each build a report shaped like this and act on it.

---

## 9. The model at a glance

The objects you walk all come from `tom_reflector_model` (re-exported by
`tom_reflector`). The ones this sample touches:

| Type | What it is | Used here for |
| ---- | ---------- | ------------- |
| `AnalysisResult` | Root of the model; flattening queries | `allClasses`, `allEnums`, `getClassOrThrow`, `findClassesWithAnnotation` |
| `LibraryInfo` | One analyzed library | (reached via the `all*` queries) |
| `ClassInfo` | A class declaration | `name`, `isAbstract`, `fields`, `methods`, `typeParameters`, `annotations` |
| `EnumInfo` | An enum declaration | `name`, `values` |
| `FunctionInfo` | A top-level function | `name`, `returnType` |
| `FieldInfo` | A field (or accessor) | `name`, `type`, `isFinal` |
| `MethodInfo` | A method | `name`, `returnType`, `parameters` |
| `ParameterInfo` | A parameter | `name`, `type` |
| `TypeParameterInfo` | A generic parameter | `name`, `bound` |
| `TypeReference` | A reference to a type | `name`, `typeArguments`, `isNullable`, `isVoid` |
| `AnnotationInfo` | A resolved annotation | `name`, `qualifiedName` |

The serialization side adds `JsonSerializer` / `JsonDeserializer` (and YAML
equivalents), plus `IdGenerator` for the id-based references that make the graph
cycle-safe. The full inventory lives in the
[`tom_reflector_model` README](../../tom_reflector_model/README.md).

---

## 10. What this engine captures (and what it doesn't)

Being precise about the model's edges saves you surprises:

- **Annotations are recorded by name, not by argument value.** `@Entity('products')`
  becomes an `AnnotationInfo` with `name: 'Entity'` — the string `'products'` is
  **not** captured. This is deliberate and sufficient for the dominant use case
  (*"which elements carry this marker?"*). If you need argument values, that is a
  job for the code-generation path, not the parser model.
- **Getters surface as fields.** `Product.label` is a getter, but this analyzer
  version folds property accessors into `ClassInfo.fields` (a field with a getter
  and no setter) rather than populating a separate `getters` list. Read members
  through `fields` and treat the `isFinal` / accessor flags as the discriminator.
- **`errors` is part of the result.** A real analysis can surface diagnostics;
  `AnalysisResult.errors` holds them. Here it is empty (`errors -> 0`), which is
  your signal the source resolved cleanly.
- **Source positions are coarse.** Locations carry offsets, not fully resolved
  line/column numbers, in this version — fine for identity, not for pointing an
  editor at a glyph.

None of these are bugs to route around; they are the model's current shape. The
sample's report projects exactly what the model reliably provides.

---

## 11. The aggregator

[`bin/run_example.dart`](bin/run_example.dart) imports each scenario's `main()`
under a prefix, awaits them in turn, and counts failures — the same shape as every
sample in this toolkit, except that engine-2 scenarios are **asynchronous** (the
analyzer is async), so each `main()` returns a `Future` and is awaited:

```dart
typedef Scenario = ({String name, Future<void> Function() run});

for (final scenario in scenarios) {
  try {
    await scenario.run();
  } catch (e, st) {
    failures++;
    stderr.writeln('FAILED: ${scenario.name}: $e');
  }
}
```

Running the analyzer three times in one process (once per scenario) is safe —
each `analyzeCatalog()` builds its own context and returns an independent model.

---

## 12. Engine 2 vs engine 1 — when to reach for which

Both engines are "reflection", but they answer different questions:

| | Engine 1 — `tom_reflection` | Engine 2 — `tom_reflector` (this) |
| --- | --- | --- |
| When it runs | **Runtime**, on live objects | **Build time**, on source text |
| What you get | Mirrors: invoke / read / construct by name | A data model: classes, members, types |
| Output | `*.reflection.dart` (generated) | `AnalysisResult` (in memory; serializable) |
| Typical consumer | App code doing dynamic dispatch | Code generators, indexers, tools |
| Question it answers | "Call `greet` on *this object*." | "What is the *shape* of this code?" |

Reach for **engine 2** when you are building tooling — a serializer generator, a
documentation index, an API-surface diff, a dependency-injection wiring step —
that needs to reason about code structure *before* the program runs, and wants a
stable model it can cache and re-read. Reach for **engine 1** when running code
needs to invoke members it only knows by name.

They are not two versions of one thing; they are different technologies that
happen to share a repo. Keep their concepts (and their generated-file
conventions, `*.reflection.dart` vs `*.r.dart`) distinct.

---

## 13. Where to go next

- [`reflector_reflection_introduction_sample`](../reflector_reflection_introduction_sample/README.md)
  — engine 2's *other* mode: generate `*.r.dart` and consume the reflection at
  runtime.
- [`reflector_parser_advanced_sample`](../reflector_parser_advanced_sample/README.md)
  — a deeper dive into the model: type-argument resolution, mixins and
  extensions, cycle-safe id references, YAML round-trip.
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
