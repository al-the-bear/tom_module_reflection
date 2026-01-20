// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflection.test.mixin_static_const_test;

import 'package:tom_reflection/tom_reflection.dart';
import 'package:test/test.dart';
import 'mixin_static_const_test.reflection.dart';

class Reflector extends Reflection {
  const Reflector() : super(invokingCapability, declarationsCapability);
}

const reflector = Reflector();

class A {}

@reflector
mixin class M {
  static const String s = 'dart';
}

@reflector
class B extends A with M {}

void main() {
  initializeReflection();

  test('Static const not present in mixin application', () {
    var mMirror = reflector.reflectType(M) as ClassMirror;
    expect(mMirror.declarations['s'] != null, true);
    var classMirror = reflector.reflectType(B) as ClassMirror;
    expect(classMirror.declarations['s'], null);
  });
}
