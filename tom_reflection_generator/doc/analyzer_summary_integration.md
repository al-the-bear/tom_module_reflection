# Analyzer Summary Integration

<!-- docspec: tom-specs/1.0 -->

## Overview

This document specifies the integration of Dart analyzer summary caching into the `tom_reflection_generator`. The goal is to dramatically reduce analysis time by pre-generating and caching binary summaries for stable dependencies (pub.dev packages, Flutter SDK, Dart SDK).

**Problem:** The reflection generator currently takes ~21 minutes to process a Flutter project:
- 816s (13.6 min) building
- 457s (7.6 min) analyzing

Most of this time is spent re-analyzing the same stable dependencies (Flutter framework, Dart SDK, pub.dev packages) that don't change between runs.

**Solution:** Generate `.sum` summary files once per package version and reuse them in subsequent runs.

## How Dart Analyzer Summaries Work

### Summary Format

The analyzer uses a binary `PackageBundle` format containing:

1. **Library metadata** - URIs and unit references
2. **Resolution bytes** - Pre-computed type information, declarations, and element data
3. **String table** - Deduplicated strings for efficiency

Key classes:
- `PackageBundleReader` - Reads binary summary files
- `BundleWriter` - Creates summary bundles from analyzed libraries
- `SummaryDataStore` - Container that holds multiple loaded summaries
- `InSummarySource` - Marks a source as coming from a summary (analysis is skipped)

### Automatic Skip Detection

When the analyzer encounters an import/export that resolves to an `InSummarySource`, it:
1. Wraps it in `LibraryImportWithInSummarySource` or `LibraryExportWithInSummarySource`
2. Reads element information directly from the summary bytes
3. **Skips full AST parsing and analysis** for those libraries

This means providing summaries automatically prevents re-analysis of covered packages.

## Specification

### Cache Location

```
<workspace-root>/.tom/analyzer-cache/{package}@{version}.sum
```

Examples:
- `.tom/analyzer-cache/flutter@3.32.0.sum`
- `.tom/analyzer-cache/dart_core@3.8.0.sum`
- `.tom/analyzer-cache/provider@6.1.2.sum`
- `.tom/analyzer-cache/tom_flutter_ui@0.5.3.sum`

**Rationale:** 
- Workspace-local allows different projects to have different dependency versions
- Version in filename ensures cache invalidation when dependencies update
- `.tom/` folder is the standard location for Tom tooling metadata

### Summary Types

| Type | Key Format | Source |
|------|------------|--------|
| **Dart SDK** | `dart_core@{sdk_version}.sum` | `dart:*` libraries from SDK |
| **Flutter SDK** | `flutter@{flutter_version}.sum` | `package:flutter/*` |
| **Pub packages** | `{package}@{version}.sum` | From pub.dev or path dependencies with version |
| **Local packages** | Not cached | Workspace packages without stable versions |

### Cache Validity

A summary is valid when:
1. The summary file exists at the expected path
2. The package version in the filename matches the resolved dependency version
3. The Dart SDK version used to create the summary matches current SDK

**Cache key components:**
```
{package_name}@{package_version}:{sdk_major}.{sdk_minor}
```

The SDK version is encoded in the summary file itself via `PackageBundleSdk`.

### Generator Integration Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Generator Start                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Stage 1: Dependency Discovery                                │
│ - Parse pubspec.yaml and pubspec.lock                        │
│ - Resolve all transitive dependencies with versions          │
│ - Identify Flutter/Dart SDK versions                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Stage 2: Summary Cache Check                                 │
│ - For each versioned dependency:                             │
│   - Check if .tom/analyzer-cache/{pkg}@{ver}.sum exists      │
│   - Validate SDK version compatibility                       │
│ - Build list of missing summaries                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Stage 3: Summary Generation (if needed)                      │
│ - For each missing summary:                                  │
│   - Create minimal AnalysisContextCollection for package     │
│   - Analyze all public library files                         │
│   - Write summary using BundleWriter                         │
│   - Save to cache location                                   │
│ - Progress: "Generating summary for {package}@{version}..."  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Stage 4: Cached Analysis Run                                 │
│ - Load all available summaries into SummaryDataStore         │
│ - Create AnalysisDriver with externalSummaries parameter     │
│ - Analyze only user code (summaries auto-skip dependencies)  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Stage 5: Reflection Code Generation                          │
│ - Process analyzed libraries as before                       │
│ - Generate .reflection.dart files                            │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Plan

