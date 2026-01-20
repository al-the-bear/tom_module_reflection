/// Public exports for the Tom Reflection Generator package.
///
/// Consumers can import this library to access the build_runner builder,
/// standalone CLI infrastructure, and analyzer-resolver utilities.
library;

export 'reflection_generator.dart';
export 'cli.dart';
export 'src/reflection_generator/standalone_resolver.dart';
export 'src/reflection_generator/library_resolver.dart' show FileId;
