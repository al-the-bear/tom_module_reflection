// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Shared reflection-generation pipeline.
///
/// This is the single implementation of the "generate `.reflection.dart` for a
/// set of targets rooted at a project" flow. Both the standalone CLI
/// (`lib/src/cli/runner.dart`) and the buildkit-nestable tool executor
/// (`lib/src/v2/...`) call into this module so there is exactly one copy of the
/// summary-cache → resolver → collect → process pipeline.
library;

import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
// runSummaryCacheStage is re-exported by this package's summary.dart
// (which itself re-exports `package:tom_analyzer_shared`).
import 'package:tom_reflection_generator/tom_reflection_generator.dart';
import 'package:yaml/yaml.dart';

/// Options controlling a reflection-generation run.
class ReflectionGenerationOptions {
  const ReflectionGenerationOptions({
    this.packageName = 'tom_reflection',
    this.outputExtension = '.reflection.dart',
    this.useAllCapabilities = false,
    this.allMode = false,
    this.verbose = false,
    this.noCache = false,
    this.rebuildCache = false,
    this.showCacheStatus = false,
    this.cacheOnlyPackages = const [],
  });

  /// Reflection package name whose annotations trigger generation.
  final String packageName;

  /// Output file extension (default `.reflection.dart`).
  final String outputExtension;

  /// Use all capabilities instead of those declared on the reflector class.
  final bool useAllCapabilities;

  /// Process directory targets recursively (the CLI `--all` flag).
  final bool allMode;

  /// Print detailed progress information.
  final bool verbose;

  /// Disable summary caching for dependencies.
  final bool noCache;

  /// Force regeneration of all cached summaries.
  final bool rebuildCache;

  /// Only display cache status, then stop without generating.
  final bool showCacheStatus;

  /// Restrict summary caching to specific package(s).
  final List<String> cacheOnlyPackages;
}

/// Outcome of a reflection-generation run.
class ReflectionGenerationResult {
  const ReflectionGenerationResult({
    required this.processedCount,
    required this.skippedCount,
    this.cacheStatusShown = false,
    this.noFilesMatched = false,
  });

  /// Number of files for which reflection was generated.
  final int processedCount;

  /// Number of files that were resolved but skipped (no reflection usage,
  /// no entry point, or an error).
  final int skippedCount;

  /// True when the run only displayed cache status and generated nothing.
  final bool cacheStatusShown;

  /// True when no input files matched the supplied targets.
  final bool noFilesMatched;
}

