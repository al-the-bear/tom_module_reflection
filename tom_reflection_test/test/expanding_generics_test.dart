// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
// Checks that the occurrence of an expanding generic type (where
// class `C` takes one type argument `X` and uses `C<C<X>>` as a
// type annotation.

library test_reflection.test.expanding_generics_test;

import 'package:tom_reflection/tom_reflection.dart';
import 'package:test/test.dart';
import 'expanding_generics_test.reflection.dart';

class Reflector extends Reflection {
  const Reflector() : super(typeCapability);
}

const reflector = Reflector();

@reflector
class C<X> {
  C<C<X>>? get boom => null;
}

class Typer<X> {
  Type get type => X;
}

// ignore:non_constant_identifier_names
final Type COfInt = Typer<C<int>>().type;

void runTest(String message, ClassMirror classMirror) {
  test('Obtain mirror for expanding generic $message', () {
    expect(classMirror, isNotNull);
    expect(classMirror.hasReflectedType, true);
    expect(classMirror.reflectedType, COfInt);
  });
}

void main() {
  initializeReflection();

  test('Reject reflection directly on instantiated generic class', () {
    expect(reflector.canReflectType(COfInt), false);
  });
  var instanceMirror = reflector.reflect(C<int>());
  runTest('using `reflect`, then `type`.', instanceMirror.type);
}
