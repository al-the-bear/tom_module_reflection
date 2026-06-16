// Aggregator for the reflection introduction sample.
//
// Runs every scenario under `example/` in order, prints a banner per scenario,
// tallies pass/fail, and exits non-zero if any scenario throws. This is the
// smoke test the quest plan asks each sample to ship.
//
// Each scenario is an independent entry point with its own generated
// `main.reflection.dart`; here we import their `main()` functions under a
// prefix and call them in turn.
import 'dart:io';

import '../example/introspect/main.dart' as introspect;
import '../example/read_fields/main.dart' as read_fields;
import '../example/reflect_and_invoke/main.dart' as reflect_and_invoke;

/// A named scenario: its label and the `main()` to invoke.
typedef Scenario = ({String name, void Function() run});

final List<Scenario> scenarios = [
  (name: 'reflect_and_invoke', run: reflect_and_invoke.main),
  (name: 'read_fields', run: read_fields.main),
  (name: 'introspect', run: introspect.main),
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
