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
| `reflection_introduction_sample` | 1 | Annotate → generate → reflect → invoke; read a getter. |
| `reflection_advanced_sample` | 1 | Declarations, `newInstance`, static members, type relations, generics & mixins. |
| `reflection_capability_sample` | 1 | How capabilities gate generated code; minimal vs `useAllCapabilities`; pattern capabilities. |
| `reflector_parser_introduction_sample` | 2 | Analyze sources → `AnalysisResult` → JSON round-trip → walk the model. |
| `reflector_reflection_introduction_sample` | 2 | Generate `*.r.dart` and consume the reflection at runtime. |
| `reflector_parser_advanced_sample` | 2 | Deep model dive: type-argument resolution, annotations, mixins/extensions, cycle-safe IDs, YAML. |
| `reflector_reflection_advanced_sample` | 2 | Entry-point reachability with filters, transitive resolution, coverage config. |

> **Status:** scaffolding in progress. The sample sub-projects and their
> tutorials are built out per the quest plan
> (`readme_and_example_plan.md`, steps 7–14); this index is filled in at step 7.
