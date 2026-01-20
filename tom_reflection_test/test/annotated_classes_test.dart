// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library test_reflection.test.annotated_classes_test;

import 'package:tom_reflection/tom_reflection.dart';
import 'package:test/test.dart';
import 'annotated_classes_test.reflection.dart';

class MyReflection extends Reflection {
  const MyReflection() : super(typeCapability);
}

class MyReflection2 extends Reflection {
  const MyReflection2() : super(typeCapability);
}

@MyReflection()
class A {}

@MyReflection()
class B extends A {}

class C extends B {}

class D implements B {}

@MyReflection2()
class E {}

@MyReflection2()
class F implements A {}

@MyReflection()
@MyReflection2()
class G {}

void main() {
  initializeReflection();

  test('Annotated classes', () {
    expect(
      const MyReflection().annotatedClasses.map(
        (ClassMirror classMirror) => classMirror.simpleName,
      ),
      {'A', 'B', 'G'},
    );
    expect(
      const MyReflection2().annotatedClasses.map(
        (ClassMirror classMirror) => classMirror.simpleName,
      ),
      {'E', 'F', 'G'},
    );
  });
}
