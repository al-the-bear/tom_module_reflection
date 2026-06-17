// Scenario 4 — reflect over generics and mixins.
//
// `Note` mixes in the generic `Versioned<String>`, so its `payload` (T -> String)
// and `version` fields come from the mixin, not from `Note` itself. Mixed-in
// members are reachable through the same mirror API as the class's own members.
// `reflectedTypeCapability` additionally exposes `reflectedReturnType` for
// members whose return type the generator captured.
import 'package:reflection_advanced_sample/domain.dart';
import 'package:tom_reflection/tom_reflection.dart';

import 'main.reflection.dart';

void main() {
  initializeReflection();

  final note = Note('release notes');
  final mirror = advancedReflector.reflect(note);

  // Read and write fields contributed by the mixin, by name.
  mirror.invokeSetter('version', 3);
  mirror.invokeSetter('payload', 'v3 payload');
  print('version -> ${mirror.invokeGetter('version')}'); // version -> 3
  print('payload -> ${mirror.invokeGetter('payload')}'); // payload -> v3 payload
  print('note    -> $note'); // note    -> Note(release notes, v3)

  // Inspect the getters' reflected return types where the generator has them.
  // `version`'s getter returns a concrete `int`, so its return type is
  // reflected. `payload`'s getter returns the mixin's type variable `T`; a bare
  // type variable is not a reflectable concrete type, so `hasReflectedReturnType`
  // is false for it and the guard skips it — exactly the case the guard exists
  // for.
  final classMirror = mirror.type;
  print('reflected return types:');
  for (final name in ['version', 'payload']) {
    final member = classMirror.instanceMembers[name];
    if (member is MethodMirror && member.hasReflectedReturnType) {
      print('  $name -> ${member.reflectedReturnType}');
    }
  }
  // reflected return types:
  //   version -> int
}