/// Runs the full reflection-generation pipeline for [targets] (files,
/// directories, or glob patterns) rooted at [projectRoot].
///
/// Handles the summary-cache stage, resolver lifecycle, target collection and
/// per-file generation. The resolver is always disposed before returning.
Future<ReflectionGenerationResult> generateReflection({
  required String projectRoot,
  required List<String> targets,
  ReflectionGenerationOptions options = const ReflectionGenerationOptions(),
}) async {
  final root = p.normalize(projectRoot);

  if (options.verbose) {
    print('Project root: $root');
  }

  // Summary caching stage.
  List<String>? summaryPaths;
  String? sdkSummaryPath;
  if (!options.noCache) {
    final cacheResult = await runSummaryCacheStage(
      root,
      verbose: options.verbose,
      rebuildCache: options.rebuildCache,
      showCacheStatus: options.showCacheStatus,
      cacheOnlyPackages: options.cacheOnlyPackages,
    );
    summaryPaths = cacheResult?.summaryPaths;
    sdkSummaryPath = cacheResult?.sdkSummaryPath;
    if (options.showCacheStatus) {
      // --show-cache-status is info-only; nothing else to do.
      return const ReflectionGenerationResult(
        processedCount: 0,
        skippedCount: 0,
        cacheStatusShown: true,
      );
    }
  }

  // Create the standalone resolver.
  final resolver = await StandaloneLibraryResolver.create(
    root,
    librarySummaryPaths: summaryPaths,
    sdkSummaryPath: sdkSummaryPath,
  );

  try {
    final filesToProcess = collectTargetFiles(
      projectRoot: root,
      targets: targets,
      allMode: options.allMode,
      verbose: options.verbose,
    );

    if (filesToProcess.isEmpty) {
      return const ReflectionGenerationResult(
        processedCount: 0,
        skippedCount: 0,
        noFilesMatched: true,
      );
    }

    var processedCount = 0;
    var skippedCount = 0;

    // Build-runner-style progress so a run is observable even in non-verbose
    // mode (e.g. when nested under buildkit, where this tool's stdout is the
    // only signal the user sees).
    final total = filesToProcess.length;
    final stopwatch = Stopwatch()..start();
    print('Generating reflection for $total target file(s)...');

    var index = 0;
    for (final filePath in filesToProcess) {
      index++;
      if (total > 1) {
        print('  [$index/$total] ${p.relative(filePath, from: root)}');
      }
      final processed = await processReflectionFile(
        filePath,
        root,
        resolver,
        options.verbose,
        options.packageName,
        options.outputExtension,
        useAllCapabilities: options.useAllCapabilities,
      );
      if (processed) {
        processedCount++;
      } else {
        skippedCount++;
      }
    }

    stopwatch.stop();
    print('Reflection generation succeeded after '
        '${_formatElapsed(stopwatch.elapsed)} — '
        '$processedCount generated, $skippedCount skipped.');

    return ReflectionGenerationResult(
      processedCount: processedCount,
      skippedCount: skippedCount,
    );
  } finally {
    resolver.dispose();
  }
}

/// Collects the set of `.dart` files to process from [targets].
///
/// Each target may be a glob pattern, a directory (processed recursively only
/// when [allMode] is set), or an individual file. Generated outputs
/// (`.reflection.dart`, `.g.dart`) are always excluded.
Set<String> collectTargetFiles({
  required String projectRoot,
  required List<String> targets,
  bool allMode = false,
  bool verbose = false,
}) {
  final filesToProcess = <String>{};

  for (final target in targets) {
    if (isGlobPattern(target)) {
      if (verbose) {
        print('Matching glob pattern: $target');
      }
      final glob = Glob(target);
      final matches = glob.listSync(root: projectRoot);

      for (final entity in matches) {
        if (entity is File && _isGeneratableDart(entity.path)) {
          filesToProcess.add(p.normalize(entity.path));
        }
      }
    } else {
      final normalizedTarget = p.normalize(
        p.isAbsolute(target) ? target : p.join(Directory.current.path, target),
      );

      if (FileSystemEntity.isDirectorySync(normalizedTarget)) {
        if (allMode) {
          collectDartFilesFromDirectory(normalizedTarget, filesToProcess);
        } else {
          print('Warning: $target is a directory. Use --all to process '
              'directories recursively, or use a glob pattern.');
        }
      } else if (FileSystemEntity.isFileSync(normalizedTarget)) {
        if (_isGeneratableDart(normalizedTarget)) {
          filesToProcess.add(normalizedTarget);
        }
      } else {
        print('Warning: Target not found: $target');
      }
    }
  }

  return filesToProcess;
}

/// Formats [elapsed] as a compact, build-runner-style duration string
/// (e.g. `0.3s`, `12.7s`, `1m 4s`).
String _formatElapsed(Duration elapsed) {
  final totalMs = elapsed.inMilliseconds;
  if (totalMs < 60000) {
    return '${(totalMs / 1000).toStringAsFixed(1)}s';
  }
  final minutes = elapsed.inMinutes;
  final seconds = elapsed.inSeconds - minutes * 60;
  return '${minutes}m ${seconds}s';
}

/// Whether [path] is a `.dart` file that is itself an eligible input (i.e. not
/// a generated reflection or build_runner output).
bool _isGeneratableDart(String path) {
  return path.endsWith('.dart') &&
      !path.endsWith('.reflection.dart') &&
      !path.endsWith('.g.dart');
}

