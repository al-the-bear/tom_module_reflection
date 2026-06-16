# Tom Reflection — Samples

> Part of the Tom Framework reflection toolkit. These samples exercise both
> reflection engines; the `reflection_*` samples use the
> [`reflectable`](https://pub.dev/packages/reflectable)-derived engine 1, the
> `reflector_*` samples use the original analyzer-based engine 2. See each
> sample's `LICENSE`/attribution and the repo [`README`](../README.md).

Seven runnable sample projects with long-form tutorials, ordered beginner →
advanced. Engine 1 (runtime mirrors) first, then engine 2 (build-time model).

| Sample | Engine | Demonstrates |
|--------|--------|--------------|
| [`reflection_introduction_sample`](reflection_introduction_sample/README.md) | 1 | Annotate → generate → reflect → invoke; read a getter. |
| [`reflection_advanced_sample`](reflection_advanced_sample/README.md) | 1 | Declarations, `newInstance`, static members, type relations, generics & mixins. |
| [`reflection_capability_sample`](reflection_capability_sample/README.md) | 1 | How capabilities gate generated code; minimal vs `useAllCapabilities`; pattern capabilities. |
| [`reflector_parser_introduction_sample`](reflector_parser_introduction_sample/README.md) | 2 | Analyze sources → `AnalysisResult` → JSON round-trip → walk the model. |
| [`reflector_reflection_introduction_sample`](reflector_reflection_introduction_sample/README.md) | 2 | Generate `*.r.dart` and consume the reflection at runtime. |
| [`reflector_parser_advanced_sample`](reflector_parser_advanced_sample/README.md) | 2 | Deep model dive: type-argument resolution, annotations, mixins/extensions, cycle-safe IDs, YAML. |
| [`reflector_reflection_advanced_sample`](reflector_reflection_advanced_sample/README.md) | 2 | Entry-point reachability with filters, transitive resolution, coverage config. |

Each sample's `example/README.md` indexes its runnable scenarios; run the whole
set from a sample root with `dart run bin/run_example.dart`. The engine packages
are one hop up: engine 1 → [`tom_reflection`](../tom_reflection/README.md) /
[`tom_reflection_generator`](../tom_reflection_generator/README.md), engine 2 →
[`tom_reflector`](../tom_reflector/README.md) /
[`tom_reflector_model`](../tom_reflector_model/README.md).

## Sample project layout

Each sample is a standalone `publish_to: none` Dart project that follows the
same shape (mirroring the D4rt sample exemplar):

```
<sample_name>/
  pubspec.yaml            # deps on the relevant reflection package(s)
  analysis_options.yaml   # package:lints/recommended.yaml
  README.md               # 10–15 page tutorial (added with the scenarios)
  bin/run_example.dart    # aggregator entry: runs every scenario, tallies pass/fail
  example/<scenario>/…    # one sub-dir per scenario, each with its own main.dart
```

Engine-1 samples depend on the published `tom_reflection` (`^1.0.1`) plus the
`tom_reflection_generator` (`^1.1.1`) build step; engine-2 samples depend on the
in-workspace `tom_reflector` by path.

> **Status:** all seven sub-projects are **built out** — each resolves with
> `dart pub get`, ships a long-form tutorial `README.md`, an `example/` tree of
> runnable scenarios with its own index `README.md`, and a working
> `bin/run_example.dart` aggregator (pass/fail tally, non-zero exit). Smoke-test
> any sample with `dart run bin/run_example.dart` from its root.
