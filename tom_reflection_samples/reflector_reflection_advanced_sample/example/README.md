# reflector_reflection_advanced_sample — examples

> Part of the Tom Framework reflection toolkit — an original analyzer-based
> build-time reflection engine (BSD 3-Clause). See
> [`LICENSE`](../../../tom_reflector/LICENSE).

This tree is the **canonical home** for this sample's runnable scenarios — the
deep dive into engine-2's **codegen** variant over a real class hierarchy
(inheritance, mixins, interfaces, statics). The generator emits a committed
`*.r.dart` reflection file the scenarios consume at runtime. Each scenario is a
self-contained `main.dart` ending in a printed result with an inline
`// output` expectation.

| Scenario | Demonstrates |
|----------|--------------|
| [`inspect_hierarchy/`](inspect_hierarchy) | Read the shape of a class hierarchy out of generated reflection. |
| [`dispatch_and_relations/`](dispatch_and_relations) | Polymorphic dispatch, type relations, and the `isInstance` subtype gotcha. |
| [`serialize_roundtrip/`](serialize_roundtrip) | One generic serializer + reconstructor for the whole hierarchy. |

Run the full set (aggregator lives in `bin/`, not here) from the sample root:

```sh
dart run bin/run_example.dart
```

The aggregator imports every scenario's `main`, runs each in a `try/catch`,
prints a pass/fail tally, and exits non-zero if any scenario throws.

> Regenerate the committed `*.r.dart` with `dart run bin/generate.dart` if the
> domain in `lib/` changes — never hand-edit the generated file. The
> entry-point reachability/filter/coverage config surface is documented in the
> sample's [`README.md`](../README.md); runnable generation uses the barrel path.

## Where to go next

- This sample's tutorial: [`../README.md`](../README.md)
- All seven samples: [`../../README.md`](../../README.md)
- Codegen basics first:
  [`../../reflector_reflection_introduction_sample/`](../../reflector_reflection_introduction_sample)
- Parser model (no codegen):
  [`../../reflector_parser_advanced_sample/`](../../reflector_parser_advanced_sample)
