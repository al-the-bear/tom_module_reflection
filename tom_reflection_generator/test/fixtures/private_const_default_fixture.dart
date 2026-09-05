/// Generator input fixture: an optional parameter whose default value is a
/// **private** const declared in the same library.
///
/// A private name cannot be written into the generated library — nothing there
/// is in its scope — so the only faithful rendering is the initializer the name
/// stands for, inlined. Dropping it instead is silent: the mirror still
/// compiles, it merely reports a constructor that has no default where the
/// source has one.
///
/// This file is **not** a test: it is the input `private_const_default_test.dart`
/// runs the real generator over. It has a `main()` because the pipeline only
/// generates for libraries with an entry point.
library;

import 'package:tom_reflection/tom_reflection.dart';

import 'default_value_prefix_lib.dart' as lib;

/// Minimal reflector — `newInstanceCapability` is what makes the generator
/// emit constructor default values at all.
class PrivateConstReflection extends Reflection {
  const PrivateConstReflection() : super(newInstanceCapability, typeCapability);
}

const privateConstReflection = PrivateConstReflection();

/// A scalar private const: the simplest case the emitter has to inline.
const int _defaultCount = 7;

/// A private const collection whose entries name types from a *second* library.
///
/// Shaped after Flutter's `PageTransitionsTheme({builders = _defaultBuilders})`,
/// where inlining the initializer is also what pulls the libraries its entries
/// come from into the generated file's imports. An emitter that drops the
/// default drops those imports with it, which is what makes the defect show up
/// as a diff in the import block rather than at the parameter.
const Map<String, lib.Imported> _defaultParts = <String, lib.Imported>{
  'imported': lib.Imported(),
};

@privateConstReflection
class PrivateDefaults {
  PrivateDefaults.withPrivateConsts([
    this.count = _defaultCount,
    this.parts = _defaultParts,
  ]);

  final int count;
  final Map<String, lib.Imported> parts;
}

void main() {}
