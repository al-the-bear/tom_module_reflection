# reflection_capability_sample — examples

> Part of the Tom Framework reflection toolkit. Derived from the
> [`reflectable`](https://pub.dev/packages/reflectable) package
> (© 2015 the Dart project authors, BSD 3-Clause); Tom-specific refactoring,
> fixes and enhancements © 2026 Peter Nicolai Alexis Kyaw. See
> [`LICENSE`](../../../tom_reflection/LICENSE).

This tree is the **canonical home** for this sample's runnable scenarios —
how *capabilities* gate what the engine-1 generator emits. Each scenario is a
self-contained `main.dart` ending in a printed result with an inline
`// output` expectation (including the deliberate "missing capability" errors).

| Scenario | Demonstrates |
|----------|--------------|
| [`minimal_vs_broad/`](minimal_vs_broad) | Minimal vs broad capability sets and the generated-code difference. |
| [`missing_capability/`](missing_capability) | The missing-capability error, up close. |
| [`pattern_capabilities/`](pattern_capabilities) | A pattern capability and the two error types it reveals. |
| [`use_all_capabilities/`](use_all_capabilities) | The "everything" end of the dial — `useAllCapabilities`. |

Run the full set (aggregator lives in `bin/`, not here) from the sample root:

```sh
dart run bin/run_example.dart
```

The aggregator imports every scenario's `main`, runs each in a `try/catch`,
prints a pass/fail tally, and exits non-zero if any scenario throws.

## Where to go next

- This sample's tutorial: [`../README.md`](../README.md)
- All seven samples: [`../../README.md`](../../README.md)
- Start of the engine-1 path:
  [`../../reflection_introduction_sample/`](../../reflection_introduction_sample)
