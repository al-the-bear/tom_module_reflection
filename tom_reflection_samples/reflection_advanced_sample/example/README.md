# reflection_advanced_sample — examples

> Part of the Tom Framework reflection toolkit. **Derived from the
> [`reflectable`](https://pub.dev/packages/reflectable) package by the Dart team**
> ([`google/reflectable.dart`](https://github.com/google/reflectable.dart),
> "Copyright (c) 2015, Dart", BSD-3-Clause); Tom-specific refactoring, fixes and
> enhancements © 2024–2026 Peter Nicolai Alexis Kyaw, released under the same
> BSD-3-Clause terms. See
> [`LICENSE`](../../../tom_reflection/LICENSE).

This tree is the **canonical home** for this sample's runnable scenarios — the
deeper engine-1 (runtime-mirror) walkthrough. Each scenario is a self-contained
`main.dart` ending in a printed result with an inline `// output` expectation.

| Scenario | Demonstrates |
|----------|--------------|
| [`serializer/`](serializer) | A tiny reflection-driven serializer — the realistic use case. |
| [`static_members/`](static_members) | Invoke static members through the class mirror. |
| [`type_relations/`](type_relations) | Walk type relations: the superclass chain and superinterfaces. |
| [`generics_and_mixins/`](generics_and_mixins) | Reflect over generic types and mixed-in members. |

Run the full set (aggregator lives in `bin/`, not here) from the sample root:

```sh
dart run bin/run_example.dart
```

The aggregator imports every scenario's `main`, runs each in a `try/catch`,
prints a pass/fail tally, and exits non-zero if any scenario throws.

## Where to go next

- This sample's tutorial: [`../README.md`](../README.md)
- All seven samples: [`../../README.md`](../../README.md)
- Capability gating in depth:
  [`../../reflection_capability_sample/`](../../reflection_capability_sample)
