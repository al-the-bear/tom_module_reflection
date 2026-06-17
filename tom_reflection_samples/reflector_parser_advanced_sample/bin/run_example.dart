// Aggregator for the engine-2 parser ADVANCED sample.
//
// Runs every scenario under `example/` in order, prints a banner per scenario,
// tallies pass/fail, and exits non-zero if any scenario throws. This is the
// smoke test the quest plan asks each sample to ship.
//
// Engine-2 scenarios are asynchronous (the analyzer is async), so each `main()`
// returns a `Future` and is awaited in turn.
import 'dart:io';

import '../example/api_surface/main.dart' as api_surface;
import '../example/resolve_types/main.dart' as resolve_types;
import '../example/yaml_roundtrip/main.dart' as yaml_roundtrip;

/// A named scenario: its label and the async `main()` to invoke.
typedef Scenario = ({String name, Future<void> Function() run});

final List<Scenario> scenarios = [
  (name: 'resolve_types', run: resolve_types.main),
  (name: 'yaml_roundtrip', run: yaml_roundtrip.main),
  (name: 'api_surface', run: api_surface.main),
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
