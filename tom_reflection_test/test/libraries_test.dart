// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
// Uses library mirrors and `invoke` on top level entities.

@reflector
library test_reflection.test.libraries_test;

import 'package:tom_reflection/tom_reflection.dart';
import 'package:test/test.dart';
import 'libraries_test.reflection.dart';

class Reflector extends Reflection {
  const Reflector()
    : super(
        libraryCapability,
        const TopLevelInvokeCapability(r'^myFunction$'),
        declarationsCapability,
      );
}

class Reflector2 extends Reflection {
  const Reflector2()
    : super(
        reflectedTypeCapability,
        const TopLevelInvokeMetaCapability(Test),
        declarationsCapability,
        libraryCapability,
        metadataCapability,
      );
}

class Reflector3 extends Reflection {
  const Reflector3() : super(typeCapability);
}

const reflector = Reflector();
const reflector2 = Reflector2();
const reflector3 = Reflector3();

@reflector2
class C {}

@reflector3
class D {}

String myFunction() => 'hello';

class Test {
  const Test();
}

@Test()
var p = 10;

@Test()
const int q = 11;

@Test()
set setter(x) => p = x + 1;

@Test()
String get getter => '10';

final Matcher throwsNoCapability = throwsA(
  const TypeMatcher<NoSuchCapabilityError>(),
);

final Matcher throwsReflectionNoMethod = throwsA(
  const TypeMatcher<ReflectionNoSuchMethodError>(),
);

void main() {
  initializeReflection();

  test('invoke function, getter', () {
    var libraryMirror = reflector.findLibrary(
      'test_reflection.test.libraries_test',
    );
    expect(libraryMirror.simpleName, 'test_reflection.test.libraries_test');
    expect(libraryMirror.invoke('myFunction', []), 'hello');
    expect(
      Function.apply(libraryMirror.invokeGetter('myFunction') as Function, []),
      'hello',
    );
    expect(
      () => libraryMirror.invokeGetter('getter'),
      throwsReflectionNoMethod,
    );
    var myFunctionMirror =
        libraryMirror.declarations['myFunction'] as MethodMirror;
    expect(myFunctionMirror.owner, libraryMirror);
  });
  test('owner, setter, TopLevelMetaInvokeCapability', () {
    var libraryMirror = reflector2.reflectType(C).owner as LibraryMirror;
    expect(libraryMirror.qualifiedName, 'test_reflection.test.libraries_test');
    expect(libraryMirror.simpleName, 'test_reflection.test.libraries_test');
    expect(libraryMirror.invokeSetter('setter=', 11), 11);
    expect(p, 12);
    expect(libraryMirror.invokeGetter('getter'), '10');
    var pMirror = libraryMirror.declarations['p'] as VariableMirror;
    var qMirror = libraryMirror.declarations['q'] as VariableMirror;
    var getterMirror = libraryMirror.declarations['getter'] as MethodMirror;
    var setterMirror = libraryMirror.declarations['setter='] as MethodMirror;
    expect(pMirror.owner, libraryMirror);
    expect(pMirror.hasReflectedType, true);
    expect(pMirror.reflectedType, int);
    expect(pMirror.metadata.length, 1);
    expect(pMirror.metadata[0], const Test());
    expect(pMirror.isConst, false);
    expect(qMirror.owner, libraryMirror);
    expect(qMirror.hasReflectedType, true);
    expect(qMirror.reflectedType, int);
    expect(qMirror.metadata.length, 1);
    expect(qMirror.metadata[0], const Test());
    expect(qMirror.isConst, true);
    expect(getterMirror.owner, libraryMirror);
    expect(setterMirror.owner, libraryMirror);
  });
  test('No libraryCapability', () {
    expect(() => reflector3.reflectType(D).owner, throwsNoCapability);
    expect(
      () =>
          reflector3.findLibrary('test_reflection.test.libraries_test').owner,
      throwsNoCapability,
    );
  });
}
