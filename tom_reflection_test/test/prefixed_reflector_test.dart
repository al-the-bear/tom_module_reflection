// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
// Uses a reflector which is accessed via a prefixed identifier.

library test_reflection.test.prefixed_reflector_test;

import 'package:tom_reflection/tom_reflection.dart';
import 'package:test/test.dart';
import 'prefixed_reflector_test.reflection.dart';

class Reflector extends Reflection {
  const Reflector()
    : super(
        instanceInvokeCapability,
        topLevelInvokeCapability,
        declarationsCapability,
        reflectedTypeCapability,
        libraryCapability,
      );
}

class C {
  static const reflector = Reflector();
}

@C.reflector
class D {
  int get getter => 24;
  set setter(int owtytrof) {}
}

void main() {
  initializeReflection();

  var classMirror = C.reflector.reflectType(D) as ClassMirror;
  test('Prefixed reflector type', () {
    expect(classMirror.reflectedType, D);
  });
}
