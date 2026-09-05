// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Tom Reflection Generator — command executor.
///
/// Bridges the tom_build_base v2 `ToolRunner` framework to the shared
/// reflection-generation pipeline. Runs once per traversed project and resolves
/// its input targets from project configuration, per the recorded design
/// decision in `reflection_generator_build_base_migration_plan.md` (step 3).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart'
    show TomBuildConfig, hasTomBuildConfig;
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_reflection_generator/src/generation/reflection_generation.dart';
import 'package:yaml/yaml.dart';

/// The `buildkit.yaml` section key this tool reads its config from.
const _toolKey = 'tom_reflection_generator';

/// Default executor for the tom_reflection_generator tool (single-command).
class ReflectionGeneratorExecutor extends CommandExecutor {
  /// Nested-mode entry point (`--nested`).
  ///
  /// For a single-command tool, `ToolRunner` routes nested invocation here
  /// rather than through traversal (see `tool_runner.dart` `_runNestedMode`).
  /// The host (e.g. `buildkit :reflectiongenerator`) has already changed into
  /// the target project directory before invoking us, so we build a cwd-scoped
  /// [CommandContext] and run the same per-project [execute] logic — there is
  /// exactly one implementation of the generation flow.
  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final cwd = Directory.current.path;
    final context = CommandContext(
      fsFolder: FsFolder(path: cwd),
      natures: const [],
      executionRoot: cwd,
    );
    final result = await execute(context, args);
    return ToolResult.fromItems([result]);
  }

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final projectPath = context.path;
    final verbose = args.verbose;
    final checkOnly = _flag(args, 'check');

    // Resolve the input targets for this project (step-3 precedence:
    // positional args > buildkit.yaml section > build.yaml fallback).
    final resolved = _resolveTargets(projectPath, args);

    // Skip-success when the project opts out (no targets from any source).
    if (resolved.targets.isEmpty) {
      if (verbose) {
        print('  ${context.relativePath}: no reflection targets, skipping');
      }
      return ItemResult.success(path: projectPath, name: context.name);
    }

    // Handle --list mode: report the project and stop.
    if (args.listOnly) {
      print('  ${context.relativePath}');
      return ItemResult.success(path: projectPath, name: context.name);
    }

    try {
      final result = await generateReflection(
        projectRoot: projectPath,
        targets: resolved.targets,
        options: ReflectionGenerationOptions(
          packageName: resolved.packageName,
          outputExtension: resolved.outputExtension,
          useAllCapabilities: resolved.useAllCapabilities,
          allMode: resolved.allMode,
          verbose: verbose,
          noCache: _flag(args, 'no-cache'),
          rebuildCache: _flag(args, 'rebuild-cache'),
          showCacheStatus: _flag(args, 'show-cache-status'),
          cacheOnlyPackages: _stringList(args.extraOptions['cache-only']),
          checkOnly: checkOnly,
        ),
      );

      if (result.cacheStatusShown) {
        return ItemResult.success(path: projectPath, name: context.name);
      }

      if (result.noFilesMatched) {
        if (verbose) {
          print('  ${context.relativePath}: no files matched targets');
        }
        return ItemResult.success(path: projectPath, name: context.name);
      }

      if (result.hasFailures) {
        // A resolution/generation crash is a hard failure — surface it so the
        // buildkit item is marked failed rather than silently "succeeded".
        return ItemResult.failure(
          path: projectPath,
          name: context.name,
          error: 'Reflection generation failed for ${result.failedCount} '
              'file(s) (generated ${result.processedCount}, '
              'skipped ${result.skippedCount})',
        );
      }

      if (result.hasStaleOutputs) {
        // The generated file no longer matches its source. Failing the item is
        // the whole purpose of check mode: this drift is invisible to
        // `dart analyze` and to the test suites, so the build is the only
        // place it can be caught.
        return ItemResult.failure(
          path: projectPath,
          name: context.name,
          error: '${result.staleCount} generated file(s) are stale — '
              '${result.staleFiles.join(', ')}. Regenerate and commit.',
        );
      }

      if (checkOnly) {
        return ItemResult.success(
          path: projectPath,
          name: context.name,
          message: 'Up to date ${result.upToDateCount}, '
              'skipped ${result.skippedCount}',
        );
      }

      return ItemResult.success(
        path: projectPath,
        name: context.name,
        message: 'Generated ${result.processedCount}, '
            'skipped ${result.skippedCount}',
      );
    } catch (e, stack) {
      stderr.writeln('Error processing $projectPath: $e');
      if (verbose) stderr.writeln(stack);
      return ItemResult.failure(
        path: projectPath,
        name: context.name,
        error: '$e',
      );
    }
  }

  /// Resolves targets and options for [projectPath] from all configured
  /// sources, applying CLI-over-config precedence.
  _ResolvedTargets _resolveTargets(String projectPath, CliArgs args) {
    final cliPackage = args.extraOptions['package'] as String?;
    final cliExtension =
        _normalizeExtension(args.extraOptions['extension'] as String?);
    final cliUseAll = _flag(args, 'useAllCapabilities');
    final allMode = _flag(args, 'all');

    // Load the buildkit.yaml `tom_reflection_generator:` section, if any.
    Map<String, dynamic> toolOptions = const {};
    if (hasTomBuildConfig(projectPath, _toolKey)) {
      final config = TomBuildConfig.load(dir: projectPath, toolKey: _toolKey);
      toolOptions = config?.toolOptions ?? const {};
    }

    final configPackage = toolOptions['package'] as String?;
    final configExtension =
        _normalizeExtension(toolOptions['extension'] as String?);
    final configUseAll = toolOptions['use_all_capabilities'] == true;

    // Target source 1: explicit positional args override everything.
    var targets = List<String>.from(args.positionalArgs);

    // Target source 2: buildkit.yaml generate_for globs.
    if (targets.isEmpty) {
      targets = _stringList(toolOptions['generate_for']);
    }

    // Target source 3: build.yaml fallback.
    String? buildYamlExtension;
    if (targets.isEmpty) {
      final fallback = _buildYamlFallback(projectPath, args, verbose: args.verbose);
      targets = fallback.patterns;
      buildYamlExtension = fallback.extension;
    }

    final outputExtension = cliExtension ??
        configExtension ??
        buildYamlExtension ??
        '.reflection.dart';

    return _ResolvedTargets(
      targets: targets,
      packageName: cliPackage ?? configPackage ?? 'tom_reflection',
      outputExtension: outputExtension,
      useAllCapabilities: cliUseAll || configUseAll,
      allMode: allMode,
    );
  }

  /// Loads `generate_for` patterns (and an optional extension override) from the
  /// project's `build.yaml` (or the `--config` path).
  _BuildYamlFallback _buildYamlFallback(
    String projectPath,
    CliArgs args, {
    required bool verbose,
  }) {
    final configName = args.configPath ?? 'build.yaml';
    final configPath = p.isAbsolute(configName)
        ? configName
        : p.join(projectPath, configName);

    final file = File(configPath);
    if (!file.existsSync()) {
      return const _BuildYamlFallback(patterns: [], extension: null);
    }

    final yaml = loadYaml(file.readAsStringSync());
    if (yaml is! YamlMap) {
      return const _BuildYamlFallback(patterns: [], extension: null);
    }

    final patterns = extractGenerateForPatterns(yaml, verbose: verbose);
    final options = extractBuilderOptions(yaml);
    final extension = _normalizeExtension(options['extension'] as String?);

    return _BuildYamlFallback(patterns: patterns, extension: extension);
  }
}

