/// End-to-end guard on import-prefixing of **type literals inside default
/// values**.
///
/// A default value survives generation as *source text*: the generator re-emits
/// the expression into a library that imports every originating library under a
/// synthetic `prefixNN` alias and under no other name. Every named entity in
/// that expression therefore has to be re-qualified. Anything the emitter does
/// not recognise falls through to `expression.toSource()` and is written out
/// verbatim — which, for a bare class name, is an undefined name that makes the
/// generated library fail to compile.
///
/// That is not hypothetical: `tom_reflection_test`'s committed
/// `default_values_test.reflection.dart` contains `const <int, Type>{1: A}`,
/// and the whole file fails to load. The emitter has since learned to handle
/// `TypeLiteral`, but nothing pinned the behaviour, so this suite does — across
/// every position a type literal can occupy, because the fall-through is a
/// property of the *node kind*, and a future refactor that reroutes one
/// container's elements would silently reopen the hole for that container only.
///
/// Unlike the rest of this package's suite — which deliberately exercises
/// helpers without the analyzer — this test drives the real pipeline over a
/// real file, because the defect lives in the seam between the expression
/// walker and the import collector and nothing cheaper can observe it.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_reflection_generator/tom_reflection_generator.dart';

/// Whitespace-insensitive view of the generated source.
///
/// `dart_style` decides line breaks by width, so the emitted text for one
/// expression may or may not be split across lines depending on how deeply it
/// nests. Matching against a single-spaced rendering keeps the assertions about
/// *prefixes* rather than about formatting.
String _flatten(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  final packageRoot = Directory.current.path;
  final fixture =
      p.join(packageRoot, 'test', 'fixtures', 'default_value_prefix_fixture.dart');
  final generated = p.join(
      packageRoot, 'test', 'fixtures', 'default_value_prefix_fixture.reflection.dart');

  late String flat;

  setUpAll(() async {
    final result = await generateReflection(
      projectRoot: packageRoot,
      targets: [fixture],
      // The summary cache is a whole-project stage with on-disk state; this
      // test resolves one small file and must not depend on, or perturb, it.
      options: const ReflectionGenerationOptions(noCache: true),
    );

    expect(result.failedCount, 0,
        reason: 'the fixture failed to resolve or generate — a setup problem, '
            'not the prefixing behaviour under test');
    expect(result.processedCount, 1,
        reason: 'the fixture was skipped rather than generated. It needs a '
            'main(), a reflector annotation, and newInstanceCapability for '
            'default values to be emitted at all');

    flat = _flatten(File(generated).readAsStringSync());
  });

  tearDownAll(() {
    final file = File(generated);
    if (file.existsSync()) file.deleteSync();
  });

  group('a type literal in a default value carries the generated prefix', () {
    test('the emitted constructor actually contains the default values', () {
      // Guards every following expectation: if the generator stopped emitting
      // defaults, the `Local` matches would simply be absent and the negative
      // assertions below would pass vacuously.
      expect(flat, contains('withTypeLiterals'));
      expect(RegExp(r'prefix\d+\.Local').allMatches(flat), hasLength(6),
          reason: 'six of the seven defaults name Local; the seventh names '
              'Imported');
    });

    test('as a bare positional default', () {
      expect(flat, matches(RegExp(r'bare = prefix\d+\.Local')));
    });

    test('as a map value', () {
      // The originally reported defect.
      expect(flat, matches(RegExp(r'<int, Type>\{ ?1: prefix\d+\.Local ?\}')));
    });

    test('as a map key', () {
      expect(flat, matches(RegExp(r'<Type, int>\{ ?prefix\d+\.Local: 1 ?\}')));
    });

    test('as a list element', () {
      expect(flat, matches(RegExp(r'<Type>\[ ?prefix\d+\.Local,? ?\]')));
    });

    test('as a set element', () {
      expect(flat, matches(RegExp(r'<Type>\{ ?prefix\d+\.Local,? ?\}')));
    });

    test('nested inside a collection inside a collection', () {
      expect(
          flat,
          matches(RegExp(
              r'<int, List<Type>>\{ ?1: (?:const )?<Type>\[ ?prefix\d+\.Local,? ?\]')));
    });

    test('and the generated library actually compiles', () async {
      // The assertions above name the positions we know about; this one holds
      // for the positions we do not. An unqualified name is only a *bug*
      // because it does not resolve, so resolving the emitted file is the
      // assertion that matches the contract — and it is what would have caught
      // the original `const <int, Type>{1: A}` defect without anyone first
      // guessing which node kind fell through.
      final analysis = await Process.run(
        Platform.resolvedExecutable,
        ['analyze', '--no-fatal-warnings', generated],
        workingDirectory: packageRoot,
      );

      expect(analysis.exitCode, 0,
          reason: 'the generated library does not resolve:\n'
              '${analysis.stdout}${analysis.stderr}');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('written in the source with an import prefix of its own', () {
      // `lib.Imported` in the source: the source prefix is meaningless in the
      // generated library and must be *replaced*, not kept and not doubled up
      // (`prefix2.lib.Imported` compiles no better than `lib.Imported`).
      expect(flat, matches(RegExp(r'imported = prefix\d+\.Imported')));
      expect(flat, isNot(contains('lib.Imported')),
          reason: "the source library's own import prefix leaked into the "
              'generated file, where the name `lib` is not in scope');
    });
  });
}
