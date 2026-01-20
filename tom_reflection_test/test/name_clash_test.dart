// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflection.test.name_clash_test;

import 'name_clash_lib.dart' as o;
import 'package:test/test.dart';
import 'name_clash_test.reflection.dart';

@o.reflector
class C {}

void main() {
  initializeReflection();

  test('Name-clash in annotated classes', () {
    expect(o.reflector.reflectType(C), isNot(o.reflector.reflectType(o.C)));
  });
}
