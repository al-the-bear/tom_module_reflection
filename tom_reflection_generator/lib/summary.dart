/// Summary caching infrastructure for the Tom Reflection Generator.
///
/// This library provides utilities for caching analyzer summaries
/// to speed up repeated reflection generation runs.
///
/// The implementation lives in [`package:tom_analyzer_shared`][shared]
/// and is reused by other code generators (e.g. `tom_d4rt_generator`).
/// This file is kept as a stable re-export so existing imports of
/// `package:tom_reflection_generator/summary.dart` continue to work.
///
/// [shared]: https://pub.dev/packages/tom_analyzer_shared
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

export 'package:tom_analyzer_shared/tom_analyzer_shared.dart';
