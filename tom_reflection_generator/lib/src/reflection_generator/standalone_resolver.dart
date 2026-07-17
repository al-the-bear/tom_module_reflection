// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Standalone implementation of [LibraryResolver] using the Dart analyzer.
///
/// This implementation doesn't require build_runner and can be used
/// from CLI tools or other standalone contexts.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:path/path.dart' as p;
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart'
    show resolveDartSdkPath;

import 'library_resolver.dart';

/// A standalone [LibraryResolver] implementation using the Dart analyzer.
///
/// This creates an analysis context for the project and resolves libraries
/// without needing build_runner.
class StandaloneLibraryResolver implements LibraryResolver {
  final AnalysisContextCollection _collection;
  final String _projectRoot;
  final String _packageName;
  List<LibraryElement>? _librariesCache;

  /// Creates a resolver for the project at [projectRoot].
  ///
  /// The [projectRoot] should be the directory containing pubspec.yaml.
  StandaloneLibraryResolver._(
    this._collection,
    this._projectRoot,
    this._packageName,
  );

  /// Creates a new [StandaloneLibraryResolver] for the given project.
  ///
  /// The [projectRoot] should be the absolute path to the project directory
  /// containing pubspec.yaml.
  ///
  /// If [librarySummaryPaths] is provided, the analyzer will load pre-built
  /// summary files (`.sum`) for the listed packages, skipping full analysis
  /// of those dependencies. This can dramatically reduce analysis time for
  /// projects with many stable dependencies.
  ///
  /// If [sdkSummaryPath] is provided, it's used as the Dart SDK summary.
  /// If not provided but [librarySummaryPaths] is set, we look for an
  /// existing `sdk.sum` in `.dart_tool/build_resolvers/`.
  static Future<StandaloneLibraryResolver> create(
    String projectRoot, {
    List<String>? librarySummaryPaths,
    String? sdkSummaryPath,
  }) async {
    var absolutePath = p.isAbsolute(projectRoot)
        ? projectRoot
        : p.join(Directory.current.path, projectRoot);
    
    // Normalize the path (resolve .. and . components)
    absolutePath = p.normalize(absolutePath);

    final AnalysisContextCollection collection;
    if (librarySummaryPaths != null && librarySummaryPaths.isNotEmpty) {
      // Try to find SDK summary if not provided
      var effectiveSdkSummaryPath = sdkSummaryPath;
      if (effectiveSdkSummaryPath == null) {
        effectiveSdkSummaryPath = _findSdkSummary(absolutePath);
      }

      // Use AnalysisContextCollectionImpl to pass librarySummaryPaths,
      // which enables the analyzer to skip full analysis of summarized
      // packages (they are loaded as InSummarySource).
      collection = AnalysisContextCollectionImpl(
        includedPaths: [absolutePath],
        librarySummaryPaths: librarySummaryPaths,
        sdkSummaryPath: effectiveSdkSummaryPath,
        sdkPath: _resolveSdkPath(),
      );
    } else {
      collection = AnalysisContextCollection(
        includedPaths: [absolutePath],
        sdkPath: _resolveSdkPath(),
      );
    }

    final packageName = _getPackageName(absolutePath);

    return StandaloneLibraryResolver._(collection, absolutePath, packageName);
  }

  /// Looks for an existing SDK summary.
  ///
  /// Checks our cache first (`<workspace>/.tom/analyzer-cache/sdk@<version>.sum`),
  /// then falls back to build_resolvers (`.dart_tool/build_resolvers/sdk.sum`).
  /// Returns the path if found, null otherwise.
  static String? _findSdkSummary(String projectRoot) {
    // Check our own cache first
    final dartVersion = Platform.version.split(' ').first;
    final versionMatch = RegExp(r'^(\d+\.\d+\.\d+)').firstMatch(dartVersion);
    final version = versionMatch?.group(1) ?? dartVersion;
    final ourCachePath = p.join(
      projectRoot, '.tom', 'analyzer-cache', 'sdk@$version.sum',
    );
    if (File(ourCachePath).existsSync()) {
      return ourCachePath;
    }

    // Fall back to build_resolvers
    final sdkSumPath = p.join(
      projectRoot, '.dart_tool', 'build_resolvers', 'sdk.sum',
    );
    if (File(sdkSumPath).existsSync()) {
      return sdkSumPath;
    }
    return null;
  }

  /// Locates the Dart SDK directory at runtime, or `null` to let the analyzer
  /// fall back to its default (executable-relative) detection.
  ///
  /// Delegates to [resolveDartSdkPath] from `tom_analyzer_shared`, the single
  /// source of truth for SDK location across the Tom analyzer tooling. Without
  /// an explicit SDK path the analyzer derives one from
  /// `Platform.resolvedExecutable`, which is correct under `dart run` but wrong
  /// for an AOT-compiled executable (`dart compile exe`) — there it points at
  /// the tool itself and the SDK cannot be found. Resolving the real SDK makes
  /// the compiled `reflectiongenerator` binary work when invoked as
  /// `buildkit :reflectiongenerator`.
  static String? _resolveSdkPath() => resolveDartSdkPath();

