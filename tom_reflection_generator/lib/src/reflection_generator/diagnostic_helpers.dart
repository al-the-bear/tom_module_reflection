// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

/// Diagnostic and logging helper functions for the reflection generator.
///
/// This file provides utilities for:
/// - Formatting diagnostic messages with source code locations
/// - Logging warnings, errors, and info messages
/// - Retrieving AST nodes and resolved libraries for elements
part of 'generator_implementation.dart';

// ============================================================================
// Logging Functions
// ============================================================================

/// Adds a severe error to the log, using the source code location of `target`
/// to identify the relevant location where the error occurs.
///
/// The [id] parameter should be a unique identifier in the format
/// `[category.subcategory.error_type]` to help identify the error location.
Future<void> _severe(
  String id,
  String message, [
  Element? target,
  LibraryResolver? resolver,
]) async {
  final formattedMessage = '[$id] $message';
  if (target != null && resolver != null) {
    log.severe(await _formatDiagnosticMessage(formattedMessage, target, resolver));
  } else {
    log.severe(formattedMessage);
  }
}

/// Adds a 'fine' message to the log, using the source code location of `target`
/// to identify the relevant location where the issue occurs.
///
/// The [id] parameter should be a unique identifier in the format
/// `[category.subcategory.info_type]` to help identify the message location.
Future<void> _fine(
  String id,
  String message, [
  Element? target,
  LibraryResolver? resolver,
]) async {
  final formattedMessage = '[$id] $message';
  if (target != null && resolver != null) {
    log.fine(await _formatDiagnosticMessage(formattedMessage, target, resolver));
  } else {
    log.fine(formattedMessage);
  }
}

// ============================================================================
// Diagnostic Message Formatting
// ============================================================================

/// Returns a string containing the given [message] and identifying the
/// associated source code location as the location of the given [target].
Future<String> _formatDiagnosticMessage(
  String message,
  Element? target,
  LibraryResolver resolver,
) async {
  Source? source = target?.library?.firstFragment.source;
  if (source == null) return message;
  var locationString = '';
  int? nameOffset = target?.firstFragment.nameOffset;
  // TODO(eernst): 'dart:*' is not considered valid. To survive, we return
  // a message with no location info when `element` is from 'dart:*'. Issue 173.
  LibraryElement? targetLibrary = target?.library;
  if (targetLibrary != null &&
      nameOffset != null &&
      !_isPlatformLibrary(targetLibrary)) {
    final ResolvedLibraryResult? resolvedLibrary = await _getResolvedLibrary(
      targetLibrary,
      resolver,
    );
    if (resolvedLibrary != null) {
      final FragmentDeclarationResult? targetDeclaration = resolvedLibrary
          .getFragmentDeclaration(target!.firstFragment);
      final CompilationUnit? unit = targetDeclaration?.resolvedUnit?.unit;
      final CharacterLocation? location = unit?.lineInfo.getLocation(
        nameOffset,
      );
      if (location != null) {
        locationString = '${location.lineNumber}:${location.columnNumber}';
      }
    }
  }
  return '${source.fullName}:$locationString: $message';
}

// ============================================================================
// AST Resolution Helpers
// ============================================================================

/// Return [AstNode] of declaration of [element], null if synthetic.
Future<AstNode?> _getDeclarationAst(
  Element element,
  LibraryResolver resolver,
) => resolver.astNodeFor(element.firstFragment, resolve: true);

/// Return the [ResolvedLibraryResult] of the given [library].
///
/// Uses the [resolver] to resolve the library from the asset ID of the
/// given [library], thus avoiding an `InconsistentAnalysisException`
/// which will be thrown if we use `library.session` directly.
Future<ResolvedLibraryResult?> _getResolvedLibrary(
  LibraryElement library,
  LibraryResolver resolver,
) async {
  final fileId = await resolver.fileIdForElement(library);
  if (fileId == null) {
    log.severe('[resolver.get_library.no_file_id] Internal error: Cannot get '
        'file ID for library! Library: ${library.name}, '
        'Source: ${library.firstFragment.source.uri}');
    return null;
  }
  final LibraryElement freshLibrary = await resolver.libraryFor(fileId);
  final AnalysisSession freshSession = freshLibrary.session;
  final SomeResolvedLibraryResult someResult = await freshSession
      .getResolvedLibraryByElement(freshLibrary);
  if (someResult is ResolvedLibraryResult) {
    return someResult;
  } else {
    log.severe('[resolver.get_library.inconsistent_session] Internal error: '
        'Inconsistent analysis session! Library: ${library.name}, '
        'Result type: ${someResult.runtimeType}');
    return null;
  }
}

// ============================================================================
// Error Handling
// ============================================================================

/// Throws an error for unreachable code paths.
///
/// This should be called in places where the code should never execute
/// if the program logic is correct. It helps identify bugs in the generator.
Never unreachableError(String id, String message) {
  throw StateError('[$id] Unreachable code: $message');
}
