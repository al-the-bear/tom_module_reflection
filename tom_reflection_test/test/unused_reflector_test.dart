// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
// Defines a reflector that is never used as a reflector; causes a
// warning, but not an error.

library test_reflection.test.unused_reflector_test;

import 'package:tom_reflection/tom_reflection.dart';
import 'package:test/test.dart';
import 'unused_reflector_test.reflection.dart';

class Reflector extends Reflection {
  const Reflector() : super(invokingCapability);
}

const reflector = Reflector();

Matcher throwsNoCapability = throwsA(
  const TypeMatcher<NoSuchCapabilityError>(),
);

void main() {
  initializeReflection();

  test('Unused reflector', () {
    expect(() => reflector.libraries, throwsNoCapability);
    expect(reflector.annotatedClasses, <ClassMirror>[]);
  });
}
