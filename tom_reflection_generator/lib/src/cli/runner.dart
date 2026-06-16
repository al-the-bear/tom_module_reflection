// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Standalone CLI tool to generate reflection code without build_runner.
///
/// Usage:
/// ```
/// # Generate mode (default) - process specific files
/// dart run tom_reflection_generator <entry_point.dart>
/// dart run tom_reflection_generator generate lib/main.dart
/// dart run tom_reflection_generator --all lib/
///
/// # Build mode - use build.yaml configuration
/// dart run tom_reflection_generator build
/// dart run tom_reflection_generator build --config custom.yaml
/// ```
///
/// This generates `.reflection.dart` files for Dart files that use
/// the @reflection annotation.
///
/// All actual generation work is delegated to the shared pipeline in
/// `lib/src/generation/reflection_generation.dart`, so this file holds only
/// CLI argument parsing, usage text, and mode dispatch.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_reflection_generator/src/generation/reflection_generation.dart';
import 'package:yaml/yaml.dart';

/// Known command names - these are not treated as glob patterns
const _knownCommands = {'build', 'generate'};

Future<void> runReflectionGeneratorCli(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    exit(1);
  }

  final helpMode = args.contains('--help') || args.contains('-h');
  if (helpMode) {
    _printUsage();
    exit(0);
  }

  // Determine the command
  final firstArg = args.first;
  final isBuildCommand = firstArg == 'build';
  final isGenerateCommand = firstArg == 'generate';

  // Remove command from args if it's a known command
  final commandArgs = (isBuildCommand || isGenerateCommand)
      ? args.skip(1).toList()
      : args;

  if (isBuildCommand) {
    await _runBuildMode(commandArgs);
  } else {
    await _runGenerateMode(commandArgs);
  }
}

/// Extract positional arguments (globs/files) from command-line args.
/// Filters out flags, options, and their values.
List<String> _extractPositionalArgs(List<String> args) {
  final positionalArgs = <String>[];
  final optionsWithValues = {
    '--package',
    '-p',
    '--extension',
    '-e',
    '--config',
    '-c',
    '--cache-only',
  };

  var skipNext = false;
  for (var i = 0; i < args.length; i++) {
    if (skipNext) {
      skipNext = false;
      continue;
    }

    final arg = args[i];

    // Skip flags
    if (arg.startsWith('-')) {
      // Check if this option takes a value
      if (optionsWithValues.contains(arg)) {
        skipNext = true;
      }
      continue;
    }

    // Skip known commands (only at position 0, but we've already removed them)
    if (_knownCommands.contains(arg) && i == 0) {
      continue;
    }

    positionalArgs.add(arg);
  }

  return positionalArgs;
}

/// Parses all `--cache-only PKG` values from [args].
List<String> _parseCacheOnlyPackages(List<String> args) {
  final packages = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--cache-only' && i + 1 < args.length) {
      packages.add(args[i + 1]);
      i++; // skip the value
    }
  }
  return packages;
}

/// Parses the shared option flags common to both modes from [args].
ReflectionGenerationOptions _parseOptions(
  List<String> args, {
  required bool allMode,
}) {
  final verbose = args.contains('--verbose') || args.contains('-v');
  final useAllCapabilities = args.contains('--useAllCapabilities');

  var packageName = 'tom_reflection';
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--package' || args[i] == '-p') && i + 1 < args.length) {
      packageName = args[i + 1];
    }
  }

  var outputExtension = '.reflection.dart';
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--extension' || args[i] == '-e') && i + 1 < args.length) {
      outputExtension = args[i + 1];
      if (!outputExtension.startsWith('.')) {
        outputExtension = '.$outputExtension';
      }
    }
  }

  return ReflectionGenerationOptions(
    packageName: packageName,
    outputExtension: outputExtension,
    useAllCapabilities: useAllCapabilities,
    allMode: allMode,
    verbose: verbose,
    noCache: args.contains('--no-cache'),
    rebuildCache: args.contains('--rebuild-cache'),
    showCacheStatus: args.contains('--show-cache-status'),
    cacheOnlyPackages: _parseCacheOnlyPackages(args),
  );
}

