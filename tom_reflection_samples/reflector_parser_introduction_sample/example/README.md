# reflector_parser_introduction_sample — examples

> Part of the Tom Framework reflection toolkit — an original analyzer-based
> build-time reflection engine (BSD 3-Clause). See
> [`LICENSE`](../../../tom_reflector/LICENSE).

This tree is the **canonical home** for this sample's runnable scenarios — the
engine-2 (build-time, analyzer-based) **parser** introduction. The parser mode
produces an in-memory `AnalysisResult` object model; there is no code
generation. Each scenario is a self-contained `main.dart` ending in a printed
result with an inline `// output` expectation.

| Scenario | Demonstrates |
|----------|--------------|
| [`analyze_and_inspect/`](analyze_and_inspect) | Analyze a source set, then query the resulting model. |
| [`json_roundtrip/`](json_roundtrip) | Serialize the model to JSON and read it back. |
| [`model_report/`](model_report) | Walk the model and emit a stable JSON report. |

Run the full set (aggregator lives in `bin/`, not here) from the sample root:

```sh
dart run bin/run_example.dart
```

The aggregator imports every scenario's `main`, runs each in a `try/catch`,
prints a pass/fail tally, and exits non-zero if any scenario throws.

## Where to go next

- This sample's tutorial: [`../README.md`](../README.md)
- All seven samples: [`../../README.md`](../../README.md)
- Deep parser/model dive:
  [`../../reflector_parser_advanced_sample/`](../../reflector_parser_advanced_sample)
- Codegen mode (`*.r.dart`) instead of the parser:
  [`../../reflector_reflection_introduction_sample/`](../../reflector_reflection_introduction_sample)