### Phase 1: Infrastructure (Estimated: 4-6 hours)

#### 1.1 Create Summary Cache Manager

**File:** `lib/src/summary/summary_cache_manager.dart`

```dart
/// Manages the analyzer summary cache for a workspace.
class SummaryCacheManager {
  final String workspaceRoot;
  final String cacheDirectory;
  
  SummaryCacheManager(this.workspaceRoot)
      : cacheDirectory = p.join(workspaceRoot, '.tom', 'analyzer-cache');
  
  /// Returns the cache file path for a package.
  String getCachePath(String packageName, String version);
  
  /// Checks if a valid summary exists for the package.
  Future<bool> hasSummary(String packageName, String version);
  
  /// Loads all available summaries into a SummaryDataStore.
  Future<SummaryDataStore> loadSummaries(List<PackageDependency> dependencies);
  
  /// Writes a summary for a package.
  Future<void> writeSummary(String packageName, String version, Uint8List bytes);
  
  /// Clears outdated summaries (different SDK version).
  Future<void> cleanOutdated();
}
```

#### 1.2 Create Dependency Resolver

**File:** `lib/src/summary/dependency_resolver.dart`

```dart
/// Resolves project dependencies with their versions.
class DependencyResolver {
  /// Parses pubspec.lock to get exact dependency versions.
  Future<List<PackageDependency>> resolveVersionedDependencies(String projectRoot);
  
  /// Gets Flutter SDK version from flutter --version.
  Future<String> getFlutterVersion();
  
  /// Gets Dart SDK version.
  String getDartVersion();
}

class PackageDependency {
  final String name;
  final String version;
  final String source; // 'hosted', 'git', 'path', 'sdk'
  final String? path; // For path dependencies
  
  bool get isCacheable => source == 'hosted' || source == 'sdk';
}
```

### Phase 2: Summary Generator (Estimated: 6-8 hours)

#### 2.1 Create Summary Generator

**File:** `lib/src/summary/summary_generator.dart`

```dart
/// Generates analyzer summaries for packages.
class SummaryGenerator {
  final SummaryCacheManager cacheManager;
  
  /// Generates a summary for a single package.
  /// 
  /// Creates a temporary AnalysisContextCollection, analyzes
  /// all public libraries, and writes the summary bundle.
  Future<void> generateSummary(PackageDependency dependency);
  
  /// Generates summaries for all missing dependencies.
  Future<void> generateMissingSummaries(
    List<PackageDependency> dependencies,
    {void Function(String package, int current, int total)? onProgress}
  );
}
```

#### 2.2 Implement Bundle Writing

```dart
Future<Uint8List> _createSummaryBundle(
  String packagePath,
  List<LibraryElement> libraries,
) async {
  final bundleWriter = BundleWriter();
  
  for (final library in libraries) {
    bundleWriter.writeLibraryElement(library as LibraryElementImpl);
  }
  
  final result = bundleWriter.finish();
  return result.resolutionBytes;
}
```

### Phase 3: Integration (Estimated: 4-6 hours)

#### 3.1 Modify StandaloneLibraryResolver

**File:** `lib/src/reflection_generator/standalone_resolver.dart`

Add support for external summaries:

```dart
class StandaloneLibraryResolver implements LibraryResolver {
  final SummaryDataStore? _externalSummaries;
  
  static Future<StandaloneLibraryResolver> create(
    String projectRoot, {
    SummaryDataStore? externalSummaries,
  }) async {
    // ... existing code ...
    
    // Create AnalysisContextCollection with summary support
    final collection = AnalysisContextCollection(
      includedPaths: [absolutePath],
      // Note: Need to use ContextBuilder for external summaries
    );
  }
}
```

**Challenge:** The standard `AnalysisContextCollection` doesn't directly support `externalSummaries`. We need to use the lower-level `ContextBuilderImpl.createContext()` API or `createAnalysisDriver()` from `build_resolvers.dart`.

#### 3.2 Modify CLI Runner

**File:** `lib/src/cli/runner.dart`

Add pre-generation stage:

