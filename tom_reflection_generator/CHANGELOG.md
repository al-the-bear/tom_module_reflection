# Changelog

## 1.4.0

- **New: `--check` verifies that committed `*.reflection.dart` files still
  match their sources.** The generator runs exactly as usual and then compares
  what it would emit against what is on disk, instead of overwriting it; it
  exits non-zero naming every file that differs or is missing, and modifies
  nothing.

  This closes a gap in which a reflected signature change left its generated
  counterpart stale and *nothing noticed*. Widening a parameter from `String?`
  to `Object?` in two packages changed a type index in each generated seed;
  neither was regenerated, and both were committed stale. Measured at the time:
  `dart analyze` was clean and both suites fully green, with identical test
  counts before and after regeneration — the stale part is metadata the tests
  never exercise. "Remember to regenerate" was the only thing standing in the
  way of a committed mismatch, and a habit is not a control.

  Available on the CLI, in nested/buildkit mode (a stale file fails the item),
  and through each project's `reflection_generation.sh --check`. A check costs a
  full generation run (~20–30 s per package) because answering the question
  means actually generating. See `doc/reflection_generator.md` § Check Mode.

## 1.3.2

- **Fix: a type annotation no longer carries the originating library's import
  prefix into the generated file.** Type annotations in constant expressions
  were emitted by prepending the generated prefix to the annotation's *source
  text*. For an annotation written through an import prefix — `lib.Imported`,
  or a type argument such as `List<lib.Imported>` — the source prefix came
  along, producing `prefixNN.lib.Imported`: the name `lib` is not in scope in
  the generated library, so it fails to compile with "The name 'lib' is being
  referenced through the prefix 'prefixNN', but it isn't defined in any of the
  libraries imported using that prefix". The helper now rebuilds the annotation
  from its parts (prefix + simple name + type arguments, the latter re-qualified
  recursively) instead of reusing source text. See
  `src/reflection_generator/constant_extractor.dart`.
- `dynamic` and `void` used as type arguments (e.g. `<String, dynamic>{}`) no
  longer raise a spurious `constant.type_annotation.unsupported` severe
  diagnostic. They belong to no library, take no prefix, and were already
  emitted correctly — only the diagnostic was wrong.
- **Test: the 1.3.1 type-literal fix is now covered.** A new end-to-end suite
  (`test/default_value_prefix_test.dart`) runs the real generator over a fixture
  whose optional parameters put a type literal in every position it can occupy —
  bare, map key, map value, list element, set element, nested collection, and
  behind a source import prefix — asserts the generated prefix in each, and
  resolves the emitted library with `dart analyze` so an unqualified name in any
  *other* position fails the suite too.

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
