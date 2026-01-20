// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
// Uses `reflect`.

library test_reflection.test.reflect_test;

import 'package:tom_reflection/tom_reflection.dart';
import 'package:test/test.dart';
import 'reflect_test.reflection.dart';

class MyReflection extends Reflection {
  const MyReflection();
}

const myReflection = MyReflection();

@myReflection
class A {}

void main() {
  initializeReflection();

  test('reflect', () {
    // Expect that this does not throw.
    myReflection.reflect(A());
  });
}
