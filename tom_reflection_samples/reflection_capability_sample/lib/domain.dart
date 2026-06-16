// The shared domain for the reflection CAPABILITY sample.
//
// Capabilities are the dial that controls how much mirror data the generator
// emits — and therefore what you may do at runtime. This domain declares four
// reflectors with deliberately different capability sets, one per scenario,
// so each scenario can show a different facet of how capabilities gate
// reflection:
//
//   minimalReflector / broadReflector → minimal vs broad (scenario 1)
//   declOnlyReflector                 → the missing-capability error (scenario 2)
//   gettersOnlyReflector              → a pattern capability (scenario 3)
//   allCapabilitiesReflector          → the "everything" end of the dial
//                                        (scenario 4)
library;

import 'package:tom_reflection/tom_reflection.dart';

// ---------------------------------------------------------------------------
// Scenario 1 — minimal vs broad.
// `Account` carries BOTH reflectors. `minimalReflector` grants only instance
// invocation; `broadReflector` adds declarations + type relations + metadata.
// Same class, two windows of different width onto it.
// ---------------------------------------------------------------------------

/// The narrowest useful reflector: invoke instance members by name, nothing
/// else. No `declarations`, no type relations.
class MinimalReflector extends Reflection {
  const MinimalReflector() : super(instanceInvokeCapability);
}

const minimalReflector = MinimalReflector();

/// A broad reflector: invoke (instance + static), enumerate declarations, walk
/// type relations, read metadata, follow the superclass chain to Object.
class BroadReflector extends Reflection {
  const BroadReflector()
      : super(
          invokingCapability,
          declarationsCapability,
          typeRelationsCapability,
          metadataCapability,
          superclassQuantifyCapability,
        );
}

const broadReflector = BroadReflector();

@minimalReflector
@broadReflector
class Account {
  String owner;
  double balance;

  Account(this.owner, this.balance);

  double deposit(double amount) => balance += amount;
  String get summary => '$owner: \$$balance';
}

// ---------------------------------------------------------------------------
// Scenario 2 — the missing-capability error.
// `declOnlyReflector` has declarations + instance invoke but NO type relations,
// so reading `.superclass` / `.superinterfaces` throws NoSuchCapabilityError —
// and the message names the capability you forgot.
// ---------------------------------------------------------------------------

class DeclOnlyReflector extends Reflection {
  const DeclOnlyReflector()
      : super(declarationsCapability, instanceInvokeCapability);
}

const declOnlyReflector = DeclOnlyReflector();

@declOnlyReflector
class Widget {
  final String id;
  const Widget(this.id);
  String render() => '<$id/>';
}

/// Deliberately NOT annotated — reflecting an instance of it is the other way
/// to trip NoSuchCapabilityError (the class is outside every reflector's scope).
class Unregistered {
  const Unregistered();
}

// ---------------------------------------------------------------------------
// Scenario 3 — a pattern capability.
// `InstanceInvokeCapability('^get')` covers only members whose name starts with
// "get". Matching members invoke fine; a non-matching member is present but not
// covered, so it throws ReflectionNoSuchMethodError (NOT NoSuchCapabilityError).
// ---------------------------------------------------------------------------

class GettersOnlyReflector extends Reflection {
  const GettersOnlyReflector() : super(const InstanceInvokeCapability('^get'));
}

const gettersOnlyReflector = GettersOnlyReflector();

@gettersOnlyReflector
class Sensor {
  final int _raw;
  Sensor(this._raw);

  int get getRaw => _raw; // name matches ^get → covered
  int get getScaled => _raw * 2; // matches ^get → covered
  int compute() => _raw + 1; // does NOT match ^get → not covered
}

// ---------------------------------------------------------------------------
// Scenario 4 — the "everything" end of the dial.
// `allCapabilitiesReflector` lists the full capability set, so it can do
// everything the API offers: invoke, enumerate, walk relations, read metadata,
// AND construct via newInstance. This is the opposite extreme from
// `minimalReflector` (scenario 1). It is also the capability-set equivalent of
// the generator's `--useAllCapabilities` flag — see the README.
// ---------------------------------------------------------------------------

class AllCapabilitiesReflector extends Reflection {
  const AllCapabilitiesReflector()
      : super(
          invokingCapability,
          declarationsCapability,
          typeRelationsCapability,
          superclassQuantifyCapability,
          metadataCapability,
          newInstanceCapability,
          reflectedTypeCapability,
        );
}

const allCapabilitiesReflector = AllCapabilitiesReflector();

@allCapabilitiesReflector
class Profile {
  String name;
  int age;

  Profile({this.name = '', this.age = 0});

  String greet() => 'Hi $name';
  String get badge => '$name ($age)';
}
