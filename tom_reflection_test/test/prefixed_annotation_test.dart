// Copyright (c) 2018, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
// Uses an annotation that denotes a reflector via a prefix.

library test_reflection.test.prefixed_annotation_test;

import 'package:test/test.dart';
import 'prefixed_annotation_lib.dart' as prefix;
import 'prefixed_annotation_test.reflection.dart';

@prefix.reflector
class C {
  int m() => 42;
}

void main() {
  initializeReflection();

  test('Using an import prefix with a reflector', () {
    var instanceMirror = prefix.reflector.reflect(C());
    var result = instanceMirror.invoke('m', []);
    expect(result, 42);
  });
}
