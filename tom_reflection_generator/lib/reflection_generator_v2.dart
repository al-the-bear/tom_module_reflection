/// Public exports for the tom_build_base v2 tool surface of the Tom Reflection
/// Generator.
///
/// Import this library to embed the runtime-mirror reflection generator as a
/// single-command, buildkit-nestable tool (`buildkit :reflectiongenerator`):
/// the [reflectionGeneratorTool] definition and its
/// [ReflectionGeneratorExecutor].
///
/// The `build_runner` builder entry remains in
/// `package:tom_reflection_generator/reflection_generator.dart` and is
/// unaffected by this surface.
library;

export 'src/v2/reflection_generator_executor.dart'
    show ReflectionGeneratorExecutor, createReflectionGeneratorExecutors;
export 'src/v2/reflection_generator_tool.dart'
    show reflectionGeneratorOptions, reflectionGeneratorTool;
