# reflector_parser_advanced_sample — examples

> Part of the Tom Framework reflection toolkit — an original analyzer-based
> build-time reflection engine (BSD 3-Clause). See
> [`LICENSE`](../../../tom_reflector/LICENSE).

This tree is the **canonical home** for this sample's runnable scenarios — the
deep dive into engine-2's **parser** object model. Each scenario is a
self-contained `main.dart` ending in a printed result with an inline
`// output` expectation.

| Scenario | Demonstrates |
|----------|--------------|
| [`resolve_types/`](resolve_types) | Resolve the hard parts: generics, bounds, mixins, extensions. |
| [`yaml_roundtrip/`](yaml_roundtrip) | Serialize the cyclic graph to YAML (ID-based refs) and read it back. |
| [`api_surface/`](api_surface) | Build a deterministic API-surface index — a real tool on top of the model. |

Run the full set (aggregator lives in `bin/`, not here) from the sample root:

```sh
dart run bin/run_example.dart
```

The aggregator imports every scenario's `main`, runs each in a `try/catch`,
prints a pass/fail tally, and exits non-zero if any scenario throws.

## Where to go next

- This sample's tutorial: [`../README.md`](../README.md)
- All seven samples: [`../../README.md`](../../README.md)
- Parser basics first:
  [`../../reflector_parser_introduction_sample/`](../../reflector_parser_introduction_sample)
- Codegen mode (`*.r.dart`):
  [`../../reflector_reflection_advanced_sample/`](../../reflector_reflection_advanced_sample)