/// Run in generate mode - process specific files, directories, or glob patterns
Future<void> _runGenerateMode(List<String> args) async {
  final allMode = args.contains('--all');
  final options = _parseOptions(args, allMode: allMode);

  // Extract positional arguments (files, directories, or glob patterns).
  final targetArgs = _extractPositionalArgs(args);

  if (targetArgs.isEmpty) {
    print('Error: No target file, directory, or glob pattern specified.');
    _printUsage();
    exit(1);
  }

  // Determine project root from first target.
  final firstTarget = targetArgs.first;
  var projectRoot = findProjectRoot(firstTarget);

  if (projectRoot == null) {
    // If first target looks like a glob, try current directory.
    if (isGlobPattern(firstTarget)) {
      projectRoot = findProjectRoot(Directory.current.path);
    }
    if (projectRoot == null) {
      print('Error: Could not find project root (no pubspec.yaml found).');
      exit(1);
    }
  }

  final result = await generateReflection(
    projectRoot: projectRoot,
    targets: targetArgs,
    options: options,
  );

  _reportResult(result);
}

/// Run in build mode - use build.yaml configuration and/or command-line globs
Future<void> _runBuildMode(List<String> args) async {
  final options = _parseOptions(args, allMode: false);
  final verbose = options.verbose;

  // Parse config file option (default: build.yaml).
  var configFile = 'build.yaml';
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--config' || args[i] == '-c') && i + 1 < args.length) {
      configFile = args[i + 1];
    }
  }

  // Extract command-line glob patterns (positional arguments).
  final cliGlobs = _extractPositionalArgs(args);

  // Normalize config file path.
  final configPath = p.isAbsolute(configFile)
      ? configFile
      : p.normalize(p.join(Directory.current.path, configFile));

  final configFileEntity = File(configPath);

  // If command-line globs are provided, they take precedence; otherwise fall
  // back to build.yaml.
  List<String> patterns;
  String projectRoot;
  var outputExtension = options.outputExtension;

  if (cliGlobs.isNotEmpty) {
    patterns = cliGlobs;

    final root = findProjectRoot(Directory.current.path);
    if (root == null) {
      print('Error: Could not find project root (no pubspec.yaml found).');
      exit(1);
    }
    projectRoot = p.normalize(root);

    if (verbose) {
      print('Project root: $projectRoot');
      print('Using command-line glob patterns: $patterns');
    }
  } else {
    if (!configFileEntity.existsSync()) {
      print('Error: Config file not found: $configPath');
      print('Create a build.yaml file, specify a different config with '
          '--config,');
      print('or provide glob patterns as arguments.');
      exit(1);
    }

    final root = findProjectRoot(p.dirname(configPath));
    if (root == null) {
      print('Error: Could not find project root (no pubspec.yaml found near '
          '$configPath).');
      exit(1);
    }
    projectRoot = p.normalize(root);

    if (verbose) {
      print('Project root: $projectRoot');
      print('Config file: $configPath');
    }

    final yamlContent = configFileEntity.readAsStringSync();
    final yaml = loadYaml(yamlContent) as YamlMap?;

    if (yaml == null) {
      print('Error: Could not parse config file: $configPath');
      exit(1);
    }

    patterns = extractGenerateForPatterns(yaml, verbose: verbose);

    if (patterns.isEmpty) {
      print('Error: No generate_for patterns found in $configFile.');
      print('Expected format:');
      print('  targets:');
      print('    \$default:');
      print('      builders:');
      print('        reflection_generator:');
      print('          generate_for:');
      print('            - lib/**/*.dart');
      exit(1);
    }

    if (verbose) {
      print('Generate patterns from build.yaml: $patterns');
    }

    // Override extension from build.yaml options if specified.
    final builderOptions = extractBuilderOptions(yaml);
    if (builderOptions.containsKey('extension')) {
      outputExtension = builderOptions['extension'] as String;
      if (!outputExtension.startsWith('.')) {
        outputExtension = '.$outputExtension';
      }
    }
  }

  final result = await generateReflection(
    projectRoot: projectRoot,
    targets: patterns,
    options: ReflectionGenerationOptions(
      packageName: options.packageName,
      outputExtension: outputExtension,
      useAllCapabilities: options.useAllCapabilities,
      allMode: false,
      verbose: options.verbose,
      noCache: options.noCache,
      rebuildCache: options.rebuildCache,
      showCacheStatus: options.showCacheStatus,
      cacheOnlyPackages: options.cacheOnlyPackages,
    ),
  );

  _reportResult(result, alwaysPrintSkipped: true);
}

