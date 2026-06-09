/// Tom Reflection Analyzer v2 — Tool definition using tom_build_base v2.
///
/// `reflection_analyzer` emits a JSON/YAML dump of a package's public API
/// surface (the `tom_reflector_model` `AnalysisResult`, including doc comments)
/// using the Dart analyzer. It is the producer behind the website's
/// `doc/analyzer_analysis.json` reference dumps.
///
/// It shares the analysis engine with `tom_analyzer` but, unlike that tool,
/// does not require a per-package `tom_analyzer:` buildkit block: it defaults
/// the barrel to the package's conventional `lib/<name>.dart` when none is
/// configured. The name disambiguates it from the many other "analyzer" tools
/// in the workspace.
library;

import 'package:tom_build_base/tom_build_base_v2.dart';

import '../version.versioner.dart';
import 'analyzer_tool.dart' show analyzerOptions;

// =============================================================================
// Tool Definition
// =============================================================================

/// Tom Reflection Analyzer tool definition.
final reflectionAnalyzerTool = ToolDefinition(
  name: 'reflection_analyzer',
  description: 'Dumps a Dart package public API surface (incl. doc comments)',
  version: AnalyzerVersionInfo.version,
  versionString: 'Tom Reflection Analyzer ${AnalyzerVersionInfo.versionLong}',
  mode: ToolMode.singleCommand,
  worksWithNatures: {DartProjectFolder},
  features: const NavigationFeatures(
    projectTraversal: true,
    gitTraversal: false,
    recursiveScan: false,
    interactiveMode: false,
    dryRun: false,
    jsonOutput: false,
    verbose: true,
  ),
  globalOptions: analyzerOptions,
  helpFooter: '''
Barrel resolution (first match wins):
  1. --barrel <path>
  2. tom_analyzer.barrels[0] in buildkit.yaml (if present)
  3. lib/<package-name>.dart (the conventional public barrel)

Typical use (from a package directory):
  reflection_analyzer --output doc/analyzer_analysis.json --format json

Related:
  For reflection mirror-code generation, use tom_reflector:
    dart run tom_reflector:reflector --help
''',
);
