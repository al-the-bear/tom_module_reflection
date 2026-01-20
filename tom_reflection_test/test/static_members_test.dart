// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
// Uses `staticMembers` to access a static const variable.

library test_reflection.test.static_members_test;

import 'package:tom_reflection/tom_reflection.dart';
import 'package:test/test.dart';
import 'static_members_test.reflection.dart';

class MyReflection extends Reflection {
  const MyReflection() : super(staticInvokeCapability, declarationsCapability);
}

const myReflection = MyReflection();

@myReflection
class A {
  static const List<String> foo = ['apple'];
}

void main() {
  initializeReflection();

  var classMirror = myReflection.reflectType(A) as ClassMirror;
  test('Static members', () {
    expect(classMirror.staticMembers.length, 1);
    expect(classMirror.staticMembers['foo'], isNotNull);
  });
}