/// Prints the summary for a completed run and exits when appropriate.
void _reportResult(
  ReflectionGenerationResult result, {
  bool alwaysPrintSkipped = false,
}) {
  if (result.cacheStatusShown) {
    // --show-cache-status is info-only; exit after displaying.
    exit(0);
  }

  if (result.noFilesMatched) {
    print('No files to process.');
    exit(0);
  }

  print('\nProcessed: ${result.processedCount} files');
  if (alwaysPrintSkipped || result.skippedCount > 0) {
    print('Skipped: ${result.skippedCount} files');
  }

  print('Done.');
}

void _printUsage() {
  print('''
Reflection Generator - Standalone reflection code generator

Commands:
  generate    Process specific files, directories, or glob patterns (default)
  build       Use build.yaml configuration or command-line glob patterns

Usage:
  dart run tom_reflection_generator [command] [options] <targets...>

Generate Mode (default):
  dart run tom_reflection_generator <file.dart>
  dart run tom_reflection_generator generate <file.dart>
  dart run tom_reflection_generator --all <directory>
  dart run tom_reflection_generator "lib/**/*.dart"
  dart run tom_reflection_generator "lib/**/*.dart" "test/**_test.dart"

Build Mode:
  dart run tom_reflection_generator build
  dart run tom_reflection_generator build --config custom.yaml
  dart run tom_reflection_generator build "lib/**/*.dart"
  dart run tom_reflection_generator build "test/**_test.dart"

Glob Patterns:
  You can specify one or more glob patterns instead of individual files.
  Patterns must be quoted to prevent shell expansion.
  If glob patterns are provided to 'build' mode, they override build.yaml.

  Common patterns:
    "lib/**/*.dart"       All Dart files in lib/ recursively
    "test/**_test.dart"   All test files in test/ recursively
    "lib/*.dart"          Only Dart files directly in lib/
    "{lib,bin}/**/*.dart" Files in both lib/ and bin/

Options:
  --all               Process all .dart files in directory recursively
  --config, -c        Config file path (default: build.yaml) (build mode only)
  --package, -p       Reflection package name (default: tom_reflection)
                      Use 'reflection' for original reflection.dart package
  --extension, -e     Output file extension (default: .reflection.dart)
                      Use '.reflection.dart' to match build_runner output
  --useAllCapabilities
                      Use all capabilities for full reflection instead of
                      capabilities specified in reflector class
  --no-cache          Disable summary caching for dependencies
  --rebuild-cache     Force regenerate all cached summaries
  --cache-only PKG    Only cache specific package(s) (repeatable)
  --show-cache-status Show which packages have cached summaries
  --verbose, -v       Print detailed progress information
  --help, -h          Show this help message

Examples:
  # Generate mode - process specific files or patterns
  dart run tom_reflection_generator lib/main.dart
  dart run tom_reflection_generator "lib/**/*.dart"
  dart run tom_reflection_generator "lib/**/*.dart" "test/**_test.dart"
  dart run tom_reflection_generator --all lib/
  dart run tom_reflection_generator --all --verbose test/

  # Build mode - use build.yaml or command-line patterns
  dart run tom_reflection_generator build
  dart run tom_reflection_generator build --config my_build.yaml
  dart run tom_reflection_generator build "test/**_test.dart"
  dart run tom_reflection_generator build -v

build.yaml format:
  targets:
    \$default:
      builders:
        reflection_generator:
          generate_for:
            - lib/**/*.dart
            - test/**_test.dart
          options:
            formatted: true
            extension: .reflection.dart
''');
}
