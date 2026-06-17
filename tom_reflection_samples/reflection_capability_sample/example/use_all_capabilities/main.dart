// Scenario 4 — the "everything" end of the dial.
//
// `allCapabilitiesReflector` lists the full capability set, so the same class
// supports every operation: invoke, enumerate declarations, walk type relations,
// AND construct via newInstance. Compare with scenario 1, where the *minimal*
// reflector threw NoSuchCapabilityError for declarations — this is the opposite
// extreme of the same dial.
//
// Relationship to `--useAllCapabilities`: the generator also offers a
// `--useAllCapabilities` flag that emits data for every capability *regardless*
// of what the reflector declares — the generator-side way to reach this same
// "emit everything" state without listing capabilities. That flag is exposed by
// the standalone CLI, not the build_runner builder this sample uses, so here we
// reach the full set the portable way: by declaring it. Either way the cost is
// the same — maximal generated code — which is exactly why a tight capability
// set is the default advice.
import 'package:reflection_capability_sample/domain.dart';

import 'main.reflection.dart';

void main() {
  initializeReflection();

  final profile = Profile(name: 'Grace', age: 37);
  final mirror = allCapabilitiesReflector.reflect(profile);

  // Invoke + read — basic instance reflection.
  print('invoke greet  -> ${mirror.invoke('greet', const [])}'); // -> Hi Grace
  print('read badge    -> ${mirror.invokeGetter('badge')}'); // -> Grace (37)

  // Enumerate declarations.
  final classMirror = mirror.type;
  final names = classMirror.declarations.keys.toList()..sort();
  print('declarations  -> $names');
  // declarations  -> [Profile, age, badge, greet, name]

  // Walk type relations.
  print('superclass    -> ${classMirror.superclass?.simpleName}');
  // superclass    -> Object

  // Construct a fresh instance by name, then populate it — only possible because
  // the full set includes newInstanceCapability.
  final built = classMirror.newInstance('', const []);
  final builtMirror = allCapabilitiesReflector.reflect(built);
  builtMirror.invokeSetter('name', 'Ada');
  builtMirror.invokeSetter('age', 36);
  print('newInstance   -> ${builtMirror.invokeGetter('badge')}');
  // newInstance   -> Ada (36)
}
