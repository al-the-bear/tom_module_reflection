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

    // Find all public library files
    final libraryFiles = _findPublicLibraries(packagePath);
    if (libraryFiles.isEmpty) {
      // No public libraries — nothing to summarize
      stdout.writeln('    Skipping ${dependency.name}: no public libraries');
      return false;
    }

    stdout.writeln('    Analyzing ${dependency.name}@${dependency.version} '
        '(${libraryFiles.length} libraries)...');

    // Analyze and create summary bundle
    final summaryBytes = await _analyzeAndCreateBundle(
      packagePath,
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

  /// Finds all public Dart library files in a package's `lib/` directory.
  ///
  /// Returns absolute, normalized paths for each `.dart` file found.
  /// Excludes files in `lib/src/` as they are implementation details
  /// (though they are still included as part units when the public
  /// libraries import them).
  List<String> _findPublicLibraries(String packagePath) {
    final libDir = Directory(p.join(packagePath, 'lib'));
    if (!libDir.existsSync()) {
      return [];
    }

    final libraries = <String>[];

    // Find all .dart files directly in lib/ (not in lib/src/)
    for (final entity in libDir.listSync()) {
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
  Future<Uint8List?> _analyzeAndCreateBundle(
    String packagePath,
    List<String> libraryFiles,
  ) async {
    AnalysisContextCollectionImpl? collection;

    try {
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
    }
  }
}