  static String _getPackageName(String projectRoot) {
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

  @override
  Future<FileId?> fileIdForElement(LibraryElement library) async {
    final uri = library.identifier;
    final parsedUri = Uri.parse(uri);

    if (parsedUri.scheme == 'package') {
      final package = parsedUri.pathSegments.first;
      final path = 'lib/${parsedUri.pathSegments.skip(1).join('/')}';
      return FileId(package, path);
    }

    if (parsedUri.scheme == 'file') {
      final filePath = parsedUri.toFilePath();
      if (filePath.startsWith(_projectRoot)) {
        final relativePath = p.relative(filePath, from: _projectRoot);
        return FileId(_packageName, relativePath);
      }
    }

    return null;
  }

  @override
  Future<bool> isImportable(LibraryElement library, FileId fromFile) async {
    final fileId = await fileIdForElement(library);
    if (fileId == null) return false;

    // Same package - check if it's in lib/ (always importable)
    // or a relative import within the same directory structure
    if (fileId.package == fromFile.package) {
      if (fileId.path.startsWith('lib/')) return true;
      // For non-lib files, they can only import each other if in same tree
      return !fileId.path.startsWith('test/') ||
          fromFile.path.startsWith('test/');
    }

    // Different package - must be in lib/
    return fileId.path.startsWith('lib/');
  }

  @override
  Future<LibraryElement> libraryFor(FileId fileId) async {
    // Convert FileId to absolute path
    if (fileId.package == _packageName) {
      // `fileId.path` uses forward slashes (`lib/src/...`); joining it onto a
      // backslash-rooted project path on Windows yields a mixed-separator,
      // non-normalized path that the analyzer rejects ("Only absolute
      // normalized paths are supported"). Normalize to the platform separator.
      final absolutePath = p.normalize(p.join(_projectRoot, fileId.path));
      final context = _collection.contextFor(absolutePath);
      final result =
          await context.currentSession.getResolvedLibrary(absolutePath);
      if (result is ResolvedLibraryResult) {
        return result.element;
      }
      throw StateError(
        '[resolver.library_for.local_not_resolved] '
        'Cannot resolve library at $absolutePath',
      );
    }

    // External package - resolve through URI
    final uriString = fileId.uri.toString();
    final context = _collection.contexts.first;
    final libraryResult = await context.currentSession.getLibraryByUri(uriString);
    if (libraryResult is LibraryElementResult) {
      return libraryResult.element;
    }
    throw StateError(
      '[resolver.library_for.external_not_resolved] '
      'Cannot resolve library for $fileId (URI: $uriString)',
    );
  }

  @override
  Future<AstNode?> astNodeFor(Fragment fragment, {bool resolve = false}) async {
    // Get the library containing this fragment
    final element = fragment.element;
    final library = element.library;
    if (library == null) return null;

    // Resolve the library to get AST with declarations
    final fileId = await fileIdForElement(library);
    if (fileId == null) return null;

    ResolvedLibraryResult? result;
    if (fileId.package == _packageName) {
      // Normalize: see the note in `libraryFor` — forward-slash FileId paths
      // joined onto a backslash project root are rejected by the analyzer.
      final absolutePath = p.normalize(p.join(_projectRoot, fileId.path));
      final context = _collection.contextFor(absolutePath);
      final libResult =
          await context.currentSession.getResolvedLibrary(absolutePath);
      if (libResult is ResolvedLibraryResult) {
        result = libResult;
      }
    } else {
      // External library - use URI and getResolvedLibraryByElement
      final context = _collection.contexts.first;
      final libResult =
          await context.currentSession.getResolvedLibraryByElement(library);
      if (libResult is ResolvedLibraryResult) {
        result = libResult;
      }
    }

    if (result == null) return null;

    // Get the declaration for this fragment
    final declaration = result.getFragmentDeclaration(fragment);
    return declaration?.node;
  }

  @override
  Future<List<LibraryElement>> get libraries async {
    if (_librariesCache != null) return _librariesCache!;

    final libs = <LibraryElement>[];
    final seen = <String>{};

    // First, collect all libraries from analyzed files
    for (final context in _collection.contexts) {
      for (final filePath in context.contextRoot.analyzedFiles()) {
        if (!filePath.endsWith('.dart')) continue;
        if (seen.contains(filePath)) continue;
        seen.add(filePath);

        try {
          final result =
              await context.currentSession.getResolvedLibrary(filePath);
          if (result is ResolvedLibraryResult) {
            libs.add(result.element);
          }
        } catch (e) {
          // Skip files that can't be resolved
        }
      }
    }

    // Now, traverse all imported libraries to include dependencies
    final toProcess = List<LibraryElement>.from(libs);
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
      
      // Get exported libraries from LibraryElement
      for (final exportedLib in lib.exportedLibraries) {
        final id = exportedLib.identifier;
        if (seen.contains(id)) continue;
        seen.add(id);
        
        libs.add(exportedLib);
        toProcess.add(exportedLib);
      }
    }

    _librariesCache = libs;
    return libs;
  }

  /// Resolves a specific file and returns its library element.
  ///
  /// Returns `null` only when the analyzer produces a non-library result for
  /// the file (e.g. it is a part file) — a benign skip. A failure *inside*
  /// resolution (for example a corrupt analyzer summary in the cache, which
  /// throws `RangeError` from the bundle reader) is a hard failure: it is
  /// **rethrown**, never swallowed. Callers must surface it loudly and fail the
  /// run rather than reporting a "successful" regen that regenerated nothing.
  @override
  Future<LibraryElement?> resolveFile(String filePath) async {
    // Normalize so a mixed-separator path (e.g. a forward-slash relative path
    // joined onto a backslash project root on Windows) is accepted by the
    // analyzer, which requires absolute, normalized paths.
    final absolutePath = p.normalize(
      p.isAbsolute(filePath) ? filePath : p.join(_projectRoot, filePath),
    );

    final context = _collection.contextFor(absolutePath);
    final result =
        await context.currentSession.getResolvedLibrary(absolutePath);
    if (result is ResolvedLibraryResult) {
      return result.element;
    }
    return null;
  }

  /// Disposes resources used by this resolver.
  void dispose() {
    // AnalysisContextCollection doesn't have a dispose method,
    // but we can clear the cache
    _librariesCache = null;
  }
}
