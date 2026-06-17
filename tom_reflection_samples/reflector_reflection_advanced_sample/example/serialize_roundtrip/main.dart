// Scenario 3 — one generic serializer + reconstructor for the whole hierarchy.
//
// This is the payoff of generating reflection over a class hierarchy: a SINGLE
// `serialize` / `deserialize` pair handles `User` and `Order` (and any future
// `@Persisted` subtype) with zero per-type code. It builds on the two lessons
// from the earlier scenarios:
//   * resolve the CONCRETE descriptor by runtime type (scenario 2's gotcha); and
//   * stored state includes INHERITED fields (scenario 1's flattening), so the
//     base class's `id` is serialized automatically.
//
// Reconstruction is the interesting half: not every stored field is a
// constructor parameter (`User.loginCount` is not). So we rebuild through the
// constructor for the parameters it accepts, then re-apply the leftover
// writable fields via `setProperty`.
import 'dart:convert';

import 'package:reflector_reflection_advanced_sample/store.r.dart';
import 'package:tom_reflector/tom_reflector.dart';

/// A field is "stored" if it holds real state: a final field (set once) or a
/// writable field (has a setter). A computed getter such as `kind` / `isoDate`
/// reflects as a field with neither, so it is skipped — derived, not stored.
bool _isStored(FieldDescriptor f) => f.isFinal || f.setInstance != null;

/// The descriptor for the instance's CONCRETE type (never an ancestor).
ClassDescriptor _concreteOf(Object instance) {
  final typeName = instance.runtimeType.toString();
  return reflectionApi.allClasses.firstWhere((c) => c.name == typeName);
}

/// Serialize ANY reflected entity, tagging the record with its type so the
/// reader knows which descriptor to reconstruct through.
Map<String, Object?> serialize(Object instance) {
  final cls = _concreteOf(instance);
  final out = <String, Object?>{'_type': cls.name};
  for (final entry in cls.fields.entries) {
    if (!_isStored(entry.value)) continue;
    out[entry.key] = cls.getProperty(instance, entry.key);
  }
  return out;
}

/// Rebuild an entity from a serialized record — through the constructor for the
/// parameters it accepts, then `setProperty` for the rest.
Object deserialize(Map<String, Object?> data) {
  final cls = reflectionApi.findClass(data['_type'] as String)!;
  final ctor = cls.constructors['new']!;
  final ctorParams = ctor.parameters.map((p) => p.name).toSet();

  final named = <Symbol, dynamic>{};
  for (final p in ctor.parameters) {
    if (data.containsKey(p.name)) named[Symbol(p.name)] = data[p.name];
  }
  final instance = cls.newInstance(constructorName: 'new', named: named)!;

  // Re-apply any stored field the constructor did not cover (e.g. loginCount).
  for (final entry in data.entries) {
    if (entry.key == '_type' || ctorParams.contains(entry.key)) continue;
    final field = cls.fields[entry.key];
    if (field != null && field.setInstance != null) {
      cls.setProperty(instance, entry.key, entry.value);
    }
  }
  return instance;
}

void main() {
  final userCls = reflectionApi.findClass('User')!;
  final orderCls = reflectionApi.findClass('Order')!;

  final user = userCls.newInstance(constructorName: 'new', named: {
    #id: 'U-1',
    #name: 'Ada',
    #email: 'ada@example.io',
    #epochMillis: 0,
  })!;
  userCls.invoke(user, 'recordLogin');
  userCls.invoke(user, 'recordLogin');
  userCls.invoke(user, 'recordLogin');

  final order = orderCls.newInstance(constructorName: 'new', named: {
    #id: 'O-9',
    #total: 42.5,
    #epochMillis: 0,
  })!;

  // One serializer, both types. Note `id` (inherited from Entity) is captured,
  // and the computed `kind` / `isoDate` getters are NOT.
  final encoder = JsonEncoder.withIndent('  ');
  final userJson = serialize(user);
  print('User serialized:');
  print(encoder.convert(userJson));
  // User serialized:
  // {
  //   "_type": "User",
  //   "name": "Ada",
  //   "email": "ada@example.io",
  //   "epochMillis": 0,
  //   "loginCount": 3,
  //   "id": "U-1"
  // }

  print('\nOrder serialized: ${serialize(order)}');
  // Order serialized: {_type: Order, total: 42.5, epochMillis: 0, id: O-9}

  // Round-trip: serialize -> deserialize -> serialize again. The leftover
  // writable field `loginCount` is restored even though it is not a
  // constructor parameter.
  final rebuiltUser = deserialize(userJson);
  print('\nrebuilt -> $rebuiltUser '
      'loginCount=${userCls.getProperty(rebuiltUser, 'loginCount')}');
  // rebuilt -> User(U-1) loginCount=3
  final roundTripsClean = serialize(rebuiltUser).toString() == userJson.toString();
  print('round-trip stable -> $roundTripsClean');
  // round-trip stable -> true

  // The codegen payoff for tooling: build a table registry from every
  // `@Persisted` class by reading its `table` static — no per-type code.
  final registry = <String, ClassDescriptor>{};
  for (final cls in reflectionApi.allClasses) {
    final isPersisted = cls.annotations.any((a) => a.name == 'Persisted');
    if (!isPersisted) continue;
    final table = cls.getStaticProperty('table') as String;
    registry[table] = cls;
  }
  print('\n@Persisted tables -> ${registry.keys.toList()}');
  // @Persisted tables -> [orders, users]

  // Look an entity up purely by its table name and reconstruct it.
  final fromTable = registry['orders']!;
  final rebuiltOrder = fromTable.newInstance(constructorName: 'new', named: {
    #id: 'O-42',
    #total: 7.0,
    #epochMillis: 0,
  })!;
  print('built via registry[orders] -> $rebuiltOrder '
      'kind=${fromTable.getProperty(rebuiltOrder, 'kind')}');
  // built via registry[orders] -> Order(O-42) kind=order
}
