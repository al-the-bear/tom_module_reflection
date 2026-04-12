// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/summary2/bundle_writer.dart';
import 'package:analyzer/src/summary2/package_bundle_format.dart';
import 'package:path/path.dart' as p;

import 'dependency_resolver.dart';
import 'package_dependency.dart';
import 'summary_cache_manager.dart';

/// Result of generating summaries for a batch of packages.
class SummaryGenerationResult {
  /// Number of summaries successfully generated.
  final int generated;

  /// Number of summaries that were already cached.
  final int skipped;

  /// Number of summaries that failed to generate.
  final int failed;

  /// Error messages for failed packages (keyed by package name).
  final Map<String, String> errors;

  const SummaryGenerationResult({
    required this.generated,
    required this.skipped,
    required this.failed,
    required this.errors,
  });

  /// Total packages processed.
  int get total => generated + skipped + failed;

  @override
  String toString() =>
      'SummaryGenerationResult(generated: $generated, skipped: $skipped, '
      'failed: $failed)';
}

/// Generates analyzer summaries for packages.
///
/// Creates binary `.sum` files containing pre-analyzed type information
/// for stable dependencies (hosted and SDK packages). These summaries
/// can be loaded by the analyzer to skip re-analysis of unchanged packages.
///
/// ## Usage
///
/// ```dart
/// final cacheManager = SummaryCacheManager('/path/to/workspace');
/// final depResolver = DependencyResolver();
/// final generator = SummaryGenerator(
///   cacheManager: cacheManager,
///   dependencyResolver: depResolver,
/// );
///
/// // Generate summaries for all missing dependencies
/// final deps = await depResolver.resolveCacheableDependencies('/path/to/project');
/// final result = await generator.generateMissingSummaries(deps);
/// print('Generated ${result.generated} summaries');
/// ```
class SummaryGenerator {
  /// The cache manager for reading/writing summary files.
  final SummaryCacheManager cacheManager;

  /// The dependency resolver for locating package sources.
  final DependencyResolver dependencyResolver;

  /// Creates a summary generator.
  SummaryGenerator({
    required this.cacheManager,
    required this.dependencyResolver,
  });

  /// Generates a summary for a single package.
  ///
  /// Creates a temporary [AnalysisContextCollectionImpl], analyzes all public
  /// libraries in the package, and writes the summary bundle to cache.
  ///
  /// Does nothing if the summary is already cached.
  ///
  /// Throws if the package path cannot be resolved or analysis fails.
  Future<bool> generateSummary(PackageDependency dependency) async {
    if (!dependency.isCacheable) {
      return false;
    }

    // Check if already cached
    if (await cacheManager.hasSummary(dependency.name, dependency.version)) {
      return false;
    }

    // Resolve package path
    final packagePath = await _resolvePackagePath(dependency);
    if (packagePath == null) {
      throw StateError(
        'Could not resolve path for package ${dependency.name}@${dependency.version}',
      );
    }

    // Find all library files (public and internal)
    final libraryFiles = _findAllLibraries(packagePath);
    if (libraryFiles.isEmpty) {
      // No libraries — nothing to summarize
      stdout.writeln('    Skipping ${dependency.name}: no public libraries');
      return false;
    }

    stdout.writeln('    Analyzing ${dependency.name}@${dependency.version} '
        '(${libraryFiles.length} libraries)...');

    // Analyze and create summary bundle
    final summaryBytes = await _analyzeAndCreateBundle(
      packagePath,
      dependency.name,
      libraryFiles,
    );

    if (summaryBytes == null) {
      stdout.writeln('    Failed to create bundle for ${dependency.name}');
      return false;
    }

    // Write to cache
    await cacheManager.writeSummary(
      dependency.name,
      dependency.version,
      summaryBytes,
    );

    final sizeKB = (summaryBytes.length / 1024).toStringAsFixed(1);
    stdout.writeln('    Cached ${dependency.name}@${dependency.version} '
        '(${sizeKB} KB)');

    return true;
  }

  /// Generates summaries for all dependencies that are missing from the cache.
  ///
  /// Skips dependencies that are already cached or not cacheable.
  /// Continues processing on individual failures, collecting errors.
  Future<SummaryGenerationResult> generateMissingSummaries(
    List<PackageDependency> dependencies, {
    void Function(String package, int current, int total)? onProgress,
  }) async {
    final cacheable =
        dependencies.where((d) => d.isCacheable).toList();

    var generated = 0;
    var skipped = 0;
    var failed = 0;
    final errors = <String, String>{};

    for (var i = 0; i < cacheable.length; i++) {
      final dep = cacheable[i];
      onProgress?.call(dep.name, i + 1, cacheable.length);

      // Check if already cached
      if (await cacheManager.hasSummary(dep.name, dep.version)) {
        skipped++;
        continue;
      }

      try {
        final success = await generateSummary(dep);
        if (success) {
          generated++;
        } else {
          skipped++;
        }
      } catch (e) {
        failed++;
        errors[dep.name] = e.toString();
      }
    }

    return SummaryGenerationResult(
      generated: generated,
      skipped: skipped,
      failed: failed,
      errors: errors,
    );
  }

  /// Resolves the filesystem path for a dependency.
  Future<String?> _resolvePackagePath(PackageDependency dependency) async {
    switch (dependency.source) {
      case 'hosted':
        return dependencyResolver.getHostedPackagePath(dependency);
      case 'sdk':
        return await dependencyResolver.getSdkPackagePath(dependency);
      default:
        return null;
    }
  }

