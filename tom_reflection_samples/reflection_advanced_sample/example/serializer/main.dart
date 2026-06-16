// Scenario 1 — a tiny reflection-driven serializer (the realistic use case).
//
// This is what runtime mirrors are *for*: write the (de)serialization logic
// once, against the mirror API, and it works for any annotated class without a
// hand-written `toMap`/`fromMap` per type.
//
//   toMap   — enumerate the class's stored fields (VariableMirror, non-static,
//             non-private) and read each with invokeGetter.
//   fromMap — construct an empty instance with newInstance, then write each
//             field back with invokeSetter.
//
// The derived getter `label` is intentionally skipped: it is a MethodMirror,
// not a VariableMirror, so it never enters the map — derived state is not
// persisted state.
import 'package:reflection_advanced_sample/domain.dart';
import 'package:tom_reflection/tom_reflection.dart';

import 'main.reflection.dart';

/// Serialize any annotated object to a `Map` by reading its stored fields.
Map<String, Object?> toMap(Object instance) {
  final mirror = advancedReflector.reflect(instance);
  final classMirror = mirror.type;
  final out = <String, Object?>{};
  for (final entry in classMirror.declarations.entries) {
    final decl = entry.value;
    if (decl is VariableMirror && !decl.isStatic && !decl.isPrivate) {
      out[entry.key] = mirror.invokeGetter(entry.key);
    }
  }
  return out;
}

/// Reconstruct an instance of [classMirror]'s type from a field map.
Object fromMap(ClassMirror classMirror, Map<String, Object?> data) {
  // The unnamed constructor is addressed by the empty string. Product's
  // constructor is all-optional, so no positional args are required.
  final instance = classMirror.newInstance('', const []);
  final mirror = advancedReflector.reflect(instance);
  for (final entry in data.entries) {
    mirror.invokeSetter(entry.key, entry.value);
  }
  return instance;
}

void main() {
  initializeReflection();

  final product = Product(sku: 'A-1', name: 'Widget', price: 9.5, stock: 12);

  // Grab the ClassMirror once; fromMap below rebuilds from the map + this type.
  final productClass = advancedReflector.reflect(product).type;

  final map = toMap(product);
  print('toMap   -> $map');
  // toMap   -> {sku: A-1, name: Widget, price: 9.5, stock: 12}

  // Round-trip: rebuild a fresh instance from the map alone.
  final clone = fromMap(productClass, map);
  print('fromMap -> $clone');
  // fromMap -> Product(A-1, Widget, $9.5, x12)

  // The derived getter was not serialized.
  print('label   -> ${(clone as Product).label}  (never in the map)');
  // label   -> Widget (A-1)  (never in the map)
}
