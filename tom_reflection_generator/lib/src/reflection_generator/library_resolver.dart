// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Abstraction layer for library resolution in the reflection generator.
///
/// This allows the reflection generator to work with both:
/// - build_runner's Resolver (for integration with build system)
/// - Standalone analyzer (for CLI usage without build_runner)
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

/// Represents a file identifier with package name and path.
///
/// This is an abstraction over build_runner's AssetId that can work
/// standalone without the build package dependency.
class FileId {
  /// The package name containing this file.
  final String package;

  /// The path within the package (e.g., 'lib/src/foo.dart').
  final String path;

  /// Creates a file identifier.
  const FileId(this.package, this.path);

  /// Creates a new FileId with a different extension.
  FileId changeExtension(String newExtension) {
    final basePath = path.endsWith('.dart')
        ? path.substring(0, path.length - 5)
        : path;
    return FileId(package, '$basePath$newExtension');
  }

  /// The package URI for this file.
  Uri get uri {
    if (path.startsWith('lib/')) {
      return Uri.parse('package:$package/${path.substring(4)}');
    }
    return Uri.parse('package:$package/$path');
  }

  @override
  String toString() => '$package|$path';

  @override
  bool operator ==(Object other) =>
      other is FileId && other.package == package && other.path == path;

  @override
  int get hashCode => Object.hash(package, path);
}

/// Abstract interface for resolving library information.
///
/// Implementations provide access to analyzed libraries and their
/// package/path information without depending on build_runner.
abstract class LibraryResolver {
  /// Gets the FileId for a library element.
  ///
  /// Returns null if the library's location cannot be determined.
  Future<FileId?> fileIdForElement(LibraryElement library);

  /// Gets a library element for a FileId.
  ///
  /// Throws if the library cannot be resolved.
  Future<LibraryElement> libraryFor(FileId fileId);

  /// Gets the AST node for an element.
  ///
  /// Returns null for synthetic elements.
  Future<AstNode?> astNodeFor(Fragment fragment, {bool resolve = false});

  /// Checks if a library can be imported from another location.
  ///
  /// Returns true if [library] can be imported from [fromFile].
  Future<bool> isImportable(LibraryElement library, FileId fromFile);

  /// Gets all libraries visible from the project.
  Future<List<LibraryElement>> get libraries;
}
