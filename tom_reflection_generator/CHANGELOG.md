# Changelog

## 1.1.2

- Upgraded `tom_analyzer_shared` to `^0.3.0`. Analyzer summaries are now stored
  in the shared Tom tool-cache directory (resolved via `ToolCacheLocator`:
  `TOM_TOOL_CACHE` → ancestor `.tom/tom_tool_cache` → Dart tool dir) instead of
  a fixed `<workspace>/.tom/analyzer-cache`, so the same hosted-package summary
  is reused across projects and sibling generators. No API change.

## 1.1.1

- **Bug fix**: Fixed incorrect prefix assignment for mixin-variant types
  in `NonGenericClassMirrorImpl` generation. When a type is a synthetic
  mixin application (e.g. `TomFormStringField with TomGenericFieldDecorationMixin`),
  the generic type parameter now uses the prefix for the *superclass*'s
  library rather than the synthetic `MixinApplication`'s library. Previously
  this caused `'SomeType' isn't a type` compile errors after regeneration.

## 1.1.0

- **Standalone CLI**: Added analyzer summary caching for 26x faster generation
  (38s vs 1269s on a Flutter project with 75 dependencies)
- Summary cache stored in `.tom/analyzer-cache/` with per-package versioned `.sum` files
- SDK summary self-generation with Flutter embedder support
- Topological dependency ordering for correct cross-package type resolution
- Fixed default parameter value extraction from summary-backed elements
- Fixed metadata annotation extraction from summary-backed elements
- CLI output now matches build_runner output byte-for-byte

## 1.0.2

- Bug fixes and internal improvements

## 1.0.1

- Repository reorganization: Moved to tom_module_reflection repository
- Changed tom_reflection dependency to pub.dev version

## 1.0.0

- Extracted the reflection builder/CLI from `tom_build` and `tom_build_tools`.
- Added reusable CLI runner (`runReflectionGeneratorCli`).
- Published documentation and tests within the new package.
