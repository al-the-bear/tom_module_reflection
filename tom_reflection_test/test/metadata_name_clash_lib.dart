// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library test_reflection.test.metadata_name_clash_lib;

import 'package:tom_reflection/tom_reflection.dart';

class Reflector2 extends Reflection {
  const Reflector2() : super(metadataCapability);
}

class Bar {
  const Bar();
}

const Reflection reflector2 = Reflector2();

@reflector2
@Bar()
class D {}
