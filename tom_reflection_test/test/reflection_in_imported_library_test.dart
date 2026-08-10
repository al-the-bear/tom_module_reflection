// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
//
// The entry point declares nothing reflected: the reflector and the annotated
// class both live in `reflection_in_imported_library_lib.dart`. Generation is
// nonetheless driven from *this* library — it is the one carrying `main()` —
// so the generated file has to reach into an imported library for every mirror
// it emits and reference nothing local. Other tests in this suite keep the
// annotated class next to `main()`; this is the one that separates them.

library test_reflection.test.reflection_in_imported_library_test;

import 'package:test/test.dart';

import 'reflection_in_imported_library_lib.dart';
import 'reflection_in_imported_library_test.reflection.dart';

void main() {
  initializeReflection();

  test('reflector and annotated class in an imported library', () {
    expect(const Reflector().canReflectType(C), true);
  });
}
