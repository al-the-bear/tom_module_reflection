/// Summary caching infrastructure for the Tom Reflection Generator.
///
/// This library provides utilities for caching analyzer summaries
/// to speed up repeated reflection generation runs.
///
/// ## Usage
///
/// ```dart
/// import 'package:tom_reflection_generator/summary.dart';
///
/// // Create a cache manager for your workspace
/// final cacheManager = SummaryCacheManager('/path/to/workspace');
///
/// // Resolve dependencies from pubspec.lock
/// final resolver = DependencyResolver();
/// final deps = await resolver.resolveVersionedDependencies('/path/to/project');
///
/// // Check which summaries are missing
/// final missing = await cacheManager.findMissingSummaries(deps);
///
/// // Load available summaries
/// final store = await cacheManager.loadSummaries(deps);
/// ```
library;

export 'src/summary/dependency_resolver.dart';
export 'src/summary/package_dependency.dart';
export 'src/summary/summary_cache_manager.dart';
export 'src/summary/summary_generator.dart';
