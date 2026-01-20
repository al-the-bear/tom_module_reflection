// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflection.test.no_such_capability_test;

import 'package:tom_reflection/tom_reflection.dart' as r;
import 'package:test/test.dart';
import 'no_such_capability_test.reflection.dart';

// ignore_for_file: omit_local_variable_types

class MyReflection extends r.Reflection {
  const MyReflection()
    : super(
        const r.StaticInvokeCapability('nonExisting'),
        const r.InstanceInvokeCapability('nonExisting'),
      );
}

const myReflection = MyReflection();

@myReflection
class A {}

Matcher throwsReflectionNoMethod = throwsA(
  const TypeMatcher<r.ReflectionNoSuchMethodError>(),
);

void main() {
  initializeReflection();

  test('reflect', () {
    r.InstanceMirror instanceMirror = myReflection.reflect(A());
    expect(
      () => instanceMirror.invoke('foo', []),
      throwsA(const TypeMatcher<r.ReflectionNoSuchMethodError>()),
    );
    r.ClassMirror classMirror = myReflection.reflectType(A) as r.ClassMirror;
    expect(
      () => classMirror.invoke('foo', []),
      throwsA(const TypeMatcher<r.ReflectionNoSuchMethodError>()),
    );
    // When we have the capability we get the NoSuchMethodError, not
    // NoSuchCapabilityError.
    expect(
      () => instanceMirror.invoke('nonExisting', []),
      throwsReflectionNoMethod,
    );

    // When we have the capability we get the NoSuchMethodError, not
    // NoSuchCapabilityError.
    expect(
      () => classMirror.invoke('nonExisting', []),
      throwsReflectionNoMethod,
    );
  });
}
