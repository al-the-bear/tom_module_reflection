// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
// Uses 'reflect' across file boundaries.  Provider of the
// metadata class.

library test_reflection.test.three_files_meta;

import 'package:tom_reflection/tom_reflection.dart';

class MyReflection extends Reflection {
  const MyReflection() : super();
}

const myReflection = MyReflection();
