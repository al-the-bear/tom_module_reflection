// Scenario 3 — one generic serializer, every @Entity type, zero per-class code.
//
// This is the reason you generate reflection. `toMap` below works for `Product`
// and `Warehouse` (and any future @Entity) without a single type-specific line:
// it discovers the class descriptor from the live instance, reads the stored
// fields, and emits a map. A hand-written `toJson` per class is exactly the
// boilerplate the generated reflection replaces.
import 'dart:convert';

import 'package:reflector_reflection_introduction_sample/catalog.r.dart';
import 'package:tom_reflector/tom_reflector.dart';

/// A field is "stored" if it holds real state we want to serialize: a final
/// field (set once, read-only) or a mutable field (has a setter). A getter such
/// as `Product.label` reflects as a field with neither a setter nor `isFinal`,
/// so it is computed, not stored — and we skip it.
bool _isStored(FieldDescriptor f) => f.isFinal || f.setInstance != null;

/// Serialize ANY reflected instance to a map, driven purely by descriptors.
Map<String, Object?> toMap(Object instance) {
  // Find the descriptor whose generated type-check matches this instance.
  final cls = reflectionApi.allClasses.firstWhere((c) => c.isInstance(instance));
  final result = <String, Object?>{};
  for (final entry in cls.fields.entries) {
    if (!_isStored(entry.value)) continue;
    result[entry.key] = cls.getProperty(instance, entry.key);
  }
  return result;
}

void main() {
  final product = reflectionApi.findClass('Product')!;
  final warehouse = reflectionApi.findClass('Warehouse')!;

  // Build instances reflectively — still no direct constructor calls.
  final p = product.newInstance(
    constructorName: 'new',
    named: {#sku: 'A-100', #name: 'Widget', #price: 19.99, #stock: 7},
  )!;
  final w = warehouse.newInstance(
    constructorName: 'new',
    positional: ['WH-1'],
    named: {#capacity: 250},
  )!;

  // The SAME toMap handles both types.
  final encoder = JsonEncoder.withIndent('  ');
  print('Product as JSON:');
  print(encoder.convert(toMap(p)));
  // Product as JSON:
  // {
  //   "sku": "A-100",
  //   "name": "Widget",
  //   "price": 19.99,
  //   "stock": 7
  // }

  print('Warehouse as JSON:');
  print(encoder.convert(toMap(w)));
  // Warehouse as JSON:
  // {
  //   "code": "WH-1",
  //   "capacity": 250
  // }

  // Note the computed getters never appear: Product.label and Warehouse.isFull
  // are filtered out by `_isStored`.
  print('Product stored fields -> '
      '${product.fields.values.where(_isStored).map((f) => f.name).toList()}');
  // Product stored fields -> [sku, name, price, stock]
}
