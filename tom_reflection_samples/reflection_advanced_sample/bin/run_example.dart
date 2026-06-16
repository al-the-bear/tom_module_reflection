// Aggregator for the reflection advanced sample.
//
// Runs every scenario under `example/` in order, prints a banner per scenario,
// tallies pass/fail, and exits non-zero if any scenario throws. This is the
// smoke test the quest plan asks each sample to ship.
//
// Each scenario is an independent entry point with its own generated
// `main.reflection.dart`; here we import their `main()` functions under a
// prefix and call them in turn.
import 'dart:io';

import '../example/generics_and_mixins/main.dart' as generics_and_mixins;
import '../example/serializer/main.dart' as serializer;
import '../example/static_members/main.dart' as static_members;
import '../example/type_relations/main.dart' as type_relations;

/// A named scenario: its label and the `main()` to invoke.
typedef Scenario = ({String name, void Function() run});

final List<Scenario> scenarios = [
  (name: 'serializer', run: serializer.main),
  (name: 'static_members', run: static_members.main),
  (name: 'type_relations', run: type_relations.main),
  (name: 'generics_and_mixins', run: generics_and_mixins.main),
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
