// Scenario 2 — polymorphic dispatch, type relations, and the one gotcha.
//
// THE GOTCHA: `ClassDescriptor.isInstance` is an `is` check, so it is
// subtype-inclusive — `Entity.isInstance(aUser)` and `Auditable.isInstance(aUser)`
// are BOTH true. A naive `allClasses.firstWhere((c) => c.isInstance(obj))` will
// happily return an ABSTRACT BASE or an INTERFACE descriptor (whichever the map
// iterates first) instead of the concrete class — and then property/method
// lookups fail because the base descriptor doesn't carry the leaf's members.
//
// THE FIX: resolve the concrete descriptor by the instance's RUNTIME TYPE, then
// use the relation helpers (`isSubclassOf`, `implementsInterface`, `hasMixin`)
// when you actually want the subtype-inclusive answer.
import 'package:reflector_reflection_advanced_sample/store.r.dart';
import 'package:tom_reflector/tom_reflector.dart';

const _base = 'package:reflector_reflection_advanced_sample/store.dart';
const entityQN = '$_base.Entity';
const auditableQN = '$_base.Auditable';
const timestampedQN = '$_base.Timestamped';

/// Resolve the descriptor for the instance's CONCRETE type, not any ancestor.
ClassDescriptor concreteOf(Object instance) {
  final typeName = instance.runtimeType.toString();
  return reflectionApi.allClasses.firstWhere((c) => c.name == typeName);
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
  final order = orderCls.newInstance(constructorName: 'new', named: {
    #id: 'O-9',
    #total: 42.5,
    #epochMillis: 0,
  })!;

  // The gotcha, made visible: how many descriptors claim `user` as an instance?
  final claimants =
      reflectionApi.allClasses.where((c) => c.isInstance(user)).map((c) => c.name);
  print('descriptors where isInstance(user) -> ${claimants.toList()}');
  // descriptors where isInstance(user) -> [Auditable, Entity, User]
  print('naive firstWhere(isInstance) -> '
      '${reflectionApi.allClasses.firstWhere((c) => c.isInstance(user)).name}  '
      '(WRONG: an ancestor)');
  // naive firstWhere(isInstance) -> Auditable  (WRONG: an ancestor)
  print('concreteOf(user)             -> ${concreteOf(user).name}  (correct)');
  // concreteOf(user)             -> User  (correct)

  // Type relations — these are the RIGHT tool when you DO want the
  // subtype-inclusive answer. Each walks the superclass chain.
  print('\nUser  isSubclassOf Entity       -> '
      '${reflectionApi.isSubclassOf(userCls.qualifiedName, entityQN)}');
  // User  isSubclassOf Entity       -> true
  print('User  implementsInterface Audit -> '
      '${reflectionApi.implementsInterface(userCls.qualifiedName, auditableQN)}');
  // User  implementsInterface Audit -> true
  print('Order implementsInterface Audit -> '
      '${reflectionApi.implementsInterface(orderCls.qualifiedName, auditableQN)}');
  // Order implementsInterface Audit -> false
  print('User  hasMixin Timestamped      -> '
      '${reflectionApi.hasMixin(userCls.qualifiedName, timestampedQN)}');
  // User  hasMixin Timestamped      -> true

  // Polymorphic dispatch: ONE loop drives both subtypes. `kind` and `isoDate`
  // are overridden / mixed-in getters; the reflection resolves them per object
  // with no `if (obj is User)` anywhere.
  print('');
  for (final instance in [user, order]) {
    final cls = concreteOf(instance);
    print('${cls.name}: kind=${cls.getProperty(instance, 'kind')} '
        'isoDate=${cls.getProperty(instance, 'isoDate')}');
  }
  // User: kind=user isoDate=1970-01-01T00:00:00.000Z
  // Order: kind=order isoDate=1970-01-01T00:00:00.000Z

  // Invoke an inherited concrete method (declared on Entity) through the leaf
  // descriptor — flattening means it is present on `User`.
  print('\nuser.baseFields() -> ${userCls.invoke(user, 'baseFields')}');
  // user.baseFields() -> {id: U-1, kind: user}

  // Invoke a mutator by name, then the interface method.
  userCls.invoke(user, 'recordLogin');
  userCls.invoke(user, 'recordLogin');
  print('after 2x recordLogin, loginCount -> '
      '${userCls.getProperty(user, 'loginCount')}');
  // after 2x recordLogin, loginCount -> 2
  print('user.auditFields() -> ${userCls.invoke(user, 'auditFields')}');
  // user.auditFields() -> {id: U-1, name: Ada}

  // Static members go through their own channel — never an instance.
  final entityCls = reflectionApi.findClass('Entity')!;
  print('\nEntity.schemaVersion       -> '
      '${entityCls.getStaticProperty('schemaVersion')}');
  // Entity.schemaVersion       -> 3
  entityCls.setStaticProperty('schemaVersion', 4);
  print('Entity.describe() after set -> '
      '${entityCls.invokeStatic('describe')}');
  // Entity.describe() after set -> entity schema v4
}