/// Returns true if [s] looks like a glob pattern.
bool isGlobPattern(String s) {
  return s.contains('*') || s.contains('?') || s.contains('[') || s.contains('{');
}

/// Recursively collects all eligible `.dart` files under [dirPath] into [files].
void collectDartFilesFromDirectory(String dirPath, Set<String> files) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return;

  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File && _isGeneratableDart(entity.path)) {
      files.add(p.normalize(entity.path));
    }
  }
}

/// Generates reflection for a single [filePath].
///
/// Returns true when an output file was written, false when the file was
/// skipped (does not use reflection, has no entry point, or failed to resolve).
Future<bool> processReflectionFile(
  String filePath,
  String projectRoot,
  StandaloneLibraryResolver resolver,
  bool verbose,
  String packageName,
  String outputExtension, {
  bool useAllCapabilities = false,
}) async {
  if (verbose) {
    print('Analyzing: $filePath');
  }

  try {
    // Resolve the library.
    final library = await resolver.resolveFile(filePath);
    if (library == null) {
      if (verbose) {
        print('  Skipped: Could not resolve library');
      }
      return false;
    }

    // Check if the file uses reflection.
    final usesReflection = await _usesReflection(library, resolver, packageName);
    if (!usesReflection) {
      if (verbose) {
        print('  Skipped: Does not use @$packageName');
      }
      return false;
    }

    // Check if it has a main function (entry point).
    if (library.entryPoint == null) {
      if (verbose) {
        print('  Skipped: No main() entry point');
      }
      return false;
    }

    // Generate the reflection code.
    final relativePath = p.relative(filePath, from: projectRoot);
    final projectPackageName = _getPackageName(projectRoot);
    final inputId = FileId(projectPackageName, relativePath);
    final outputId = inputId.changeExtension(outputExtension);

    // Get only the libraries transitively imported by the entry point
    // (excludes test files that aren't imported by the entry point).
    final visibleLibraries = await _getTransitiveLibraries(library);

    // Build the mirror library with the specified reflection package name.
    // By default, use capabilities from reflector unless useAllCapabilities set.
    final builder = GeneratorImplementation(
      reflectionPackageName: packageName,
      useAllCapabilities: useAllCapabilities,
    );
    final generatedSource = await builder.buildMirrorLibrary(
      resolver,
      inputId,
      outputId,
      library,
      visibleLibraries.cast(),
      true, // formatted
      [], // no suppressed warnings
    );

    // Write the output file.
    final outputPath = filePath.replaceAll('.dart', outputExtension);
    await File(outputPath).writeAsString(generatedSource);

    print('  Generated: $outputPath');
    return true;
  } catch (e, st) {
    if (verbose) {
      print('  Error: $e');
      print('  Stack: $st');
    } else {
      print('  Error processing $filePath: $e');
    }
    return false;
  }
}

/// Finds the nearest enclosing project root (directory containing a
/// `pubspec.yaml`) starting from [startPath]. Returns null if none is found.
String? findProjectRoot(String startPath) {
  var current = p.isAbsolute(startPath)
      ? startPath
      : p.join(Directory.current.path, startPath);

  if (FileSystemEntity.isFileSync(current)) {
    current = p.dirname(current);
  }

  while (current != p.dirname(current)) {
    if (File(p.join(current, 'pubspec.yaml')).existsSync()) {
      return current;
    }
    current = p.dirname(current);
  }

  return null;
}

