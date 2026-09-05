/// End-to-end guard on **private const default values**.
///
/// A default value survives generation as source text, and a private name in
/// that text is unusable: the generated library is a different library, so
/// `_defaultBuilders` resolves to nothing there. The emitter therefore has to
/// replace the name with the initializer it stands for.
///
/// It reaches that initializer by two independent routes — the declaration's
/// source AST, and the `const` initializer the element itself carries — and for
/// a long while only the first was implemented. The AST route is unavailable
/// whenever the declaring library was loaded from an analyzer **summary bundle**
/// rather than from source, and whether a given dependency is summarised is a
/// property of the shared analyzer cache, not of the code. The generator
/// silently emitted a parameter with no default, logged a SEVERE that nothing
/// was listening to, and reported success — so the same sources produced
/// different mirrors on consecutive days
/// (`tom_flutter_form_test/lib/main.reflection.dart`, where Flutter's
/// `PageTransitionsTheme({builders = _defaultBuilders})` lost its default and
/// two imports with it).
///
/// This suite pins the source route, which is the one a self-contained fixture
/// can exercise. The summary route has no cheap unit-level fixture — it needs a
/// dependency package that the cache stage has actually summarised — and is
/// guarded end to end by `tom_flutter_form_test/reflection_generation.sh
/// --check`, which fails naming the file when the committed mirror drifts.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_reflection_generator/tom_reflection_generator.dart';

/// Whitespace-insensitive view of the generated source: `dart_style` decides
/// line breaks by width, and these assertions are about expressions.
String _flatten(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  final packageRoot = Directory.current.path;
  final fixture = p.join(
      packageRoot, 'test', 'fixtures', 'private_const_default_fixture.dart');
  final generated = p.join(packageRoot, 'test', 'fixtures',
      'private_const_default_fixture.reflection.dart');

  late String flat;
  late ReflectionGenerationResult result;

  setUpAll(() async {
    result = await generateReflection(
      projectRoot: packageRoot,
      targets: [fixture],
      // The summary cache is a whole-project stage with on-disk state; this
      // test resolves one small file and must not depend on, or perturb, it.
      options: const ReflectionGenerationOptions(noCache: true),
    );

    expect(result.failedCount, 0,
        reason: 'the fixture failed to resolve or generate — a setup problem, '
            'not the inlining behaviour under test');
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

  group('a private const default value is inlined', () {
    test('the emitted constructor is present at all', () {
      // Guards the rest: were the constructor missing, the negative assertions
      // below would pass vacuously.
      expect(flat, contains('withPrivateConsts'));
    });

    test('a scalar private const becomes its value', () {
      expect(flat, matches(RegExp(r'count = 7')));
    });

    test('a private const collection becomes its initializer', () {
      // The entry names a class from a second library, so it must also carry
      // the generated import prefix — inlining and re-qualification are the
      // same pass and a fix to one has broken the other before.
      expect(
          flat,
          matches(RegExp(
              r"<String, prefix\d+\.Imported>\{ ?'imported': (?:const )?prefix\d+\.Imported\(\),? ?\}")));
    });

    test('no private name survives into the generated library', () {
      // The general form of the two assertions above: whatever route the
      // emitter takes, a name starting with `_` from the source library does
      // not resolve here.
      expect(flat, isNot(contains('_defaultCount')));
      expect(flat, isNot(contains('_defaultParts')));
    });

    test('and the run reports no SEVERE diagnostics', () {
      // The defect announced itself this way and nobody heard it: the emitter
      // logged "Cannot handle private identifier" and carried on. A count on
      // the result is what turns that into an observable failure.
      expect(result.severeCount, 0,
          reason: 'the generator met something it could not render and left '
              'it out; the mirror is incomplete even though the file was '
              'written');
    });

    test('and the generated library actually compiles', () async {
      // The assertions above name what we expect to be inlined; this one holds
      // for what we did not think of. An un-inlined private name is only a bug
      // because it does not resolve, so resolving the emitted file is the
      // assertion that matches the contract.
      final analysis = await Process.run(
        Platform.resolvedExecutable,
        ['analyze', '--no-fatal-warnings', generated],
        workingDirectory: packageRoot,
      );

      expect(analysis.exitCode, 0,
          reason: 'the generated library does not resolve:\n'
              '${analysis.stdout}${analysis.stderr}');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
