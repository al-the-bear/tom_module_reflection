/// Tom Reflection Generator CLI — runtime-mirror reflection code generation.
///
/// Built on the tom_build_base v2 tool framework so it works standalone and as
/// a nested buildkit tool (`buildkit :reflectiongenerator`).
///
/// Run `tom_reflection_generator --help` for usage information.
library;

import 'dart:io';

import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_reflection_generator/src/v2/reflection_generator_executor.dart';
import 'package:tom_reflection_generator/src/v2/reflection_generator_tool.dart';

void main(List<String> args) async {
  final runner = ToolRunner(
    tool: reflectionGeneratorTool,
    executors: <String, CommandExecutor>{
      'default': ReflectionGeneratorExecutor(),
    },
  );

  final result = await runner.run(args);

  if (!result.success) {
    exitCode = 1;
  }
}
