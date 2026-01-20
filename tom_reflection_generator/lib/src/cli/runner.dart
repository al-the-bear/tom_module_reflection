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
library;

import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
import 'package:tom_reflection_generator/tom_reflection_generator.dart';
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
  final optionsWithValues = {'--package', '-p', '--extension', '-e', '--config', '-c'};
  
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
    // This shouldn't happen but just in case
    if (_knownCommands.contains(arg) && i == 0) {
      continue;
    }
    
    positionalArgs.add(arg);
  }
  
  return positionalArgs;
}

/// Run in generate mode - process specific files, directories, or glob patterns
Future<void> _runGenerateMode(List<String> args) async {
  final allMode = args.contains('--all');
  final verbose = args.contains('--verbose') || args.contains('-v');
  
  // Parse useAllCapabilities flag - when set, use all capabilities instead of reflector-specified
  final useAllCapabilities = args.contains('--useAllCapabilities');
  
  // Parse package name option
  var packageName = 'tom_reflection';
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--package' || args[i] == '-p') && i + 1 < args.length) {
      packageName = args[i + 1];
    }
  }
  
  // Parse output extension option
  var outputExtension = '.reflection.dart';
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--extension' || args[i] == '-e') && i + 1 < args.length) {
      outputExtension = args[i + 1];
      if (!outputExtension.startsWith('.')) {
        outputExtension = '.$outputExtension';
      }
    }
  }
  
  // Extract positional arguments (files, directories, or glob patterns)
  final targetArgs = _extractPositionalArgs(args);

  if (targetArgs.isEmpty) {
    print('Error: No target file, directory, or glob pattern specified.');
    _printUsage();
    exit(1);
  }

  // Determine project root from first target
  final firstTarget = targetArgs.first;
  var projectRoot = _findProjectRoot(firstTarget);

  if (projectRoot == null) {
    // If first target looks like a glob, try current directory
    if (_isGlobPattern(firstTarget)) {
      projectRoot = _findProjectRoot(Directory.current.path);
    }
    if (projectRoot == null) {
      print('Error: Could not find project root (no pubspec.yaml found).');
      exit(1);
    }
  }
  
  // Normalize the project root path
  projectRoot = p.normalize(projectRoot);

  if (verbose) {
    print('Project root: $projectRoot');
  }

  // Create the standalone resolver
  final resolver = await StandaloneLibraryResolver.create(projectRoot);

  try {
    // Collect all files to process
    final filesToProcess = <String>{};
    
    for (final target in targetArgs) {
      if (_isGlobPattern(target)) {
        // Treat as glob pattern
        if (verbose) {
          print('Matching glob pattern: $target');
        }
        final glob = Glob(target);
        final matches = glob.listSync(root: projectRoot);
        
        for (final entity in matches) {
          if (entity is File && entity.path.endsWith('.dart')) {
            // Skip generated files
            if (!entity.path.endsWith('.reflection.dart') &&
                !entity.path.endsWith('.reflection.dart') &&
                !entity.path.endsWith('.g.dart')) {
              filesToProcess.add(p.normalize(entity.path));
            }
          }
        }
      } else {
        // Regular file or directory path
        final normalizedTarget = p.normalize(p.isAbsolute(target) 
            ? target 
            : p.join(Directory.current.path, target));
        
        if (FileSystemEntity.isDirectorySync(normalizedTarget)) {
          if (allMode) {
            // Process directory recursively
            await _collectDartFilesFromDirectory(normalizedTarget, filesToProcess);
          } else {
            print('Warning: $target is a directory. Use --all to process directories recursively, or use a glob pattern.');
          }
        } else if (FileSystemEntity.isFileSync(normalizedTarget)) {
          if (normalizedTarget.endsWith('.dart') &&
              !normalizedTarget.endsWith('.reflection.dart') &&
              !normalizedTarget.endsWith('.reflection.dart') &&
              !normalizedTarget.endsWith('.g.dart')) {
            filesToProcess.add(normalizedTarget);
          }
        } else {
          print('Warning: Target not found: $target');
        }
      }
    }

    if (filesToProcess.isEmpty) {
      print('No files to process.');
      exit(0);
    }

    print('Found ${filesToProcess.length} files to process.');

    var processedCount = 0;
    var skippedCount = 0;

    for (final filePath in filesToProcess) {
      final result = await _processFile(
        filePath,
        projectRoot,
        resolver,
        verbose,
        packageName,
        outputExtension,
        useAllCapabilities: useAllCapabilities,
      );
      if (result) {
        processedCount++;
      } else {
        skippedCount++;
      }
    }

    print('\nProcessed: $processedCount files');
    if (skippedCount > 0) {
      print('Skipped: $skippedCount files');
    }
  } finally {
    resolver.dispose();
  }

  print('Done.');
}

