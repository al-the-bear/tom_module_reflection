// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
// Imports the core file of this package and gives it a
// prefix, then proceeds to use the imported material.

library test_reflection.test.use_prefix_test;

import 'package:tom_reflection/tom_reflection.dart' as r;
import 'package:test/test.dart';
import 'use_prefix_test.reflection.dart';

class MyReflection extends r.Reflection {
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
