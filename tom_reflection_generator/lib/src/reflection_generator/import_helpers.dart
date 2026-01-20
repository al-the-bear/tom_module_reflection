// Copyright (c) 2025, the Tom project authors.
// Please see the AUTHORS file for details. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: avoid_dynamic

part of 'generator_implementation.dart';

// ============================================================================
// Import Helpers
// ============================================================================
//
// This file provides utilities for handling imports in generated reflection
// code. It determines whether elements can be imported, resolves import URIs,
// and handles the complexities of package/asset/file URI schemes.
//
// Key functions:
//   - _isImportable: Check if an element can be imported
//   - _isImportableLibrary: Check if a library can be imported
//   - _getImportUri: Get the appropriate import URI for a library
//   - _assetIdToUri: Convert asset IDs to importable URI strings
// ============================================================================

/// Answers true if [element] can be imported into [generatedLibraryId].
///
/// This checks whether the element's library is accessible from the generated
/// code. Private elements and elements from internal SDK libraries cannot be
/// imported.
///
/// Parameters:
///   - [element]: The element to check for importability
///   - [generatedLibraryId]: The target library where imports will be added
///   - [resolver]: The library resolver for asset resolution
///
/// Returns true if the element's library can be imported.
// TODO(sigurdm) implement: Make a test that tries to reflect on native/private
// classes.
Future<bool> _isImportable(
  Element element,
  FileId generatedLibraryId,
  LibraryResolver resolver,
) async {
  return await _isImportableLibrary(
    element.library!,
    generatedLibraryId,
    resolver,
  );
}

/// Answers true if [library] can be imported into [generatedLibraryId].
///
/// A library is importable if:
///   - It's not a dart: library, or
///   - It's a public dart: library (in [sdkLibraryNames])
///
/// Internal dart: libraries (like dart:_internal) cannot be imported.
///
/// Parameters:
///   - [library]: The library element to check
///   - [generatedLibraryId]: The target library where imports will be added
///   - [resolver]: The library resolver for URI resolution
///
/// Returns true if the library can be imported.
Future<bool> _isImportableLibrary(
  LibraryElement library,
  FileId generatedLibraryId,
  LibraryResolver resolver,
) async {
  Uri importUri = await _getImportUri(library, resolver, generatedLibraryId);
  return importUri.scheme != 'dart' || sdkLibraryNames.contains(importUri.path);
}

/// Converts an [assetId] to an importable URI string relative to [from].
///
/// This function handles two cases:
///   1. lib/ assets: Converted to package: URIs (e.g., package:foo/bar.dart)
///   2. non-lib/ assets: Converted to relative paths if same package
///
/// Cross-package imports from non-lib/ directories are not allowed and will
/// log a severe error.
///
/// Parameters:
///   - [assetId]: The asset to convert to a URI
///   - [from]: The source file for relative path calculation
///   - [messageTarget]: Element for error reporting context
///   - [resolver]: The library resolver for error reporting
///
/// Returns the URI string, or null if the asset cannot be imported.
Future<String?> _assetIdToUri(
  FileId assetId,
  FileId from,
  Element messageTarget,
  LibraryResolver resolver,
) async {
  if (!assetId.path.startsWith('lib/')) {
    // Cannot do absolute imports of non lib-based assets.
    // Cross-package imports must be from lib/ directory.
    if (assetId.package != from.package) {
      await _severe(
        'import.cross_package.non_lib',
        'Attempt to generate non-lib import from different package. '
        'Asset: ${assetId.package}/${assetId.path}, From: ${from.package}/${from.path}. '
        'Cross-package imports must be from lib/ directory.',
        messageTarget,
      );
      return null;
    }
    // Same package: use relative path
    return Uri(
      path: path.url.relative(assetId.path, from: path.url.dirname(from.path)),
    ).toString();
  }

  // lib/ directory: convert to package: URI
  return Uri.parse(
    'package:${assetId.package}/${assetId.path.substring(4)}',
  ).toString();
}

/// Gets a URI which would be appropriate for importing the library.
///
/// This function handles multiple URI schemes:
///   - **dart:** URIs are returned as-is (SDK libraries)
///   - **package:** URIs are returned as-is
///   - **asset:** URIs are converted to package: or relative URIs
///   - **file:** URIs (from standalone resolver) are converted appropriately
///
/// Note that the returned URI may represent a non-importable file such as
/// a part file, so callers should use [_isImportableLibrary] to verify.
///
/// Parameters:
///   - [lib]: The library element to get an import URI for
///   - [resolver]: The library resolver for asset resolution
///   - [from]: The source file for relative path calculation
///
/// Returns the appropriate import URI for the library.
Future<Uri> _getImportUri(
  LibraryElement lib,
  LibraryResolver resolver,
  FileId from,
) async {
  Source source = lib.firstFragment.source;
  Uri uri = source.uri;

  if (uri.scheme == 'asset') {
    // Asset URIs occur when library is accessed via path rather than package:
    // For instance `asset:reflection/example/example_lib.dart`
    // when the library is in the example/ directory.
    String package = uri.pathSegments[0];
    String uriPath = uri.path.substring(package.length + 1);
    return Uri(
      path: await _assetIdToUri(FileId(package, uriPath), from, lib, resolver),
    );
  }

  if (uri.scheme == 'file') {
    // Handle file:// URIs from standalone resolver.
    // Convert to package: URI or relative path based on file location.
    final fileId = await resolver.fileIdForElement(lib);
    if (fileId != null) {
      if (fileId.path.startsWith('lib/')) {
        // Convert lib/ files to package: URIs
        return Uri.parse(
          'package:${fileId.package}/${fileId.path.substring(4)}',
        );
      } else {
        // For non-lib files, use relative path from generated file
        final relativePath = await _assetIdToUri(fileId, from, lib, resolver);
        if (relativePath != null) {
          return Uri(path: relativePath);
        }
      }
    }
  }

  // Return dart: and package: URIs as-is
  return uri;
}
