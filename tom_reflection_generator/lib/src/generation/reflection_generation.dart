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
    this.checkOnly = false,
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

  /// Compare against the committed output instead of overwriting it.
  ///
  /// Everything up to the final write is identical to an ordinary run — the
  /// same resolver, the same generator, the same source string. Only the last
  /// step differs: the string is compared with what is on disk rather than
  /// replacing it, and any difference fails the run.
  ///
  /// This is the guard against a generated file that no longer matches its
  /// source. That drift is invisible to every other signal: a stale type index
  /// leaves `dart analyze` clean and the suites green, because it is metadata
  /// the tests never read. Costly — a check run is a full generation run — but
  /// it is the only thing that actually answers the question.
  final bool checkOnly;
}

/// Per-file result of [processReflectionFile].
///
/// A crash during resolution/generation is a distinct outcome from a benign
/// skip: it MUST be surfaced loudly and MUST fail the run. Collapsing the two
/// (the historical behaviour) let a poisoned analyzer summary produce a
/// "succeeded — 0 generated, 1 skipped" run that regenerated nothing and left
/// a stale `.reflection.dart` in place.
enum ReflectionFileOutcome {
  /// An output `.reflection.dart` file was written.
  generated,

  /// The file was resolved but legitimately has nothing to generate (does not
  /// use the reflection package, has no `main()` entry point, or resolved to a
  /// non-library result). A benign skip.
  skipped,

  /// Resolution or generation threw. A hard failure — the run must exit
  /// non-zero and must not be reported as succeeded.
  failed,

  /// Check mode only: the committed output matches what would be generated.
  upToDate,

  /// Check mode only: the committed output differs from what would be
  /// generated, or is missing entirely. The source and its generated
  /// counterpart have diverged; the run must exit non-zero.
  stale,
}

/// Writes [generatedSource] to [outputPath], or in check mode compares the two.
///
/// This is the single point where generating and checking diverge, which is why
/// it is a named function rather than an `if` inside [processReflectionFile]:
/// everything before it — resolver, capabilities, generator — is shared by
/// construction, so a check cannot drift from the generation it is checking.
///
/// Comparison is exact. A benign formatting difference would be reported as
/// drift, which sounds harsh but converges: the remedy is to regenerate, and
/// once regenerated the bytes agree permanently. The alternative — normalising
/// before comparing — would have to guess which differences are benign, and
/// guessing wrong in that direction hides the very defect this exists to catch.
///
/// A missing output counts as [ReflectionFileOutcome.stale]. A source that
/// should have a generated counterpart and does not is drift, and the remedy is
/// the same: run the generator.
ReflectionFileOutcome applyGeneratedOutput({
  required String outputPath,
  required String generatedSource,
  required bool checkOnly,
}) {
  final output = File(outputPath);

  if (!checkOnly) {
    output.writeAsStringSync(generatedSource);
    print('  Generated: $outputPath');
    return ReflectionFileOutcome.generated;
  }

  if (!output.existsSync()) {
    stderr.writeln('  STALE (missing): $outputPath');
    return ReflectionFileOutcome.stale;
  }

  if (output.readAsStringSync() == generatedSource) {
    return ReflectionFileOutcome.upToDate;
  }

  stderr.writeln('  STALE (differs): $outputPath');
  return ReflectionFileOutcome.stale;
}

/// Outcome of a reflection-generation run.
class ReflectionGenerationResult {
  const ReflectionGenerationResult({
    required this.processedCount,
    required this.skippedCount,
    this.failedCount = 0,
    this.upToDateCount = 0,
    this.staleCount = 0,
    this.staleFiles = const [],
    this.cacheStatusShown = false,
    this.noFilesMatched = false,
  });

  /// Number of files for which reflection was generated.
  final int processedCount;

  /// Number of files that were resolved but benignly skipped (no reflection
  /// usage, no entry point, or a non-library result).
  final int skippedCount;

  /// Number of files whose resolution or generation crashed. These are hard
  /// failures, never benign skips.
  final int failedCount;

  /// Check mode: number of files whose committed output already matches.
  final int upToDateCount;

  /// Check mode: number of files whose committed output differs or is missing.
  final int staleCount;

  /// Check mode: the project-relative paths behind [staleCount].
  ///
  /// Carried rather than merely counted because the count alone does not tell
  /// anyone what to regenerate, and the whole point of the check is to name the
  /// file that drifted.
  final List<String> staleFiles;

  /// True when the run only displayed cache status and generated nothing.
  final bool cacheStatusShown;

  /// True when no input files matched the supplied targets.
  final bool noFilesMatched;

  /// Whether any target file failed to resolve or generate. When true the run
  /// must be treated as failed (non-zero exit).
  bool get hasFailures => failedCount > 0;

  /// Whether any committed output has drifted from its source (check mode).
  ///
  /// Independent of [hasFailures]: a crash and a stale output are different
  /// faults with different remedies, and a run can produce both.
  bool get hasStaleOutputs => staleCount > 0;
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
    var failedCount = 0;
    var upToDateCount = 0;
    final failedFiles = <String>[];
    final staleFiles = <String>[];

