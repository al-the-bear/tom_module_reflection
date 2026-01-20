// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Reflection code generator for Tom Reflection.
///
/// This library provides the core logic for generating reflection code,
/// with abstraction over the library resolution mechanism.
///
/// Use [StandaloneLibraryResolver] for CLI tools that don't use build_runner,
/// or [BuildRunnerLibraryResolver] for build_runner integration.
library;

export 'build_runner_resolver.dart';
export 'generator_implementation.dart' show GeneratorImplementation, WarningKind;
export 'library_resolver.dart';
export 'reflection_builder.dart';
export 'standalone_resolver.dart';
