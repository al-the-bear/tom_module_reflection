// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflection.test.reflect_type_test;

import 'package:tom_reflection/tom_reflection.dart';
import 'package:test/test.dart';
import 'reflect_type_test.reflection.dart';

class Reflector extends Reflection {
  const Reflector() : super(typeCapability);
}

const reflector = Reflector();

class BroadReflector extends Reflection {
  const BroadReflector()
    : super.fromList(const <ReflectCapability>[typingCapability]);
}

const broadReflector = BroadReflector();

@reflector
@broadReflector
class A {}

class B {}

final Matcher throwsNoCapability = throwsA(
  TypeMatcher<NoSuchCapabilityError>(),
);

void performTests(String message, reflector) {
  test('$message: reflectType', () {
    ClassMirror cm = reflector.reflectType(A);
    expect(cm, TypeMatcher<ClassMirror>());
    expect(cm.simpleName, 'A');
    expect(() => reflector.reflectType(B), throwsNoCapability);
  });
  test('$message: InstanceMirror.type', () {
    ClassMirror cm = reflector.reflectType(A);
    ClassMirror cm2 = reflector.reflect(A()).type;
    expect(cm.qualifiedName, cm2.qualifiedName);
  });
}

void main() {
  initializeReflection();

  performTests('With typeCapability', reflector);
  performTests('With typingCapability', broadReflector);
  test('Seeing that typing is broader than type', () {
    expect(
      () => reflector.findLibrary('test_reflection.test.reflect_type_test'),
      throwsNoCapability,
    );
    var libraryMirror = broadReflector.findLibrary(
      'test_reflection.test.reflect_type_test',
    );
    expect(libraryMirror, isNotNull);
    var uriString = libraryMirror.uri.toString();
    // Note: tom_reflection uses package: URI scheme instead of asset:
    expect(
      uriString == 'asset:test_reflection/test/reflect_type_test.dart' ||
          uriString ==
              'package:tom_reflection_test/test/reflect_type_test.dart',
      isTrue,
    );
  });
}
