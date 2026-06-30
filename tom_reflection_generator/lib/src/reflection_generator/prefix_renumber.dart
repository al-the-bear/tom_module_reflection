// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Deterministic renumbering of generated import prefixes.
///
/// The reflection generator assigns each imported library a prefix
/// (`prefix0`, `prefix1`, …) in the order the library is first *encountered*
/// while walking the element model. Encounter order can differ between
/// environments (analyzer/SDK versions, filesystem traversal order), which
/// makes the emitted code — where those prefixes are embedded — differ even
/// though the set of imported libraries is identical.
///
/// These helpers re-key the prefixes by a stable property (the import URI), so
/// the same set of libraries always yields the same prefix numbering and hence
/// byte-identical output regardless of the order they were discovered.
library;

/// Computes a deterministic prefix renumbering.
///
/// [uriByOldIndex] maps each current prefix index (the `N` in `prefixN`) to the
/// import URI of the library it stands for. Returns a map from old index to new
/// index, where new indices are assigned `0..N-1` in ascending URI order. Ties
/// on URI (which should not occur for distinct libraries) fall back to the old
/// index so the result is always total and stable.
Map<int, int> deterministicPrefixRemap(Map<int, String> uriByOldIndex) {
  final entries = uriByOldIndex.entries.toList()
    ..sort((a, b) {
      final byUri = a.value.compareTo(b.value);
      return byUri != 0 ? byUri : a.key.compareTo(b.key);
    });

  final remap = <int, int>{};
  for (var i = 0; i < entries.length; i++) {
    remap[entries[i].key] = i;
  }
  return remap;
}

/// Rewrites import-prefix usages in [code] according to [remap].
///
/// Only matches `prefixN.` — the qualified-access form the generator emits for
/// imported members (`prefix3.SomeClass`). The trailing dot keeps the rewrite
/// precise: bare tokens inside symbol strings (`'prefix3'`) or identifiers that
/// merely start with `prefix` are left untouched. Indices absent from [remap]
/// are left as-is.
String applyPrefixRemap(String code, Map<int, int> remap) {
  return code.replaceAllMapped(RegExp(r'\bprefix(\d+)\.'), (match) {
    final oldIndex = int.parse(match.group(1)!);
    final newIndex = remap[oldIndex];
    return newIndex == null ? match.group(0)! : 'prefix$newIndex.';
  });
}
