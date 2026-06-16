# reflector_reflection_introduction_sample — examples

> Part of the Tom Framework reflection toolkit — an original analyzer-based
> build-time reflection engine (BSD 3-Clause). See
> [`LICENSE`](../../../tom_reflector/LICENSE).

This tree is the **canonical home** for this sample's runnable scenarios — the
engine-2 (build-time, analyzer-based) **codegen** introduction. The generator
emits a committed `*.r.dart` reflection file that the scenarios consume at
runtime. Each scenario is a self-contained `main.dart` ending in a printed
result with an inline `// output` expectation.

| Scenario | Demonstrates |
|----------|--------------|
| [`inspect_generated/`](inspect_generated) | Load the generated reflection and query its shape. |
| [`invoke_dynamically/`](invoke_dynamically) | Drive live objects entirely through the generated reflection. |
| [`serialize_with_reflection/`](serialize_with_reflection) | One generic serializer over every `@Entity` type — zero per-class code. |

Run the full set (aggregator lives in `bin/`, not here) from the sample root:

```sh
dart run bin/run_example.dart
```

The aggregator imports every scenario's `main`, runs each in a `try/catch`,
prints a pass/fail tally, and exits non-zero if any scenario throws.

> Regenerate the committed `*.r.dart` with `dart run bin/generate.dart` if the
> domain in `lib/` changes — never hand-edit the generated file.

## Where to go next

- This sample's tutorial: [`../README.md`](../README.md)
- All seven samples: [`../../README.md`](../../README.md)
- Deeper codegen dive (hierarchies, filters, coverage config):
  [`../../reflector_reflection_advanced_sample/`](../../reflector_reflection_advanced_sample)
- Parser mode (no codegen) instead:
  [`../../reflector_parser_introduction_sample/`](../../reflector_parser_introduction_sample)
