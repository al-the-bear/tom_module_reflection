// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
// Imports the core file of this package and uses the
// class Reflection as an annotation.

library test_reflection.test.use_annotation;

import 'package:tom_reflection/tom_reflection.dart';

class MyReflection extends Reflection {
  const MyReflection();
}

@MyReflection()
class A {}

void main() {}
