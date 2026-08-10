// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// Declarations for `reflection_in_imported_library_test.dart`. Everything the
// program reflects on — the reflector and the annotated class — is declared
// here, so the library that generation is driven from contributes no reflected
// class of its own and the generated file must reach for this one under an
// import prefix.

library test_reflection.test.reflection_in_imported_library_lib;

import 'package:tom_reflection/tom_reflection.dart';

class Reflector extends Reflection {
  const Reflector() : super(typeCapability);
}

@Reflector()
class C {}
