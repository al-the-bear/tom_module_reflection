// Scenario 3 — walk type relations: superclass chain and superinterfaces.
//
// `typeRelationsCapability` exposes `.superclass` and `.superinterfaces`;
// `superclassQuantifyCapability` lets the chain continue all the way up to
// `Object` (whose own superclass is null). Only *annotated* interfaces appear
// in `superinterfaces` — that is why `Drawable` carries the reflector.
import 'package:reflection_advanced_sample/domain.dart';

import 'main.reflection.dart';

void main() {
  initializeReflection();

  final circle = Circle(2);
  final classMirror = advancedReflector.reflect(circle).type;

  // Climb the superclass chain: Circle -> Shape -> Object -> (null).
  print('superclass chain:');
  var current = classMirror.superclass;
  while (current != null) {
    print('  ${current.simpleName}');
    current = current.superclass;
  }
  // superclass chain:
  //   Shape
  //   Object

  // Superinterfaces lists only the annotated interfaces Circle implements.
  print('superinterfaces:');
  for (final iface in classMirror.superinterfaces) {
    print('  ${iface.simpleName}');
  }
  // superinterfaces:
  //   Drawable
}
