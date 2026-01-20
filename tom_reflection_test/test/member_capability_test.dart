// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
// Uses 'reflect', with a constraint to invocation based on
// 'InvokeInstanceMemberCapability'.

library test_reflection.test.member_capability_test;

import 'package:tom_reflection/tom_reflection.dart';
import 'package:test/test.dart';
import 'member_capability_test.reflection.dart';

class MyReflection extends Reflection {
  const MyReflection() : super(invokingCapability);
}

class MyReflection2 extends Reflection {
  const MyReflection2() : super(const InstanceInvokeCapability(r'^(x|b|b=)$'));
}

class MyReflection3 extends Reflection {
  const MyReflection3() : super(const InstanceInvokeMetaCapability(Bar));
}

const myReflection = MyReflection();
const myReflection2 = MyReflection2();
const myReflection3 = MyReflection3();

class Bar {
  const Bar();
}

@myReflection
class Foo {
  var a = 1;
  var b = 2;
  int x() => 42;
  String y(int n) => 'Hello $n';
}

@myReflection2
class Foo2 {
  var a = 1;
  var b = 2;
  int x() => 42;
  String y(int n) => 'Hello $n';
  Object? z;
}

class Foo3Base {
  @Bar()
  var c = 3;
}

@myReflection3
class Foo3 extends Foo3Base {
  var a = 1;
  @Bar()
  var b = 2;
  int x() => 42;
  @Bar()
  String y(int n) => 'Hello $n';
  // ignore:prefer_typing_uninitialized_variables
  var z;
}

final Matcher throwsReflectionNoMethod = throwsA(
  const TypeMatcher<ReflectionNoSuchMethodError>(),
);

void main() {
  initializeReflection();

  test('invokingCapability', () {
    var foo = Foo();
    var fooMirror = myReflection.reflect(foo);
    expect(fooMirror.invokeGetter('a'), 1);
    expect(fooMirror.invokeSetter('a', 11), 11);
    expect(fooMirror.invokeGetter('a'), 11);
    expect(fooMirror.invokeGetter('b'), 2);
    expect(fooMirror.invokeSetter('b', 12), 12);
    expect(fooMirror.invokeGetter('b'), 12);
    expect(fooMirror.invoke('y', [1]), 'Hello 1');

    expect(fooMirror.invoke('x', []), 42);
    expect(fooMirror.invoke('y', [1]), 'Hello 1');
  });

  test("InstanceInvokeCapability('x')", () {
    var foo = Foo2();
    var fooMirror = myReflection2.reflect(foo);
    expect(() => fooMirror.invokeGetter('a'), throwsReflectionNoMethod);
    expect(() => fooMirror.invokeSetter('a', 11), throwsReflectionNoMethod);
    expect(fooMirror.invokeGetter('b'), 2);
    expect(fooMirror.invokeSetter('b', 12), 12);
    expect(fooMirror.invokeGetter('b'), 12);

    expect(myReflection2.reflect(Foo2()).invoke('x', []), 42);
    expect(
      () => myReflection2.reflect(Foo2()).invoke('y', [3]),
      throwsReflectionNoMethod,
    );
  });

  test('InstanceInvokeMetaCapability(Bar)', () {
    var foo = Foo3();
    var fooMirror = myReflection3.reflect(foo);
    expect(() => fooMirror.invokeGetter('a'), throwsReflectionNoMethod);
    expect(() => fooMirror.invokeSetter('a', 11), throwsReflectionNoMethod);
    expect(fooMirror.invokeGetter('b'), 2);
    expect(fooMirror.invokeSetter('b', 12), 12);
    expect(fooMirror.invokeGetter('b'), 12);
    expect(fooMirror.invokeGetter('c'), 3);
    expect(fooMirror.invokeSetter('c', 13), 13);
    expect(fooMirror.invokeGetter('c'), 13);

    expect(
      () => myReflection3.reflect(Foo3()).invoke('x', []),
      throwsReflectionNoMethod,
    );
    expect(myReflection3.reflect(Foo3()).invoke('y', [3]), 'Hello 3');
  });
}
