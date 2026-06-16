// Scenario 2 — the missing-capability error, up close.
//
// `declOnlyReflector` has declarations + instance invoke, but NO type
// relations. Two distinct ways to hit NoSuchCapabilityError:
//   1. ask for an operation the reflector did not enable (`.superclass`), and
//   2. try to reflect an object whose class no reflector covers.
// The first names the capability you forgot; the second tells you the class is
// out of scope.
import 'package:reflection_capability_sample/domain.dart';
import 'package:tom_reflection/tom_reflection.dart';

import 'main.reflection.dart';

void main() {
  initializeReflection();

  final widget = const Widget('btn');
  final mirror = declOnlyReflector.reflect(widget);

  // The capabilities it DOES have work normally.
  print('invoke render      -> ${mirror.invoke('render', const [])}');
  // invoke render      -> <btn/>
  final decls = mirror.type.declarations.keys.toList()..sort();
  print('declarations       -> $decls');
  // declarations       -> [id, render]

  // 1. A capability it did NOT ask for: type relations. The error message names
  //    the missing capability, which is the fastest way to diagnose it.
  try {
    mirror.type.superclass;
    print('superclass         -> (unexpected success)');
  } on NoSuchCapabilityError catch (e) {
    final mentions = e.toString().toLowerCase().contains('typerelations');
    print('superclass         -> NoSuchCapabilityError '
        '(names typeRelations: $mentions)');
    // superclass         -> NoSuchCapabilityError (names typeRelations: true)
  }

  // 2. An object outside every reflector's scope. `canReflect` is the cheap
  //    boolean pre-check; `reflect` itself throws.
  print('canReflect(Unregistered) -> '
      '${declOnlyReflector.canReflect(const Unregistered())}');
  // canReflect(Unregistered) -> false
  try {
    declOnlyReflector.reflect(const Unregistered());
    print('reflect Unregistered     -> (unexpected success)');
  } on NoSuchCapabilityError {
    print('reflect Unregistered     -> NoSuchCapabilityError (class not covered)');
    // reflect Unregistered     -> NoSuchCapabilityError (class not covered)
  }
}
