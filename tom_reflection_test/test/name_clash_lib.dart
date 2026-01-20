// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflection.test.name_clash_lib;

import 'package:tom_reflection/tom_reflection.dart';

class Reflector extends Reflection {
  const Reflector() : super(typeCapability);
}

const reflector = Reflector();

@reflector
class C {}