/// Reads a boolean flag from [args] extra options (`true` when present).
bool _flag(CliArgs args, String name) => args.extraOptions[name] == true;

/// Coerces a dynamic config value into a list of strings.
List<String> _stringList(dynamic value) {
  if (value == null) return const [];
  if (value is String) return value.isEmpty ? const [] : [value];
  if (value is List) return value.map((e) => e.toString()).toList();
  return const [];
}

/// Ensures an extension string begins with a dot; returns null when [ext] is
/// null or empty.
String? _normalizeExtension(String? ext) {
  if (ext == null || ext.isEmpty) return null;
  return ext.startsWith('.') ? ext : '.$ext';
}

/// Resolved targets and generation options for a single project.
class _ResolvedTargets {
  const _ResolvedTargets({
    required this.targets,
    required this.packageName,
    required this.outputExtension,
    required this.useAllCapabilities,
    required this.allMode,
  });

  final List<String> targets;
  final String packageName;
  final String outputExtension;
  final bool useAllCapabilities;
  final bool allMode;
}

/// Patterns and optional extension override loaded from a `build.yaml`.
class _BuildYamlFallback {
  const _BuildYamlFallback({required this.patterns, required this.extension});

  final List<String> patterns;
  final String? extension;
}

/// Creates the executor map for the reflection generator tool.
Map<String, CommandExecutor> createReflectionGeneratorExecutors() {
  return {'default': ReflectionGeneratorExecutor()};
}
