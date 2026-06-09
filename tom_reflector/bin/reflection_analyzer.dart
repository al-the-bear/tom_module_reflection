/// Tom Reflection Analyzer CLI — emits a JSON/YAML dump of a package's public
/// API surface (the tom_reflector_model AnalysisResult, including doc comments)
/// using the Dart analyzer.
///
/// Named `reflection_analyzer` to disambiguate from the other analyzers in the
/// workspace. This is the producer the website's `gen_api --reflect` invokes
/// (per package) to generate the `doc/analyzer_analysis.json` reference dumps.
///
/// Run `reflection_analyzer --help` for usage information.
library;

import 'dart:io';

import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_reflector/src/v2/analyzer_executor.dart';
import 'package:tom_reflector/src/v2/reflection_analyzer_tool.dart';

void main(List<String> args) async {
  final runner = ToolRunner(
    tool: reflectionAnalyzerTool,
    executors: createReflectionAnalyzerExecutors(),
  );

  final result = await runner.run(args);

  if (!result.success) {
    exitCode = 1;
  }
}