/// Extracts `generate_for` patterns from a parsed `build.yaml` [yaml].
///
/// Looks under `targets.<target>.builders.<reflection builder>.generate_for`
/// and also accepts a top-level `generate_for` shorthand.
List<String> extractGenerateForPatterns(YamlMap yaml, {bool verbose = false}) {
  final patterns = <String>[];

  final targets = yaml['targets'] as YamlMap?;
  if (targets != null) {
    for (final targetEntry in targets.entries) {
      final targetConfig = targetEntry.value as YamlMap?;
      if (targetConfig == null) continue;

      final builders = targetConfig['builders'] as YamlMap?;
      if (builders == null) continue;

      // Look for reflection_generator or any builder with generate_for.
      for (final builderEntry in builders.entries) {
        final builderName = builderEntry.key as String;
        final builderConfig = builderEntry.value as YamlMap?;
        if (builderConfig == null) continue;

        // Check if this is a reflection-related builder.
        if (builderName.contains('reflection') ||
            builderName == r'$default' ||
            builders.length == 1) {
          final generateFor = builderConfig['generate_for'];
          if (generateFor is YamlList) {
            for (final pattern in generateFor) {
              if (pattern is String) patterns.add(pattern);
            }
          } else if (generateFor is String) {
            patterns.add(generateFor);
          }
        }
      }
    }
  }

  // Also check for top-level generate_for (simplified format).
  final topLevelGenerateFor = yaml['generate_for'];
  if (topLevelGenerateFor is YamlList) {
    for (final pattern in topLevelGenerateFor) {
      if (pattern is String) patterns.add(pattern);
    }
  } else if (topLevelGenerateFor is String) {
    patterns.add(topLevelGenerateFor);
  }

  return patterns;
}

/// Extracts builder `options` from a parsed `build.yaml` [yaml].
Map<String, dynamic> extractBuilderOptions(YamlMap yaml) {
  final options = <String, dynamic>{};

  final targets = yaml['targets'] as YamlMap?;
  if (targets == null) return options;

  for (final targetEntry in targets.entries) {
    final targetConfig = targetEntry.value as YamlMap?;
    if (targetConfig == null) continue;

    final builders = targetConfig['builders'] as YamlMap?;
    if (builders == null) continue;

    for (final builderEntry in builders.entries) {
      final builderConfig = builderEntry.value as YamlMap?;
      if (builderConfig == null) continue;

      final builderOptions = builderConfig['options'] as YamlMap?;
      if (builderOptions != null) {
        for (final optEntry in builderOptions.entries) {
          options[optEntry.key as String] = optEntry.value;
        }
      }
    }
  }

  return options;
}

/// Reads the package name from the `pubspec.yaml` at [projectRoot].
String _getPackageName(String projectRoot) {
  final pubspecFile = File(p.join(projectRoot, 'pubspec.yaml'));
  if (pubspecFile.existsSync()) {
    final content = pubspecFile.readAsStringSync();
    final match =
        RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(content);
    if (match != null) {
      return match.group(1)!;
    }
  }
  return p.basename(projectRoot);
}

/// Heuristic check that [library] (or its visible libraries) references the
/// reflection [packageName].
Future<bool> _usesReflection(
  LibraryElement library,
  StandaloneLibraryResolver resolver,
  String packageName,
) async {
  final identifier = library.identifier;

  try {
    final libs = await resolver.libraries;
    for (final lib in libs) {
      if (lib.identifier.contains(packageName)) {
        return true;
      }
    }
  } catch (_) {
    // Fall back to simple identifier check.
  }

  return identifier.contains(packageName);
}

/// Collects all libraries transitively imported or exported by [entryPoint].
///
/// Mirrors build_runner's behaviour of only seeing libraries reachable from the
/// entry point, excluding test files that aren't imported.
Future<List<LibraryElement>> _getTransitiveLibraries(
  LibraryElement entryPoint,
) async {
  final libs = <LibraryElement>[entryPoint];
  final seen = <String>{entryPoint.identifier};
  final toProcess = [entryPoint];

  while (toProcess.isNotEmpty) {
    final lib = toProcess.removeLast();

    for (final importedLib in lib.firstFragment.importedLibraries) {
      final id = importedLib.identifier;
      if (seen.contains(id)) continue;
      seen.add(id);

      libs.add(importedLib);
      toProcess.add(importedLib);
    }

    for (final exportedLib in lib.exportedLibraries) {
      final id = exportedLib.identifier;
      if (seen.contains(id)) continue;
      seen.add(id);

      libs.add(exportedLib);
      toProcess.add(exportedLib);
    }
  }

  return libs;
}
