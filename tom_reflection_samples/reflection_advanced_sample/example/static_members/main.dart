// Scenario 2 — invoke static members through the class mirror.
//
// `invoke` on a ClassMirror targets *static* methods (vs `invoke` on an
// InstanceMirror, which targets instance methods). `staticMembers` enumerates
// the static surface the same way `instanceMembers` does for instances.
import 'package:reflection_advanced_sample/domain.dart';

import 'main.reflection.dart';

void main() {
  initializeReflection();

  // We need a ClassMirror for Temperature. Reflecting any instance gives one.
  final classMirror = advancedReflector.reflect(Temperature(20)).type;

  // List the static methods the generator captured.
  print('staticMembers:');
  final staticNames = classMirror.staticMembers.keys.toList()..sort();
  for (final name in staticNames) {
    print('  $name');
  }
  // staticMembers:
  //   boiling
  //   freezing

  // Call the static factories by name; each returns a live Temperature.
  final freezing = classMirror.invoke('freezing', const []) as Temperature;
  final boiling = classMirror.invoke('boiling', const []) as Temperature;
  print('freezing()       -> $freezing'); // freezing()       -> 0.0C
  print('boiling()        -> $boiling'); // boiling()        -> 100.0C

  // Then reflect over the constructed instance to read an instance getter.
  final fahrenheit = advancedReflector.reflect(boiling).invokeGetter('fahrenheit');
  print('boiling.fahrenheit -> $fahrenheit'); // boiling.fahrenheit -> 212.0
}
