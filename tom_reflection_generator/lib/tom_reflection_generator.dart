/// Public exports for the Tom Reflection Generator package.
///
/// Consumers can import this library to access the build_runner builder,
/// standalone CLI infrastructure, the shared generation pipeline, and
/// analyzer-resolver utilities.
///
/// For the tom_build_base v2 tool/executor (buildkit nesting), import
/// `package:tom_reflection_generator/reflection_generator_v2.dart` instead.
library;

export 'reflection_generator.dart';
export 'cli.dart';
export 'summary.dart';
export 'src/generation/reflection_generation.dart';
export 'src/reflection_generator/standalone_resolver.dart';
export 'src/reflection_generator/library_resolver.dart' show FileId;
