# Changelog

## 1.3.1

- **Fix: type-literal annotation arguments are now import-prefixed.** A bare
  type name used as a constant annotation argument — e.g. the `EmailService`
  in `@TomComponent(EmailService)` — is parsed as a `TypeLiteral`, an
  expression kind the constant extractor did not handle. It fell through to
  `Expression.toSource()` and was emitted UNQUALIFIED (`EmailService`), which
  is an undefined name in the generated `.reflection.dart` library and fails
  to compile (`Error: Undefined name 'EmailService'`). The extractor now
  routes `TypeLiteral` through the type-annotation helper, so it carries the
  correct import prefix (`prefixNN.EmailService`) and the owning library is
  registered for import. See
  `src/reflection_generator/constant_extractor.dart` (RCL1).

## 1.3.0

- **Deterministic output.** Import prefixes (`prefix0`, `prefix1`, …) are now
  numbered by a stable sort of the import URIs instead of the order libraries
  happened to be encountered while walking the element model. The same set of
  imported libraries therefore always yields byte-identical generated code,
  regardless of analyzer/SDK traversal order — eliminating spurious
  cross-machine diffs in `.reflection.dart` outputs. See
  `src/reflection_generator/prefix_renumber.dart`.
- **Build-runner-style progress.** `generateReflection` now prints a start
  banner (`Generating reflection for N target file(s)...`), a per-file
  `[i/N]` progress line for multi-file runs, and a timed completion summary
  (`Reflection generation succeeded after Xs — N generated, M skipped.`) in
  non-verbose mode, so a run is observable when nested under buildkit (where
  this tool's stdout is the only signal the user sees).
- Raised the `tom_analyzer_shared` floor to `>=0.6.1` for the verbose
  per-summary cache-usage trace (`using {pkg}@{ver}.sum from cache at {path}`),
  which lets a generation run be audited for actual cache reads.

## 1.2.1

- Track our latest published components: `tom_analyzer_shared` floor raised to
  `>=0.6.0` (ToolCacheLocator shared tool-cache root). All in-workspace
  dependencies now use lower-bound-only constraints (no upper cap) so
  `pub upgrade` resolves to our latest versions during active development.

## 1.2.0

- **Analyzer 10 migration**: widened the `analyzer` constraint from `^8.0.0`
  to `^10.0.0` and bumped `tom_analyzer_shared` to `^0.4.0` (analyzer-10 build).
  The generator's `package:analyzer/src/dart/constant/*` and element/type
  imports resolve unchanged on analyzer 10.
- The 20 `Element.isSynthetic` call sites (deprecated in analyzer 10 in favour
  of the `isOriginX` flag family) are now routed through a single
  `_elementIsSynthetic` helper. This preserves exact behaviour — including the
  local `MixinApplication` shim's `isSynthetic` override (which is relied upon
  at real call sites and would route through `noSuchMethod` if migrated to
  `isOriginDeclaration`) — and confines the deprecation suppression to one
  documented place. `isOriginDeclaration` is not a drop-in replacement because
  it is not declared on the base `Element` type.
- No behavioural change; supersedes the out-of-band `1.1.2` (identical source).

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
