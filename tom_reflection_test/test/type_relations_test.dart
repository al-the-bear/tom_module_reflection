// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
// Uses `typeRelations` capability.

library test_reflection.test.type_relations_test;

import 'package:tom_reflection/tom_reflection.dart';
import 'package:test/test.dart';
import 'type_relations_test.reflection.dart';

// ignore_for_file: omit_local_variable_types

class MyReflection extends Reflection {
  const MyReflection()
    : super(superclassQuantifyCapability, typeRelationsCapability);
}

const myReflection = MyReflection();

@myReflection
class MyClass {}

void main() {
  initializeReflection();

  var myClassMirror = myReflection.reflectType(MyClass) as ClassMirror;
  ClassMirror classObjectMirror = myClassMirror.superclass!;
  test('superclass targetting un-annotated class', () {
    expect(classObjectMirror.simpleName, 'Object');
  });
  test('non-existing superclass', () {
    expect(classObjectMirror.superclass, null);
  });
  // TODO(eernst) implement: add missing cases for `typeRelationsCapability`:
  // typeVariables, typeArguments, originalDeclaration, isSubtypeOf,
  // isAssignableTo, superClass, superInterfaces, mixin, isSubclassOf,
  // upperBound, and referent.
}
