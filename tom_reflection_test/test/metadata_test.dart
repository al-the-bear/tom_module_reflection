// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// Tests that metadata is preserved when the metadataCapability is present.
// TODO(sigurdm) implement: Support for metadata-annotations of arguments.

@c
library test_reflection.test.metadata_test;

import 'package:tom_reflection/tom_reflection.dart';
import 'package:test/test.dart';
import 'metadata_test.reflection.dart';

class MyReflection extends Reflection {
  const MyReflection()
    : super(
        metadataCapability,
        instanceInvokeCapability,
        staticInvokeCapability,
        declarationsCapability,
        libraryCapability,
      );
}

const myReflection = MyReflection();

class MyReflection2 extends Reflection {
  const MyReflection2()
    : super(instanceInvokeCapability, staticInvokeCapability);
}

const myReflection2 = MyReflection2();

const b = 13;
const c = [
  Bar({'a': 14}),
];
const d = true;

class K {
  static const p = 2;
}

@myReflection
@Bar({
  b: deprecated,
  c: Deprecated('tomorrow'),
  1 + 2: (d ? 3 : 4),
  identical(1, 2): 's',
  K.p: 6,
})
@b
@c
class Foo {
  @Bar({})
  @Bar.namedConstructor({})
  @b
  @c
  void foo() {}

  @b
  var x = 10;
}

@myReflection2
@Bar({})
@Bar.namedConstructor({})
@b
@c
class Foo2 {
  @Bar({})
  @Bar.namedConstructor({})
  @b
  @c
  void foo() {}
}

class Bar {
  final Map<Object, Object> m;
  const Bar(this.m);
  const Bar.namedConstructor(this.m);

  @override
  String toString() => 'Bar($m)';
}

void main() {
  initializeReflection();

  test('metadata on class', () {
    expect(myReflection.reflectType(Foo).metadata, const [
      MyReflection(),
      Bar({b: deprecated, c: Deprecated('tomorrow'), 3: 3, false: 's', 2: 6}),
      13,
      [
        Bar({'a': 14}),
      ],
    ]);

    var fooMirror = myReflection.reflectType(Foo) as ClassMirror;
    expect(fooMirror.declarations['foo']!.metadata, const [
      Bar({}),
      Bar({}),
      13,
      [
        Bar({'a': 14}),
      ],
    ]);

    expect(fooMirror.declarations['x']!.metadata, [b]);

    // The synthetic accessors do not have metadata.
    expect(fooMirror.instanceMembers['x']!.metadata, []);
    expect(fooMirror.instanceMembers['x=']!.metadata, []);

    // Test metadata on libraries
    expect(myReflection.reflectType(Foo).owner!.metadata, [c]);
  });
  test('metadata without capability', () {
    var foo2Mirror = myReflection2.reflectType(Foo2) as ClassMirror;
    expect(
      () => foo2Mirror.metadata,
      throwsA(const TypeMatcher<NoSuchCapabilityError>()),
    );

    expect(
      () => foo2Mirror.declarations['foo']!.metadata,
      throwsA(const TypeMatcher<NoSuchCapabilityError>()),
    );
  });
}
