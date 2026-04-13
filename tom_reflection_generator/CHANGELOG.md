# Changelog

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
