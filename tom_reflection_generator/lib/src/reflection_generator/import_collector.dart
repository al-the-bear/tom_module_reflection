// Copyright (c) 2016, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

part of 'generator_implementation.dart';

/// Information about reflectability for a given library.
/// Collects the libraries that needs to be imported, and gives each library
/// a unique prefix.
class _ImportCollector {
  final _mapping = <LibraryElement, String>{};
  int _count = 0;

  /// Returns the prefix associated with [library]. Iff it is non-empty
  /// it includes the period.
  String _getPrefix(LibraryElement library) {
    if (library.isDartCore) return '';
    String? prefix = _mapping[library];
    if (prefix != null) return prefix;
    prefix = 'prefix$_count.';
    _count++;
    _mapping[library] = prefix;
    return prefix;
  }

  /// Adds [library] to the collected libraries and generate a prefix for it if
  /// it has not been encountered before.
  void _addLibrary(LibraryElement library) {
    if (library.isDartCore) return;
    String? prefix = _mapping[library];
    if (prefix != null) return;
    prefix = 'prefix$_count.';
    _count++;
    _mapping[library] = prefix;
  }

  Iterable<LibraryElement> get _libraries => _mapping.keys;
}
