// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// File used to test reflection code generation.
// Imports the core file of this package and re-exports
// it.  Such an export must be adjusted similarly to the
// adjustment applied to the import.

library test_reflection.test.export_test;

import 'package:tom_reflection/tom_reflection.dart';
import 'export_test.reflection.dart';

export 'package:tom_reflection/tom_reflection.dart';

const Reflection? ignored = null; // To avoid 'unused import'.

void main() {
  initializeReflection();
}
