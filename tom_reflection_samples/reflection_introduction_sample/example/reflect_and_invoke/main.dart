// Scenario 1 — reflect over a live object and invoke members by name.
//
// The heart of runtime reflection: given an instance you did not know about at
// compile time, obtain a mirror and call its methods / getters by string name.
//
// This file is an *entry point*: it has a `main()` and imports its generated
// `main.reflection.dart`. The generator scans the import graph from here, finds
// the `@introReflector` classes in `domain.dart`, and emits the mirror data.
import 'package:reflection_introduction_sample/domain.dart';

import 'main.reflection.dart';

void main() {
  // REQUIRED once before any reflection call: wires the generated data in.
  initializeReflection();

  final user = User('Ada', 'ada@example.com');

  // Obtain an InstanceMirror for the live object.
  final mirror = introReflector.reflect(user);

  // Invoke a method by name — no static reference to `greet` here.
  final greeting = mirror.invoke('greet', []);
  print('invoke greet()      -> $greeting'); // invoke greet()      -> Hi, I am Ada

  // Invoking a mutating method changes the real object.
  print('loginCount before   -> ${user.loginCount}'); // loginCount before   -> 0
  mirror.invoke('recordLogin', []);
  mirror.invoke('recordLogin', []);
  print('loginCount after    -> ${user.loginCount}'); // loginCount after    -> 2

  // A getter is read with `invokeGetter` (not `invoke`, which is for methods).
  final active = mirror.invokeGetter('isActive');
  print('invokeGetter active -> $active'); // invokeGetter active -> true

  // Reflection sees the mutated state, because the mirror wraps the instance.
  print('reflected greeting  -> ${mirror.invoke('greet', [])}'); // reflected greeting  -> Hi, I am Ada
}
