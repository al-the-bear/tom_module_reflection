// Aggregator entry point — runs every scenario and reports a pass/fail tally.
//
// Each scenario is the `main` of an `example/<name>/main.dart` file, imported
// here. Running this one binary exercises the whole sample; a non-zero exit
// code means at least one scenario threw.
import 'dart:io';

import '../example/inspect_generated/main.dart' as inspect_generated;
import '../example/invoke_dynamically/main.dart' as invoke_dynamically;
import '../example/serialize_with_reflection/main.dart' as serialize_with_reflection;

typedef Scenario = ({String name, void Function() run});

void main() {
  final scenarios = <Scenario>[
    (name: 'inspect_generated', run: inspect_generated.main),
    (name: 'invoke_dynamically', run: invoke_dynamically.main),
    (name: 'serialize_with_reflection', run: serialize_with_reflection.main),
  ];

  var passed = 0;
  final failures = <String>[];
  for (final scenario in scenarios) {
    stdout.writeln('\n=== ${scenario.name} ===');
    try {
      scenario.run();
      passed++;
    } catch (e, st) {
      failures.add(scenario.name);
      stdout.writeln('  FAILED: $e\n$st');
    }
  }

  stdout.writeln('\n--- $passed/${scenarios.length} scenarios passed ---');
  if (failures.isNotEmpty) {
    stdout.writeln('failed: ${failures.join(', ')}');
    exit(1);
  }
}
