// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// File used to test reflection code generation.
/// Creates an `AllReflectorsMetaReflector` which may be used to reflect on
/// the set of reflectors themselves.
library test_reflection.test.reflectors_test;

@GlobalQuantifyCapability(r'.(A|B)$', Reflector3())
@GlobalQuantifyMetaCapability(P, Reflector4())
@GlobalQuantifyCapability(
  r'^tom_reflection.Reflection$',
  AllReflectorsMetaReflector(),
)
import 'package:tom_reflection/tom_reflection.dart';
import 'package:test/test.dart';
import 'reflectors_test.reflection.dart';

// ignore_for_file: omit_local_variable_types

/// Used to get access to all reflectors.
class AllReflectorsMetaReflector extends Reflection {
  const AllReflectorsMetaReflector()
    : super(subtypeQuantifyCapability, newInstanceCapability);

  Set<Reflection> get reflectors {
    var result = <Reflection>{};
    for (var classMirror in annotatedClasses) {
      if (classMirror.isAbstract) continue;
      var reflector =
          Reflection.getInstance(classMirror.reflectedType) as Reflection;
      result.add(reflector);
    }
    return result;
  }
}

class Reflector extends Reflection {
  const Reflector()
    : super(invokingCapability, declarationsCapability, libraryCapability);
}

class Reflector2 extends Reflection {
  const Reflector2()
    : super(invokingCapability, metadataCapability, libraryCapability);
}

class Reflector3 extends Reflection {
  const Reflector3() : super(invokingCapability);
}

class Reflector4 extends Reflection {
  const Reflector4() : super(declarationsCapability);
}

class ReflectorUpwardsClosed extends Reflection {
  const ReflectorUpwardsClosed()
    : super(
        superclassQuantifyCapability,
        invokingCapability,
        declarationsCapability,
        typeRelationsCapability,
      );
}

class ReflectorUpwardsClosedToA extends Reflection {
  const ReflectorUpwardsClosedToA()
    : super(
        const SuperclassQuantifyCapability(A),
        invokingCapability,
        declarationsCapability,
      );
}

class ReflectorUpwardsClosedUntilA extends Reflection {
  const ReflectorUpwardsClosedUntilA()
    : super(
        const SuperclassQuantifyCapability(A, excludeUpperBound: true),
        invokingCapability,
        declarationsCapability,
      );
}

@Reflector()
@Reflector2()
@P()
mixin class M1 {
  void foo() {}
  // ignore:prefer_typing_uninitialized_variables
  var field;
  static void staticFoo(x) {}
}

class P {
  const P();
}

@Reflector()
@Reflector2()
mixin class M2 {}

@Reflector()
@Reflector2()
mixin class M3 {}

@Reflector()
class A {
  void foo() {}
  Object? field;
  static void staticFoo(x) {}
  static void staticBar() {}
}

@Reflector()
@Reflector2()
class B extends A with M1 {}

@Reflector()
@Reflector2()
@ReflectorUpwardsClosed()
@ReflectorUpwardsClosedUntilA()
class C extends B with M2, M3 {}

@Reflector()
@Reflector2()
@ReflectorUpwardsClosed()
@ReflectorUpwardsClosedToA()
class D = A with M1;

void main() {
  initializeReflection();

  List<Reflection> reflectors = const AllReflectorsMetaReflector().reflectors
      .toList();

  test('Mixin, superclasses not included', () {
    expect(reflectors, const {
      Reflector(),
      Reflector2(),
      Reflector3(),
      Reflector4(),
      ReflectorUpwardsClosed(),
      ReflectorUpwardsClosedToA(),
      ReflectorUpwardsClosedUntilA(),
      AllReflectorsMetaReflector(),
    });
  });
}
