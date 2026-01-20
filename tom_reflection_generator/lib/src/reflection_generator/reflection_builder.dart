// Copyright (c) 2017, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// Build_runner builder for generating reflection code.
///
/// This module provides the [ReflectionGenerator] builder that integrates
/// with build_runner to generate `.reflection.dart` files.
library;

import 'dart:async';
import 'dart:io';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'build_runner_resolver.dart';
import 'generator_implementation.dart';

final _mapEnvironmentToWarningKind = <String, Set<WarningKind>>{
  "REFLECTION_SUPPRESS_BAD_SUPERCLASS": {WarningKind.badSuperclass},
  "REFLECTION_SUPPRESS_BAD_NAME_PATTERN": {WarningKind.badNamePattern},
  "REFLECTION_SUPPRESS_BAD_METADATA": {WarningKind.badMetadata},
  "REFLECTION_SUPPRESS_BAD_REFLECTOR_CLASS": {WarningKind.badReflectorClass},
  "REFLECTION_SUPPRESS_UNSUPPORTED_TYPE": {WarningKind.unsupportedType},
  "REFLECTION_SUPPRESS_UNUSED_REFLECTOR": {WarningKind.unusedReflector},
  "REFLECTION_SUPPRESS_ALL_WARNINGS": WarningKind.values.toSet(),
};

List<WarningKind> _computeSuppressedWarnings() {
  final suppressedWarnings = <WarningKind>{};
  final environmentMap = Platform.environment;
  for (final variable in _mapEnvironmentToWarningKind.keys) {
    if (environmentMap[variable]?.isNotEmpty == true) {
      suppressedWarnings.addAll(_mapEnvironmentToWarningKind[variable]!);
    }
  }
  return suppressedWarnings.toList();
}

/// A build_runner [Builder] that generates reflection code.
///
/// This builder processes `.dart` files and generates corresponding
/// `.reflection.dart` files containing mirror implementations.
class ReflectionGenerator implements Builder {
  /// Builder options from build.yaml configuration.
  BuilderOptions builderOptions;

  /// Creates a new [ReflectionGenerator] with the given [builderOptions].
  ReflectionGenerator(this.builderOptions);

  @override
  Future<void> build(BuildStep buildStep) async {
    var targetId = buildStep.inputId.toString();
    if (targetId.contains('.vm_test.') ||
        targetId.contains('.node_test.') ||
        targetId.contains('.browser_test.')) {
      return;
    }
    LibraryElement inputLibrary = await buildStep.inputLibrary;
    final resolver = BuildRunnerLibraryResolver(buildStep.resolver);
    final inputId = buildStep.inputId.toFileId();
    final outputId =
        buildStep.inputId.changeExtension('.reflection.dart').toFileId();
    List<LibraryElement> visibleLibraries =
        await buildStep.resolver.libraries.toList();
    List<WarningKind> suppressedWarnings = _computeSuppressedWarnings();
    String generatedSource = await GeneratorImplementation().buildMirrorLibrary(
      resolver,
      inputId,
      outputId,
      inputLibrary,
      visibleLibraries.cast(),
      true,
      suppressedWarnings,
    );
    await buildStep.writeAsString(
        buildStep.inputId.changeExtension('.reflection.dart'), generatedSource);
  }

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.reflection.dart'],
      };
}

/// Factory function to create a [ReflectionGenerator] for build_runner.
///
/// This is the entry point referenced in build.yaml configurations.
ReflectionGenerator reflectionGenerator(BuilderOptions options) {
  var config = Map<String, Object>.from(options.config);
  config.putIfAbsent('entry_points', () => ['**.dart']);
  return ReflectionGenerator(options);
}
