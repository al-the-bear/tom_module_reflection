// Aggregator for the engine-2 parser introduction sample.
//
// Runs every scenario under `example/` in order, prints a banner per scenario,
// tallies pass/fail, and exits non-zero if any scenario throws. This is the
// smoke test the quest plan asks each sample to ship.
//
// Engine-2 scenarios are asynchronous (the analyzer is async), so each `main()`
// returns a `Future` and is awaited in turn.
import 'dart:io';

import '../example/analyze_and_inspect/main.dart' as analyze_and_inspect;
import '../example/json_roundtrip/main.dart' as json_roundtrip;
import '../example/model_report/main.dart' as model_report;

/// A named scenario: its label and the async `main()` to invoke.
typedef Scenario = ({String name, Future<void> Function() run});

final List<Scenario> scenarios = [
  (name: 'analyze_and_inspect', run: analyze_and_inspect.main),
  (name: 'json_roundtrip', run: json_roundtrip.main),
  (name: 'model_report', run: model_report.main),
];

Future<void> main() async {
  var failures = 0;

  for (final scenario in scenarios) {
    stdout.writeln('\n=== ${scenario.name} ===');
    try {
      await scenario.run();
    } catch (e, st) {
      failures++;
      stderr.writeln('FAILED: ${scenario.name}: $e');
      stderr.writeln(st);
    }
  }

  final passed = scenarios.length - failures;
  stdout.writeln('\n----------------------------------------');
  stdout.writeln(
      'Scenarios: ${scenarios.length}  passed: $passed  failed: $failures');

  if (failures > 0) {
    exit(1);
  }
}
