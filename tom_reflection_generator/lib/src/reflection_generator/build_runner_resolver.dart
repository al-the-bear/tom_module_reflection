// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Build_runner adapter for [LibraryResolver].
///
/// This wraps build_runner's Resolver and AssetId to implement the
/// [LibraryResolver] abstraction used by the reflection generator.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'library_resolver.dart';

/// Adapts build_runner's [Resolver] to the [LibraryResolver] interface.
class BuildRunnerLibraryResolver implements LibraryResolver {
  final Resolver _resolver;

  /// Creates an adapter wrapping the build_runner [resolver].
  BuildRunnerLibraryResolver(this._resolver);

  @override
  Future<FileId?> fileIdForElement(LibraryElement library) async {
    try {
      final assetId = await _resolver.assetIdForElement(library);
      return FileId(assetId.package, assetId.path);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<LibraryElement> libraryFor(FileId fileId) async {
    final assetId = fileId.toAssetId();
    return await _resolver.libraryFor(assetId);
  }

  @override
  Future<AstNode?> astNodeFor(Fragment fragment, {bool resolve = false}) async {
    return await _resolver.astNodeFor(fragment, resolve: resolve);
  }

  @override
  Future<bool> isImportable(LibraryElement library, FileId fromFile) async {
    final fileId = await fileIdForElement(library);
    if (fileId == null) return false;

    // Same package - check if it's in lib/ (always importable)
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
  Future<List<LibraryElement>> get libraries async {
    return await _resolver.libraries.toList();
  }
}

/// Extension to convert between build_runner's AssetId and FileId.
extension AssetIdExtension on AssetId {
  /// Converts this AssetId to a FileId.
  FileId toFileId() => FileId(package, path);
}

/// Extension to convert FileId to build_runner's AssetId.
extension FileIdExtension on FileId {
  /// Converts this FileId to an AssetId.
  AssetId toAssetId() => AssetId(package, path);
}
