import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_reflector/src/reflection/generator/reflection_generator.dart';
import 'package:tom_reflector/src/reflection/generator/reflection_config.dart';
import 'package:tom_reflector/src/reflection/generator/entry_point_analyzer.dart';

/// Extract the inline `flags` integer emitted for a class's `ClassMirrorData`
/// entry. The generator writes each class as:
///
/// ```
///   'Entity',  // name
///   1,  // flags
/// ```
///
/// so we anchor on the `'<name>',  // name` marker and read the following
/// `<int>,  // flags` line.
int _classFlagsFor(String code, String className) {
  final marker = "'$className',  // name";
  final idx = code.indexOf(marker);
  expect(idx, greaterThanOrEqualTo(0),
      reason: 'no ClassMirrorData entry for $className in generated code');
  final match =
      RegExp(r'(\d+),\s*//\s*flags').firstMatch(code.substring(idx));
  expect(match, isNotNull, reason: 'no flags line after $className');
  return int.parse(match!.group(1)!);
}

/// Integration tests for ReflectionGenerator code generation.
///
/// These tests verify that the generator produces valid and expected output
/// structure from AnalysisResult data.
void main() {
  group('ReflectionGenerator - Code Generation Integration', () {
    group('generateFromResult with empty result', () {
      late ReflectionGenerator generator;
      late ReflectionAnalysisResult emptyResult;

      setUp(() {
        generator = ReflectionGenerator.fromMap({
          'entry_points': [],
        });
        emptyResult = ReflectionAnalysisResult();
      });

      test('generates valid Dart code structure', () async {
        final code = await generator.generateFromResult(emptyResult);

        // Should have header comment
        expect(code, contains('GENERATED CODE - DO NOT MODIFY BY HAND'));
        expect(code, contains('tom_analyzer reflection generator'));

        // Should have ignore directive
        expect(code, contains('ignore_for_file'));
      });

      test('generates runtime import', () async {
        final code = await generator.generateFromResult(emptyResult);

        expect(code, contains("import 'package:tom_reflector/reflection_runtime.dart'"));
      });

      test('generates initialization function', () async {
        final code = await generator.generateFromResult(emptyResult);

        expect(code, contains('void initializeReflection()'));
        expect(code, contains('registerReflectionData'));
      });

      test('generates reflectionApi variable', () async {
        final code = await generator.generateFromResult(emptyResult);

        expect(code, contains('final reflectionApi'));
        expect(code, contains('ReflectionApi.fromData'));
      });

      test('generates reflection data structure', () async {
        final code = await generator.generateFromResult(emptyResult);

        expect(code, contains('_reflectionData'));
        expect(code, contains('ReflectionData'));
      });
    });

    group('inline flag encoding', () {
      // The generator no longer emits named `const _abstract`/`const _static`
      // bit-flag constants — flag encoding moved inline, so each type/member
      // now carries an integer literal annotated with `// flags`. An empty
      // result exercises no members, so this drives a populated fixture.
      final entryPoint = p.join(
        Directory.current.path,
        'test',
        'reflection',
        'fixtures',
        'sample_models.dart',
      );

      late String code;

      setUpAll(() async {
        final generator = ReflectionGenerator.fromMap({
          'entry_points': [entryPoint],
        });
        code = await generator.generate();
      });

      test('emits inline flag integers annotated with a flags comment',
          () async {
        expect(code, contains('// flags'),
            reason:
                'per-type/member flags must be emitted as inline integers');
      });

      test('sets the abstract bit for an abstract class', () async {
        // `Entity` is abstract → bit 0 (1 << 0) set.
        expect(_classFlagsFor(code, 'Entity') & (1 << 0), isNot(0),
            reason: 'abstract class must carry the abstract flag bit');
      });

      test('clears the abstract bit for a concrete class', () async {
        // `User` is concrete → bit 0 clear.
        expect(_classFlagsFor(code, 'User') & (1 << 0), 0,
            reason: 'concrete class must not carry the abstract flag bit');
      });
    });

    group('code structure validation', () {
      test('generated code has proper Dart syntax markers', () async {
        final generator = ReflectionGenerator.fromMap({
          'entry_points': [],
        });
        final code = await generator.generateFromResult(ReflectionAnalysisResult());

        // Check for basic Dart syntax elements
        expect(code, contains(';'));
        expect(code, contains('{'));
        expect(code, contains('}'));
        expect(code, contains('('));
        expect(code, contains(')'));
      });

      test('generated code has balanced braces', () async {
        final generator = ReflectionGenerator.fromMap({
          'entry_points': [],
        });
        final code = await generator.generateFromResult(ReflectionAnalysisResult());

        final openBraces = '{'.allMatches(code).length;
        final closeBraces = '}'.allMatches(code).length;
        expect(openBraces, equals(closeBraces),
            reason: 'Open and close braces should be balanced');
      });

      test('generated code has balanced parentheses', () async {
        final generator = ReflectionGenerator.fromMap({
          'entry_points': [],
        });
        final code = await generator.generateFromResult(ReflectionAnalysisResult());

        final openParens = '('.allMatches(code).length;
        final closeParens = ')'.allMatches(code).length;
        expect(openParens, equals(closeParens),
            reason: 'Open and close parentheses should be balanced');
      });

      test('generated code has balanced brackets', () async {
        final generator = ReflectionGenerator.fromMap({
          'entry_points': [],
        });
        final code = await generator.generateFromResult(ReflectionAnalysisResult());

        final openBrackets = '['.allMatches(code).length;
        final closeBrackets = ']'.allMatches(code).length;
        expect(openBrackets, equals(closeBrackets),
            reason: 'Open and close brackets should be balanced');
      });
    });

    group('invokers array generation', () {
      test('empty result generates empty invokers', () async {
        final generator = ReflectionGenerator.fromMap({
          'entry_points': [],
        });
        final code = await generator.generateFromResult(ReflectionAnalysisResult());

        // Should have invokers list, even if empty
        expect(code, contains('invokers'));
      });
    });

    group('package structure generation', () {
      test('empty result generates minimal package structure', () async {
        final generator = ReflectionGenerator.fromMap({
          'entry_points': [],
        });
        final code = await generator.generateFromResult(ReflectionAnalysisResult());

        // Should have package-related data
        expect(code, contains('packages'));
      });
    });

    group('generator state management', () {
      test('generator resets state between calls', () async {
        final generator = ReflectionGenerator.fromMap({
          'entry_points': [],
        });

        final code1 = await generator.generateFromResult(ReflectionAnalysisResult());
        final code2 = await generator.generateFromResult(ReflectionAnalysisResult());

        // Both generations should produce the same output
        expect(code1, equals(code2));
      });

      test('generator can be reused', () async {
        final generator = ReflectionGenerator.fromMap({
          'entry_points': [],
        });

        // First generation
        await generator.generateFromResult(ReflectionAnalysisResult());

        // Second generation should not throw
        expect(
          () async => await generator.generateFromResult(ReflectionAnalysisResult()),
          returnsNormally,
        );
      });
    });

    group('output configuration', () {
      test('getOutputPath returns configured output', () {
        final config = ReflectionConfig.fromMap({
          'entry_points': [],
          'output': 'lib/generated/my_reflection.r.dart',
        });
        final generator = ReflectionGenerator(config);

        expect(
          generator.config.getOutputPath(),
          contains('my_reflection.r.dart'),
        );
      });

      test('getOutputPath returns default when not configured', () {
        final config = ReflectionConfig.fromMap({
          'entry_points': [],
        });
        final generator = ReflectionGenerator(config);

        // Should return a default path
        expect(generator.config.getOutputPath(), isNotEmpty);
      });
    });

    group('import generation', () {
      test('runtime import uses correct alias', () async {
        final generator = ReflectionGenerator.fromMap({
          'entry_points': [],
        });
        final code = await generator.generateFromResult(ReflectionAnalysisResult());

        // Runtime should be imported as 'r'
        expect(code, contains("as r;"));
      });
    });

    group('declarations section', () {
      test('empty result has declarations structure', () async {
        final generator = ReflectionGenerator.fromMap({
          'entry_points': [],
        });
        final code = await generator.generateFromResult(ReflectionAnalysisResult());

        // Should have classes/types section (even if empty)
        expect(code, anyOf(contains('classes'), contains('types')));
      });
    });
  });
}
