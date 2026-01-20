// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
// Uses 'reflect' across file boundaries.  Main file of program.

library test_reflection.test.three_files_test;

import 'package:test/test.dart';
import 'three_files_dir/three_files_aux.dart';
import 'three_files_meta.dart';
import 'three_files_test.reflection.dart';

@myReflection
class A {}

void main() {
  initializeReflection();

  test('reflect local', () {
    // Expecting that this does not throw.
    myReflection.reflect(A());
  });
  test('reflect imported', () {
    // Expecting that this does not throw.
    myReflection.reflect(B());
  });
}