  /// Finds all Dart library files in a package's `lib/` directory.
  ///
  /// Returns absolute, normalized paths for each `.dart` file found,
  /// including files in `lib/src/`. All libraries need to be included
  /// because public libraries may export/re-export symbols from internal
  /// src/ libraries, and those need to be in the summary.
  List<String> _findAllLibraries(String packagePath) {
    final libDir = Directory(p.join(packagePath, 'lib'));
    if (!libDir.existsSync()) {
      return [];
    }

    final libraries = <String>[];

    // Find all .dart files recursively in lib/ (including lib/src/)
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        libraries.add(p.normalize(entity.path));
      }
    }

    return libraries;
  }

  /// Creates a summary bundle from already-resolved library elements.
  ///
  /// Uses [BundleWriter] to serialize each library's type information,
  /// then wraps the result with [PackageBundleBuilder] to create the
  /// final `.sum` binary format.
  Uint8List _createSummaryBundle(List<LibraryElement> libraries) {
    final bundleWriter = BundleWriter();
    final bundleBuilder = PackageBundleBuilder();

    for (final library in libraries) {
      bundleWriter.writeLibraryElement(library as LibraryElementImpl);

      // Register the library URI and its fragment (unit) URIs
      final libraryUri = library.uri.toString();
      final unitUris = library.fragments
          .map((fragment) => fragment.source.uri.toString())
          .toList();
      bundleBuilder.addLibrary(libraryUri, unitUris);
    }

    final writerResult = bundleWriter.finish();
    return bundleBuilder.finish(
      resolutionBytes: writerResult.resolutionBytes,
    );
  }

  /// Analyzes a package and creates its summary bundle.
  ///
  /// Creates a temporary [AnalysisContextCollectionImpl] for the package,
  /// resolves all public libraries, and serializes them using
  /// [_createSummaryBundle].
  ///
  /// Creates a temporary `.dart_tool/package_config.json` to ensure the
  /// analyzer uses proper `package:` URIs instead of `file://` URIs.
  Future<Uint8List?> _analyzeAndCreateBundle(
    String packagePath,
    String packageName,
    List<String> libraryFiles,
  ) async {
    AnalysisContextCollectionImpl? collection;
    final dartToolDir = Directory(p.join(packagePath, '.dart_tool'));
    final packageConfigFile = File(p.join(dartToolDir.path, 'package_config.json'));
    final hadDartTool = dartToolDir.existsSync();
    final hadPackageConfig = packageConfigFile.existsSync();

    try {
      // Create minimal package_config.json for proper package: URI resolution
      if (!dartToolDir.existsSync()) {
        dartToolDir.createSync(recursive: true);
      }
      
      // Get language version from pubspec.yaml if possible
      final languageVersion = _getLanguageVersion(packagePath);
      
      // Write a minimal package_config.json
      final packageConfig = '''{
  "configVersion": 2,
  "packages": [
    {
      "name": "$packageName",
      "rootUri": "../",
      "packageUri": "lib/",
      "languageVersion": "$languageVersion"
    }
  ]
}''';
      packageConfigFile.writeAsStringSync(packageConfig);

      // Create analysis context for the package
      collection = AnalysisContextCollectionImpl(
        includedPaths: [p.normalize(p.absolute(packagePath))],
      );

      final resolvedLibraries = <LibraryElement>[];

      for (final filePath in libraryFiles) {
        try {
          final context = collection.contextFor(filePath);
          final session = context.currentSession;

          final result = await session.getResolvedLibrary(filePath);
          if (result is! ResolvedLibraryResult) {
            continue;
          }

          final libraryElement = result.element;

          // BundleWriter requires LibraryElementImpl
          if (libraryElement is! LibraryElementImpl) {
            continue;
          }

          resolvedLibraries.add(libraryElement);
        } catch (e) {
          // Skip individual library failures — log but continue
          stderr.writeln(
            'Warning: Failed to analyze ${p.basename(filePath)}: $e',
          );
        }
      }

      if (resolvedLibraries.isEmpty) {
        return null;
      }

      return _createSummaryBundle(resolvedLibraries);
    } finally {
      await collection?.dispose();
      
      // Clean up the temporary package_config.json
      if (!hadPackageConfig && packageConfigFile.existsSync()) {
        packageConfigFile.deleteSync();
      }
      if (!hadDartTool && dartToolDir.existsSync()) {
        try {
          dartToolDir.deleteSync(recursive: true);
        } catch (_) {
          // Ignore cleanup failures
        }
      }
    }
  }
  
  /// Extracts the language version from pubspec.yaml environment constraint.
  /// Returns a default version if not found.
  String _getLanguageVersion(String packagePath) {
    final pubspecFile = File(p.join(packagePath, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      return '2.12'; // Default to null-safety era
    }
    
    final content = pubspecFile.readAsStringSync();
    
    // Look for environment.sdk constraint like "sdk: ^3.0.0" or "sdk: '>=3.0.0 <4.0.0'"
    final sdkMatch = RegExp(r'''sdk:\s*['"]?[>=^]*(\d+\.\d+)''', multiLine: true)
        .firstMatch(content);
    if (sdkMatch != null) {
      return sdkMatch.group(1)!;
    }
    
    return '2.12'; // Default
  }
}
