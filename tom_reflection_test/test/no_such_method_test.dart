// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// File used to test reflection code generation.
// Uses a generic mixin.

@reflector
library test_reflection.test.no_such_method_test;

import 'package:tom_reflection/tom_reflection.dart';
import 'package:test/test.dart';
import 'no_such_method_test.reflection.dart';

class Reflector extends Reflection {
  const Reflector()
    : super(typeCapability, invokingCapability, libraryCapability);
}

const reflector = Reflector();

@reflector
class A {
  int arg0() => 100;
  int arg1(int x) => 101;
  int arg2to4(A x, int y, [Reflector? z, w]) => 102;
  int argNamed(int x, y, {num? z}) => 103;
  int operator [](int x) => 104;
  void operator []=(int x, v) {}

  // Not a movie title.
  int deepThrow(o) => deepThrowImpl(o);
  int deepThrowImpl(o) => o.thisGetterDoesNotExist;
}

Matcher throwsReflectionNoSuchMethod = throwsA(
  const TypeMatcher<ReflectionNoSuchMethodError>(),
);

void main() {
  initializeReflection();

  var aMirror = reflector.reflect(A());
  var libraryMirror = reflector.findLibrary(
    'test_reflection.test.no_such_method_test',
  );

  // Check that reflection invocations of non-existing methods causes
  // a `ReflectionNoSuchMethodError`.
  test('No such method', () {
    expect(
      () => aMirror.invoke('doesNotExist', []),
      throwsReflectionNoSuchMethod,
    );
    expect(
      () => aMirror.invoke('doesNotExist', [0]),
      throwsReflectionNoSuchMethod,
    );
    expect(
      () => aMirror.invoke('doesNotExist', [0], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(() => aMirror.invoke('arg0', [0]), throwsReflectionNoSuchMethod);
    expect(
      () => aMirror.invoke('arg0', [], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(
      () => aMirror.invoke('arg0', [0], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(() => aMirror.invoke('arg1', []), throwsReflectionNoSuchMethod);
    expect(
      () => aMirror.invoke('arg1', [], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(
      () => aMirror.invoke('arg1', [0], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(() => aMirror.invoke('arg1', [0, 0]), throwsReflectionNoSuchMethod);
    expect(
      () => aMirror.invoke('arg1', [0, 0], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(() => aMirror.invoke('arg2to4', [0]), throwsReflectionNoSuchMethod);
    expect(
      () => aMirror.invoke('arg2to4', [0], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(
      () => aMirror.invoke('arg2to4', [0, 0], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(
      () => aMirror.invoke('arg2to4', [0, 0, 0], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(
      () => aMirror.invoke('arg2to4', [0, 0, 0, 0], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(
      () => aMirror.invoke('arg2to4', [0, 0, 0, 0, 0]),
      throwsReflectionNoSuchMethod,
    );
    expect(
      () => aMirror.invoke('arg2to4', [0, 0, 0, 0, 0], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(() => aMirror.invoke('+', []), throwsReflectionNoSuchMethod);
    expect(
      () => aMirror.invoke('+', [], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(
      () => aMirror.invoke('+', [0], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(() => aMirror.invoke('+', [0, 0]), throwsReflectionNoSuchMethod);
    expect(
      () => aMirror.invoke('+', [0, 0], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(() => aMirror.invoke('[]', []), throwsReflectionNoSuchMethod);
    expect(
      () => aMirror.invoke('[]', [], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(
      () => aMirror.invoke('[]', [0], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(() => aMirror.invoke('[]', [0, 0]), throwsReflectionNoSuchMethod);
    expect(
      () => aMirror.invoke('[]', [0, 0], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );

    expect(
      () => aMirror.invokeGetter('doesNotExist'),
      throwsReflectionNoSuchMethod,
    );
    expect(
      () => aMirror.invokeSetter('doesNotExist', 0),
      throwsReflectionNoSuchMethod,
    );

    expect(
      () => libraryMirror.invoke('doesNotExist', []),
      throwsReflectionNoSuchMethod,
    );
    expect(
      () => libraryMirror.invoke('doesNotExist', [], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(
      () => libraryMirror.invoke('doesNotExist', [0]),
      throwsReflectionNoSuchMethod,
    );
    expect(
      () => libraryMirror.invoke('doesNotExist', [0], {#doesNotExist: 0}),
      throwsReflectionNoSuchMethod,
    );
    expect(
      () => libraryMirror.invokeGetter('doesNotExist'),
      throwsReflectionNoSuchMethod,
    );
    expect(
      () => libraryMirror.invokeSetter('doesNotExist', 0),
      throwsReflectionNoSuchMethod,
    );
  });

  // Check that we can distinguish a reflection invocation failure from a
  // `NoSuchMethodError` thrown by a normal, non-reflection invocation.
  test('No such method, natively', () {
    expect(() => A().deepThrow(Object()), throwsNoSuchMethodError);
    expect(
      () => aMirror.invoke('deepThrow', [Object()]),
      throwsNoSuchMethodError,
    );
  });
}
