// Aggregator entry point — runs every scenario and reports a pass/fail tally.
//
// Each scenario is the `main` of an `example/<name>/main.dart` file, imported
// here. Running this one binary exercises the whole sample; a non-zero exit
// code means at least one scenario threw. The scenarios are synchronous (the
// generated reflection is in-memory data — there is no analyzer at runtime).
import 'dart:io';

import '../example/dispatch_and_relations/main.dart' as dispatch_and_relations;
import '../example/inspect_hierarchy/main.dart' as inspect_hierarchy;
import '../example/serialize_roundtrip/main.dart' as serialize_roundtrip;

typedef Scenario = ({String name, void Function() run});

void main() {
  final scenarios = <Scenario>[
    (name: 'inspect_hierarchy', run: inspect_hierarchy.main),
    (name: 'dispatch_and_relations', run: dispatch_and_relations.main),
    (name: 'serialize_roundtrip', run: serialize_roundtrip.main),
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
