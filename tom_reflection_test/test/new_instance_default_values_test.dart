// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
// Uses default values on optional arguments.

library test_reflection.test.new_instance_default_values_test;

import 'package:tom_reflection/tom_reflection.dart';
import 'package:test/test.dart';
import 'new_instance_default_values_test.reflection.dart';

class MyReflection extends Reflection {
  const MyReflection() : super(newInstanceCapability);
}

const myReflection = MyReflection();

const String globalConstant = '20';

@myReflection
class A {
  static const localConstant = 10;
  A.optional([int x = localConstant, String y = globalConstant]) : f = x, g = y;
  A.namedOptional({int x = localConstant, String y = globalConstant})
    : f = x,
      g = y;
  A.initializingFormal([this.f = localConstant, this.g = globalConstant]);
  A.namedInitializingFormal({this.f = localConstant, this.g = globalConstant});
  int f = 0;
  String g;
}

void main() {
  initializeReflection();

  var classMirror = myReflection.reflectType(A) as ClassMirror;
  A a;

  test('positional argument default, local constant', () {
    a = classMirror.newInstance('optional', [], {}) as A;
    expect(a.f, 10);
  });
  test('positional argument default, global constant', () {
    a = classMirror.newInstance('optional', [], {}) as A;
    expect(a.g, '20');
  });

  test('named argument default, local constant', () {
    a = classMirror.newInstance('namedOptional', [], {}) as A;
    expect(a.f, 10);
  });
  test('named argument default, global constant', () {
    a = classMirror.newInstance('namedOptional', [], {}) as A;
    expect(a.g, '20');
  });

  test('initializing formal default, local constant', () {
    a = classMirror.newInstance('initializingFormal', [], {}) as A;
    expect(a.f, 10);
  });
  test('initializing formal default, global constant', () {
    a = classMirror.newInstance('initializingFormal', [], {}) as A;
    expect(a.g, '20');
  });

  test('named initializing formal default, local constant', () {
    a = classMirror.newInstance('namedInitializingFormal', [], {}) as A;
    expect(a.f, 10);
  });
  test('named initializing formal default, global constant', () {
    a = classMirror.newInstance('namedInitializingFormal', [], {}) as A;
    expect(a.g, '20');
  });
}