/// Check if a string looks like a glob pattern
bool _isGlobPattern(String s) {
  return s.contains('*') || s.contains('?') || s.contains('[') || s.contains('{');
}

/// Collect all .dart files from a directory recursively
Future<void> _collectDartFilesFromDirectory(String dirPath, Set<String> files) async {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return;
  
  await for (final entity in dir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      if (!entity.path.endsWith('.reflection.dart') &&
          !entity.path.endsWith('.reflection.dart') &&
          !entity.path.endsWith('.g.dart')) {
        files.add(p.normalize(entity.path));
      }
    }
  }
}

/// Run in build mode - use build.yaml configuration and/or command-line globs
Future<void> _runBuildMode(List<String> args) async {
  final verbose = args.contains('--verbose') || args.contains('-v');
  
  // Parse useAllCapabilities flag - when set, use all capabilities instead of reflector-specified
  final useAllCapabilities = args.contains('--useAllCapabilities');
  
  // Parse config file option (default: build.yaml)
  var configFile = 'build.yaml';
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--config' || args[i] == '-c') && i + 1 < args.length) {
      configFile = args[i + 1];
    }
  }
  
  // Parse package name option
  var packageName = 'tom_reflection';
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--package' || args[i] == '-p') && i + 1 < args.length) {
      packageName = args[i + 1];
    }
  }
  
  // Parse output extension option
  var outputExtension = '.reflection.dart';
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--extension' || args[i] == '-e') && i + 1 < args.length) {
      outputExtension = args[i + 1];
      if (!outputExtension.startsWith('.')) {
        outputExtension = '.$outputExtension';
      }
    }
  }
  
  // Extract command-line glob patterns (positional arguments)
  final cliGlobs = _extractPositionalArgs(args);

  // Normalize config file path
  final configPath = p.isAbsolute(configFile) 
      ? configFile 
      : p.normalize(p.join(Directory.current.path, configFile));
  
  final configFileEntity = File(configPath);
  
  // If command-line globs are provided, they take precedence
  // Otherwise fall back to build.yaml
  List<String> patterns;
  String projectRoot;
  
  if (cliGlobs.isNotEmpty) {
    // Use command-line globs
    patterns = cliGlobs;
    
    // Find project root from current directory
    final root = _findProjectRoot(Directory.current.path);
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
    // Use build.yaml configuration
    if (!configFileEntity.existsSync()) {
      print('Error: Config file not found: $configPath');
      print('Create a build.yaml file, specify a different config with --config,');
      print('or provide glob patterns as arguments.');
      exit(1);
    }
    
    // Find project root from config file's directory
    final root = _findProjectRoot(p.dirname(configPath));
    if (root == null) {
      print('Error: Could not find project root (no pubspec.yaml found near $configPath).');
      exit(1);
    }
    projectRoot = p.normalize(root);

    if (verbose) {
      print('Project root: $projectRoot');
      print('Config file: $configPath');
    }

    // Parse the YAML configuration
    final yamlContent = configFileEntity.readAsStringSync();
    final yaml = loadYaml(yamlContent) as YamlMap?;
    
    if (yaml == null) {
      print('Error: Could not parse config file: $configPath');
      exit(1);
    }

    // Extract generate_for patterns from build.yaml
    patterns = _extractGenerateForPatterns(yaml, verbose);
    
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

    // Check for options in build.yaml
    final options = _extractBuilderOptions(yaml);
    
    // Override extension from build.yaml options if specified
    if (options.containsKey('extension')) {
      outputExtension = options['extension'] as String;
      if (!outputExtension.startsWith('.')) {
        outputExtension = '.$outputExtension';
      }
    }
  }

  // Create the standalone resolver
  final resolver = await StandaloneLibraryResolver.create(projectRoot);

  try {
    // Find all files matching the patterns
    final filesToProcess = <String>{};
    
    for (final pattern in patterns) {
      final glob = Glob(pattern);
      final matches = glob.listSync(root: projectRoot);
      
      for (final entity in matches) {
        if (entity is File && entity.path.endsWith('.dart')) {
          // Skip generated files
          if (!entity.path.endsWith('.reflection.dart') &&
              !entity.path.endsWith('.reflection.dart') &&
              !entity.path.endsWith('.g.dart')) {
            filesToProcess.add(p.normalize(entity.path));
          }
        }
      }
    }

    if (filesToProcess.isEmpty) {
      print('No files matched the generate_for patterns.');
      exit(0);
    }

    print('Found ${filesToProcess.length} files matching patterns.');

    var processedCount = 0;
    var skippedCount = 0;

    for (final filePath in filesToProcess) {
      final result = await _processFile(
        filePath,
        projectRoot,
        resolver,
        verbose,
        packageName,
        outputExtension,
        useAllCapabilities: useAllCapabilities,
      );
      if (result) {
        processedCount++;
      } else {
        skippedCount++;
      }
    }

    print('\nProcessed: $processedCount files');
    print('Skipped: $skippedCount files');
  } finally {
    resolver.dispose();
  }

  print('Done.');
}

