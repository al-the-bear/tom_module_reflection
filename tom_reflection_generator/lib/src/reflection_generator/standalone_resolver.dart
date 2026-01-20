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
import 'package:path/path.dart' as p;

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
  static Future<StandaloneLibraryResolver> create(String projectRoot) async {
    var absolutePath = p.isAbsolute(projectRoot)
        ? projectRoot
        : p.join(Directory.current.path, projectRoot);
    
    // Normalize the path (resolve .. and . components)
    absolutePath = p.normalize(absolutePath);

    final collection = AnalysisContextCollection(
      includedPaths: [absolutePath],
    );

    final packageName = _getPackageName(absolutePath);

    return StandaloneLibraryResolver._(collection, absolutePath, packageName);
  }

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
      final absolutePath = p.join(_projectRoot, fileId.path);
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
      final absolutePath = p.join(_projectRoot, fileId.path);
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
  Future<LibraryElement?> resolveFile(String filePath) async {
    final absolutePath =
        p.isAbsolute(filePath) ? filePath : p.join(_projectRoot, filePath);

    try {
      final context = _collection.contextFor(absolutePath);
      final result =
          await context.currentSession.getResolvedLibrary(absolutePath);
      if (result is ResolvedLibraryResult) {
        return result.element;
      }
    } catch (e) {
      // File could not be resolved
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
