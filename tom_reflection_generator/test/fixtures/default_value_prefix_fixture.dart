/// Generator input fixture: every position in which a *type literal* can occur
/// inside an optional parameter's default value.
///
/// The generator re-emits default values as source text in a library that
/// imports nothing under the names the original library used, so every named
/// entity in the expression must be re-qualified with the generated import
/// prefix. A type literal that slips through unqualified is not a cosmetic
/// defect — it is an undefined name, and the generated library fails to
/// compile.
///
/// This file is **not** a test: it is the input `default_value_prefix_test.dart`
/// runs the real generator over. It has a `main()` because the pipeline only
/// generates for libraries with an entry point.
library;

import 'package:tom_reflection/tom_reflection.dart';

import 'default_value_prefix_lib.dart' as lib;

/// Minimal reflector — `newInstanceCapability` is what makes the generator
/// emit constructor default values at all.
class FixtureReflection extends Reflection {
  const FixtureReflection() : super(newInstanceCapability, typeCapability);
}

const fixtureReflection = FixtureReflection();

/// A class in the fixture's own library, used as a type literal.
class Local {
  const Local();
}

@fixtureReflection
class Defaults {
  Defaults.withTypeLiterals([
    this.bare = Local,
    this.mapValue = const <int, Type>{1: Local},
    this.mapKey = const <Type, int>{Local: 1},
    this.listElement = const <Type>[Local],
    this.setElement = const <Type>{Local},
    this.nested = const <int, List<Type>>{
      1: <Type>[Local],
    },
    this.imported = lib.Imported,
  ]);

  final Type bare;
  final Map<int, Type> mapValue;
  final Map<Type, int> mapKey;
  final List<Type> listElement;
  final Set<Type> setElement;
  final Map<int, List<Type>> nested;
  final Type imported;
}

void main() {}