/// Extract generate_for patterns from build.yaml
List<String> _extractGenerateForPatterns(YamlMap yaml, bool verbose) {
  final patterns = <String>[];
  
  // Try to find patterns in targets.$default.builders.reflection_generator.generate_for
  final targets = yaml['targets'] as YamlMap?;
  if (targets == null) return patterns;

  for (final targetEntry in targets.entries) {
    final targetConfig = targetEntry.value as YamlMap?;
    if (targetConfig == null) continue;

    final builders = targetConfig['builders'] as YamlMap?;
    if (builders == null) continue;

    // Look for reflection_generator or any builder with generate_for
    for (final builderEntry in builders.entries) {
      final builderName = builderEntry.key as String;
      final builderConfig = builderEntry.value as YamlMap?;
      
      if (builderConfig == null) continue;
      
      // Check if this is a reflection-related builder
      if (builderName.contains('reflection') || 
          builderName == '\$default' ||
          builders.length == 1) {
        final generateFor = builderConfig['generate_for'];
        if (generateFor is YamlList) {
          for (final pattern in generateFor) {
            if (pattern is String) {
              patterns.add(pattern);
            }
          }
        } else if (generateFor is String) {
          patterns.add(generateFor);
        }
      }
    }
  }

  // Also check for top-level generate_for (simplified format)
  final topLevelGenerateFor = yaml['generate_for'];
  if (topLevelGenerateFor is YamlList) {
    for (final pattern in topLevelGenerateFor) {
      if (pattern is String) {
        patterns.add(pattern);
      }
    }
  } else if (topLevelGenerateFor is String) {
    patterns.add(topLevelGenerateFor);
  }

  return patterns;
}

/// Extract builder options from build.yaml
Map<String, dynamic> _extractBuilderOptions(YamlMap yaml) {
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

Future<bool> _processFile(
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
    // Resolve the library
    final library = await resolver.resolveFile(filePath);
    if (library == null) {
      if (verbose) {
        print('  Skipped: Could not resolve library');
      }
      return false;
    }

    // Check if the file uses reflection
    final usesReflection = await _usesReflection(library, resolver, packageName);
    if (!usesReflection) {
      if (verbose) {
        print('  Skipped: Does not use @$packageName');
      }
      return false;
    }

    // Check if it has a main function (entry point)
    if (library.entryPoint == null) {
      if (verbose) {
        print('  Skipped: No main() entry point');
      }
      return false;
    }

    // Generate the reflection code
    final relativePath = p.relative(filePath, from: projectRoot);
    final projectPackageName = _getPackageName(projectRoot);
    final inputId = FileId(projectPackageName, relativePath);
    final outputId = inputId.changeExtension(outputExtension);
    
    // Get only the libraries transitively imported by the entry point
    // (excludes test files that aren't imported by the entry point)
    final visibleLibraries = await _getTransitiveLibraries(library);

    // Build the mirror library with the specified reflection package name
    // By default, use capabilities from reflector unless --useAllCapabilities flag is set
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

    // Write the output file
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

Future<bool> _usesReflection(
  LibraryElement library,
  StandaloneLibraryResolver resolver,
  String packageName,
) async {
  // Check if any imported library is from the specified reflection package
  // by checking the library's identifier which includes imports
  final identifier = library.identifier;
  
  // Simple heuristic: check if the library's source references the package
  // This is a basic check - the full implementation would parse imports properly
  try {
    // Get all visible libraries and check if the package is among them
    final libs = await resolver.libraries;
    for (final lib in libs) {
      if (lib.identifier.contains(packageName)) {
        // Check if this library actually imports it by checking dependencies
        // For now, just return true if the package is in the project
        return true;
      }
    }
  } catch (e) {
    // Fall back to simple identifier check
  }
  
  return identifier.contains(packageName);
}

String? _findProjectRoot(String startPath) {
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

/// Collects all libraries transitively imported or exported by [entryPoint].
/// This mimics build_runner's behavior of only seeing libraries that are
/// reachable from the entry point, excluding test files that aren't imported.
Future<List<LibraryElement>> _getTransitiveLibraries(
  LibraryElement entryPoint,
) async {
  final libs = <LibraryElement>[entryPoint];
  final seen = <String>{entryPoint.identifier};
  final toProcess = [entryPoint];

  while (toProcess.isNotEmpty) {
    final lib = toProcess.removeLast();
    
    // Get imported libraries from the first fragment
    for (final importedLib in lib.firstFragment.importedLibraries) {
      final id = importedLib.identifier;
      if (seen.contains(id)) continue;
      seen.add(id);
      
      libs.add(importedLib);
      toProcess.add(importedLib);
    }
    
    // Get exported libraries
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
