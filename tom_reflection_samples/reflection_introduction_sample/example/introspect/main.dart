// Scenario 3 — introspect a class through its mirror.
//
// From an instance mirror you can reach the `ClassMirror` (via `.type`) and
// enumerate its declarations: fields, methods, getters and constructors. This
// is "examine the program's own structure" — the introspection half of
// reflection.
import 'package:reflection_introduction_sample/domain.dart';
// The mirror kinds (MethodMirror, VariableMirror) live in the reflection
// library; domain.dart does not re-export them, so import it directly.
import 'package:tom_reflection/tom_reflection.dart';

import 'main.reflection.dart';

void main() {
  initializeReflection();

  final order = Order('B-200', User('Lin', 'lin@example.com'), 99.0);
  final mirror = introReflector.reflect(order);

  final classMirror = mirror.type;
  print('simpleName    -> ${classMirror.simpleName}'); // simpleName    -> Order
  print('qualifiedName -> ${classMirror.qualifiedName}'); // qualifiedName -> .Order

  // Enumerate declared members, classifying each by mirror kind.
  print('declarations:');
  final names = classMirror.declarations.keys.toList()..sort();
  for (final name in names) {
    final decl = classMirror.declarations[name];
    final kind = switch (decl) {
      MethodMirror m when m.isGetter => 'getter',
      MethodMirror m when m.isSetter => 'setter',
      MethodMirror m when m.isConstructor => 'constructor',
      MethodMirror() => 'method',
      VariableMirror() => 'field',
      _ => 'other',
    };
    print('  ${name.padRight(13)} $kind');
    // Order         constructor
    // amount        field
    // applyDiscount method
    // customer      field
    // id            field
    // summary       method
    // toString      method
  }
}