    // Build-runner-style progress so a run is observable even in non-verbose
    // mode (e.g. when nested under buildkit, where this tool's stdout is the
    // only signal the user sees).
    final total = filesToProcess.length;
    final stopwatch = Stopwatch()..start();
    print(options.checkOnly
        ? 'Checking reflection for $total target file(s)...'
        : 'Generating reflection for $total target file(s)...');

    var index = 0;
    for (final filePath in filesToProcess) {
      index++;
      if (total > 1) {
        print('  [$index/$total] ${p.relative(filePath, from: root)}');
      }
      final outcome = await processReflectionFile(
        filePath,
        root,
        resolver,
        options.verbose,
        options.packageName,
        options.outputExtension,
        useAllCapabilities: options.useAllCapabilities,
        checkOnly: options.checkOnly,
      );
      switch (outcome) {
        case ReflectionFileOutcome.generated:
          processedCount++;
        case ReflectionFileOutcome.skipped:
          skippedCount++;
        case ReflectionFileOutcome.failed:
          failedCount++;
          failedFiles.add(p.relative(filePath, from: root));
        case ReflectionFileOutcome.upToDate:
          upToDateCount++;
        case ReflectionFileOutcome.stale:
          staleFiles.add(
            p.relative(
              filePath.replaceAll('.dart', options.outputExtension),
              from: root,
            ),
          );
      }
    }

    stopwatch.stop();
    final elapsed = _formatElapsed(stopwatch.elapsed);
    final verb = options.checkOnly ? 'check' : 'generation';

    if (failedCount > 0) {
      // A crash on an explicit target must be loud and must fail the run —
      // never reported as "succeeded". Write to stderr so it stands out even
      // when this tool is nested under another builder.
      stderr.writeln('Reflection $verb FAILED after $elapsed — '
          '$processedCount generated, $skippedCount skipped, '
          '$failedCount failed.');
      for (final failed in failedFiles) {
        stderr.writeln('  FAILED: $failed');
      }
    }

    if (staleFiles.isNotEmpty) {
      stderr.writeln('Reflection check FAILED after $elapsed — '
          '${staleFiles.length} generated file(s) no longer match their '
          'source, $upToDateCount up to date, $skippedCount skipped.');
      for (final stale in staleFiles) {
        stderr.writeln('  STALE: $stale');
      }
      // The remedy is one command, and naming it here saves the reader working
      // out that a *check* failure is repaired by an ordinary *generate* run.
      stderr.writeln('Regenerate with the project\'s reflection_generation.sh '
          '(or `dart run tom_reflection_generator build`) and commit the '
          'result.');
    } else if (failedCount == 0) {
      print(options.checkOnly
          ? 'Reflection check succeeded after $elapsed — '
              '$upToDateCount up to date, $skippedCount skipped.'
          : 'Reflection generation succeeded after $elapsed — '
              '$processedCount generated, $skippedCount skipped.');
    }

    return ReflectionGenerationResult(
      processedCount: processedCount,
      skippedCount: skippedCount,
      failedCount: failedCount,
      upToDateCount: upToDateCount,
      staleCount: staleFiles.length,
      staleFiles: staleFiles,
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
/// Returns [ReflectionFileOutcome.generated] when an output file was written,
/// [ReflectionFileOutcome.skipped] when the file legitimately has nothing to
/// generate (does not use reflection, has no entry point, or resolves to a
/// non-library result), and [ReflectionFileOutcome.failed] when resolution or
/// generation *threw*. A thrown exception is a hard failure — it is reported
/// prominently and never collapsed into a benign skip.
///
/// With [checkOnly] the generated source is compared against the committed
/// output instead of replacing it, yielding [ReflectionFileOutcome.upToDate] or
/// [ReflectionFileOutcome.stale]. See [applyGeneratedOutput].
Future<ReflectionFileOutcome> processReflectionFile(
  String filePath,
  String projectRoot,
  LibraryResolver resolver,
  bool verbose,
  String packageName,
  String outputExtension, {
  bool useAllCapabilities = false,
  bool checkOnly = false,
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
      return ReflectionFileOutcome.skipped;
    }

    // Check if the file uses reflection.
    final usesReflection = await _usesReflection(library, resolver, packageName);
    if (!usesReflection) {
      if (verbose) {
        print('  Skipped: Does not use @$packageName');
      }
      return ReflectionFileOutcome.skipped;
    }

    // Check if it has a main function (entry point).
    if (library.entryPoint == null) {
      if (verbose) {
        print('  Skipped: No main() entry point');
      }
      return ReflectionFileOutcome.skipped;
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

    // Write the output file, or in check mode compare against it.
    final outputPath = filePath.replaceAll('.dart', outputExtension);
    return applyGeneratedOutput(
      outputPath: outputPath,
      generatedSource: generatedSource,
      checkOnly: checkOnly,
    );
  } catch (e, st) {
    // A crash here (e.g. a corrupt analyzer summary in the cache throwing
    // RangeError) is a hard failure, not a skip. Report it prominently on
    // stderr and signal failure so the run exits non-zero.
    stderr.writeln('  FAILED to process $filePath: $e');
    if (verbose) {
      stderr.writeln('  Stack: $st');
    }
    return ReflectionFileOutcome.failed;
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
  LibraryResolver resolver,
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
