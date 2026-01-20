// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
// Uses a declaration from the original main file (this one)
// in an expression that will be copied in generated code.

library test_reflection.test.original_prefix_test;

import 'package:tom_reflection/tom_reflection.dart';
import 'package:test/test.dart';
import 'original_prefix_test.reflection.dart';

class MyReflection extends Reflection {
  const MyReflection()
    : super(newInstanceCapability, instanceInvokeCapability);
}

const myReflection = MyReflection();

const int defaultX = 0x2A;
const int _defaultY = defaultX;

@myReflection
class C {
  final String s;
  C([int x = defaultX, int y = _defaultY])
    : s = '${x.toString().length + 2}${y ~/ 15}';
}

void main() {
  initializeReflection();

  test('Original prefix', () {
    var classMirror = myReflection.reflectType(C) as ClassMirror;
    var c = classMirror.newInstance('', []) as C;
    expect(c.s, '42');
  });
}
