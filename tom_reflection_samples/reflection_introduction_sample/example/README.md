# reflection_introduction_sample — examples

> Part of the Tom Framework reflection toolkit. Derived from the
> [`reflectable`](https://pub.dev/packages/reflectable) package
> (© 2015 the Dart project authors, BSD 3-Clause); Tom-specific refactoring,
> fixes and enhancements © 2026 Peter Nicolai Alexis Kyaw. See
> [`LICENSE`](../../../tom_reflection/LICENSE).

This tree is the **canonical home** for this sample's runnable scenarios —
the engine-1 (runtime-mirror) introduction. Each scenario is a self-contained
`main.dart` whose meaningful work ends with a printed result and an inline
`// output` expectation, so every scenario doubles as a smoke test.

| Scenario | Demonstrates |
|----------|--------------|
| [`reflect_and_invoke/`](reflect_and_invoke) | Reflect over a live object and invoke members by name. |
| [`read_fields/`](read_fields) | Read and write fields by name through an instance mirror. |
| [`introspect/`](introspect) | Introspect a class through its class mirror. |

Run the full set (aggregator lives in `bin/`, not here) from the sample root:

```sh
dart run bin/run_example.dart
```

The aggregator imports every scenario's `main`, runs each in a `try/catch`,
prints a pass/fail tally, and exits non-zero if any scenario throws.

## Where to go next

- This sample's tutorial: [`../README.md`](../README.md)
- All seven samples: [`../../README.md`](../../README.md)
- Engine-2 (build-time, analyzer-based) samples start at
  [`../../reflector_parser_introduction_sample/`](../../reflector_parser_introduction_sample)
