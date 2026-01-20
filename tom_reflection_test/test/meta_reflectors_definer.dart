// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// File used to test reflection code generation.
/// Part of the entry point 'meta_reflectors_test.dart'.
///
/// Independence: This library defines reflectors only, and it does not depend
/// on domain classes (`M1..3, A..D, P`) nor on the usage of reflection, i.e.,
/// these reflectors could have been defined in a third-party package .
library test_reflection.test.meta_reflectors_definer;

import 'package:tom_reflection/tom_reflection.dart';

class Reflector extends Reflection {
  const Reflector()
    : super(
        invokingCapability,
        declarationsCapability,
        typeRelationsCapability,
        libraryCapability,
      );
}

class Reflector2 extends Reflection {
  const Reflector2()
    : super(
        invokingCapability,
        typeRelationsCapability,
        metadataCapability,
        libraryCapability,
      );
}

class ReflectorUpwardsClosed extends Reflection {
  const ReflectorUpwardsClosed()
    : super(
        superclassQuantifyCapability,
        invokingCapability,
        declarationsCapability,
        typeRelationsCapability,
      );
}
