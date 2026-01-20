// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// File used to test reflection code generation.
/// Part of the entry point 'meta_reflectors_test.dart'.
///
/// Independence: This library defines reflectors only, and it does not depend
/// on the usage of reflection. It does depend on the domain classes, because
/// it uses `A` as an upper bound in a superclass quantifier.
library test_reflection.test.meta_reflectors_domain_definer;

import 'package:tom_reflection/tom_reflection.dart';
import 'meta_reflectors_domain.dart';

class ReflectorUpwardsClosedToA extends Reflection {
  const ReflectorUpwardsClosedToA()
    : super(
        const SuperclassQuantifyCapability(A),
        invokingCapability,
        declarationsCapability,
        typeRelationsCapability,
      );
}

class ReflectorUpwardsClosedUntilA extends Reflection {
  const ReflectorUpwardsClosedUntilA()
    : super(
        const SuperclassQuantifyCapability(A, excludeUpperBound: true),
        invokingCapability,
        declarationsCapability,
      );
}