```dart
Future<void> _runGenerateMode(List<String> args) async {
  // ... existing code ...
  
  // New: Summary cache stage
  final cacheManager = SummaryCacheManager(projectRoot);
  final depResolver = DependencyResolver();
  
  final dependencies = await depResolver.resolveVersionedDependencies(projectRoot);
  final summaryGenerator = SummaryGenerator(cacheManager);
  
  await summaryGenerator.generateMissingSummaries(
    dependencies.where((d) => d.isCacheable).toList(),
    onProgress: (pkg, current, total) {
      print('Generating summary ($current/$total): $pkg');
    },
  );
  
  // Load summaries for analysis
  final summaryStore = await cacheManager.loadSummaries(dependencies);
  
  // Create resolver with summaries
  final resolver = await StandaloneLibraryResolver.create(
    projectRoot,
    externalSummaries: summaryStore,
  );
  
  // ... continue with generation ...
}
```

#### 3.3 Add CLI Options

```
--no-cache          Disable summary caching
--rebuild-cache     Force regenerate all summaries
--cache-only PKG    Only cache specific package(s)
--show-cache-status Show which packages have cached summaries
```

### Phase 4: Testing & Optimization (Estimated: 4-6 hours)

#### 4.1 Unit Tests

- `test/summary/summary_cache_manager_test.dart`
- `test/summary/dependency_resolver_test.dart`
- `test/summary/summary_generator_test.dart`

#### 4.2 Integration Tests

- Test with a Flutter project that has many dependencies
- Verify summaries are correctly loaded and used
- Verify incremental generation (only missing summaries)
- Benchmark: Compare time with/without summaries

#### 4.3 Edge Cases

- Handle corrupted summary files
- Handle SDK version mismatches gracefully
- Handle packages without proper lib/ structure
- Handle circular dependencies between summary generation

## Technical Considerations

### SDK Summary

The Dart SDK doesn't need separate summary generation - it should be included in the Flutter SDK summary or use the SDK's own summary mechanism:

```dart
// The analyzer already supports SDK summaries via:
var sdk = SummaryBasedDartSdk.forBundle(sdkBundle);
```

Flutter includes a pre-built SDK summary that we can use.

### Memory Considerations

Loading many large summaries may increase memory usage. Consider:
- Lazy loading of summaries (load on first access)
- Memory-mapped file access for large summaries
- Option to limit cached packages

### Parallel Summary Generation

For initial cache population, generate summaries in parallel:

```dart
await Future.wait(
  missingDependencies.map((dep) => summaryGenerator.generateSummary(dep)),
);
```

But limit concurrency to avoid overwhelming the system.

### Error Handling

If summary generation fails for a package:
1. Log a warning but don't fail the build
2. Fall back to full analysis for that package
3. Don't cache a broken summary

## Expected Performance Impact

Based on the current breakdown (816s build + 457s analyze):

| Scenario | Expected Time | Notes |
|----------|---------------|-------|
| First run (cold cache) | ~30 min | All summaries need generation |
| Second run (warm cache) | ~2-5 min | Only user code analyzed |
| After pub upgrade | +30s per changed package | Incremental summary generation |
| After Flutter upgrade | ~15 min | Flutter summary regeneration |

**Target:** Reduce repeat analysis time from 21 minutes to under 5 minutes.

## File Structure

```
tom_reflection_generator/
├── lib/
│   └── src/
│       └── summary/
│           ├── summary_cache_manager.dart
│           ├── dependency_resolver.dart
│           ├── summary_generator.dart
│           └── package_dependency.dart
├── test/
│   └── summary/
│       ├── summary_cache_manager_test.dart
│       ├── dependency_resolver_test.dart
│       └── summary_generator_test.dart
└── doc/
    └── analyzer_summary_integration.md  (this file)
```

## Open Questions

1. **SDK Summary Location:** Should SDK summaries be stored globally (`~/.tom/analyzer-cache/`) or per-workspace?

2. **Summary Format Version:** How to handle analyzer version upgrades that change the summary format?

3. **Shared Cache:** Could multiple workspaces share a global cache for common packages?

4. **CI/CD Integration:** Should summaries be committed to a shared repository for CI builds?

## References

- Analyzer source: `~/.pub-cache/hosted/pub.dev/analyzer-{version}/`
- `package_bundle_format.dart` - Binary format specification
- `bundle_writer.dart` - How to create summaries
- `build_resolvers.dart` - Reference implementation for summary loading
- `context_builder.dart` - How to configure external summaries
