// Aggregator for the reflection capability sample.
//
// Runs every scenario under `example/` in order, prints a banner per scenario,
// tallies pass/fail, and exits non-zero if any scenario throws. This is the
// smoke test the quest plan asks each sample to ship.
//
// Each scenario is an independent entry point with its own generated
// `main.reflection.dart`; here we import their `main()` functions under a
// prefix and call them in turn.
import 'dart:io';

import '../example/minimal_vs_broad/main.dart' as minimal_vs_broad;
import '../example/missing_capability/main.dart' as missing_capability;
import '../example/pattern_capabilities/main.dart' as pattern_capabilities;
import '../example/use_all_capabilities/main.dart' as use_all_capabilities;

/// A named scenario: its label and the `main()` to invoke.
typedef Scenario = ({String name, void Function() run});

final List<Scenario> scenarios = [
  (name: 'minimal_vs_broad', run: minimal_vs_broad.main),
  (name: 'missing_capability', run: missing_capability.main),
  (name: 'pattern_capabilities', run: pattern_capabilities.main),
  (name: 'use_all_capabilities', run: use_all_capabilities.main),
];

void main() {
  var failures = 0;

  for (final scenario in scenarios) {
    stdout.writeln('\n=== ${scenario.name} ===');
    try {
      scenario.run();
    } catch (e, st) {
      failures++;
      stderr.writeln('FAILED: ${scenario.name}: $e');
      stderr.writeln(st);
    }
  }

  final passed = scenarios.length - failures;
  stdout.writeln('\n----------------------------------------');
  stdout
      .writeln('Scenarios: ${scenarios.length}  passed: $passed  failed: $failures');

  if (failures > 0) {
    exit(1);
  }
}
