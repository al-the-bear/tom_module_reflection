import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_reflection_generator/reflection_generator_v2.dart';

/// G-REFL-3: the reflection generator runs flag-free — a bare
/// `dart run tom_reflection_generator` (no `--nested`) processes only the
/// current project.
///
/// The single-project scope is the framework's project-traversal default
/// (scan `.`, non-recursive), which applies because `reflectionGeneratorTool`
/// is a single-command project-traversal tool that does not require git
/// traversal. These tests lock that tool configuration and the resulting
/// flag-free scope here, so a future change to the tool definition (or to the
/// parser defaults it relies on) that would reintroduce a `--nested`
/// requirement is caught in this package.
void main() {
  group('G-REFL-3: flag-free single-project generation', () {
    test('the tool is a single-command project-traversal tool (no git)', () {
      expect(reflectionGeneratorTool.mode, ToolMode.singleCommand);
      expect(reflectionGeneratorTool.features.projectTraversal, isTrue);
      expect(reflectionGeneratorTool.features.gitTraversal, isFalse);
    });

    test('flag-free args scope traversal to the current project (scan .)', () {
      final args = CliArgParser().parse(const <String>[]);

      // No --nested is needed: a flag-free run is an ordinary project
      // traversal.
      expect(args.nested, isFalse);

      final info = args.toProjectTraversalInfo(executionRoot: '/workspace');
      // scan '.', non-recursive ⇒ only the cwd project is processed.
      expect(info.scan, equals('.'));
      expect(info.recursive, isFalse);
    });
  });
}
