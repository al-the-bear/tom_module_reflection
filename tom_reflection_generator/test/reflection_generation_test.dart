import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_reflection_generator/tom_reflection_generator.dart';
import 'package:yaml/yaml.dart';

/// Tests for the shared single-command generation helpers (extracted in the
/// tom_build_base migration). These cover the target-resolution building blocks
/// the `ReflectionGeneratorExecutor` relies on — glob classification, target
/// collection with generated-output exclusion, project-root discovery, and
/// `build.yaml` fallback parsing — without exercising the heavy analyzer
/// pipeline.
void main() {
  group('isGlobPattern', () {
    test('detects glob metacharacters', () {
      expect(isGlobPattern('lib/**/*.dart'), isTrue);
      expect(isGlobPattern('lib/foo?.dart'), isTrue);
      expect(isGlobPattern('lib/[ab].dart'), isTrue);
      expect(isGlobPattern('lib/{a,b}.dart'), isTrue);
    });

    test('treats a plain path as a non-glob', () {
      expect(isGlobPattern('lib/src/foo.dart'), isFalse);
      expect(isGlobPattern('main.dart'), isFalse);
    });
  });

  group('collectTargetFiles', () {
    late Directory tempDir;

    setUp(() {
      tempDir = _makeTempDir('collect');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('includes plain .dart files and excludes generated outputs', () {
      final srcDir = Directory(p.join(tempDir.path, 'lib', 'src'))
        ..createSync(recursive: true);
      final src = File(p.join(srcDir.path, 'model.dart'))
        ..writeAsStringSync('class A {}');
      File(p.join(srcDir.path, 'model.reflection.dart'))
          .writeAsStringSync('// generated');
      File(p.join(srcDir.path, 'model.g.dart')).writeAsStringSync('// gen');

      final files = collectTargetFiles(
        projectRoot: tempDir.path,
        targets: ['lib/**/*.dart'],
      );

      expect(files, contains(p.normalize(src.path)));
      expect(
        files.where((f) => f.endsWith('.reflection.dart')),
        isEmpty,
        reason: 'generated reflection outputs must be excluded',
      );
      expect(files.where((f) => f.endsWith('.g.dart')), isEmpty);
    });

    test('skips a directory target unless allMode is set', () {
      final libDir = Directory(p.join(tempDir.path, 'lib'))..createSync();
      final src = File(p.join(libDir.path, 'a.dart'))
        ..writeAsStringSync('class A {}');

      final withoutAll = collectTargetFiles(
        projectRoot: tempDir.path,
        targets: [libDir.path],
      );
      expect(withoutAll, isEmpty);

      final withAll = collectTargetFiles(
        projectRoot: tempDir.path,
        targets: [libDir.path],
        allMode: true,
      );
      expect(withAll, contains(p.normalize(src.path)));
    });
  });

  group('findProjectRoot', () {
    late Directory tempDir;

    setUp(() {
      tempDir = _makeTempDir('root');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('walks up to the nearest pubspec.yaml', () {
      File(p.join(tempDir.path, 'pubspec.yaml'))
          .writeAsStringSync('name: demo_pkg\n');
      final nested = Directory(p.join(tempDir.path, 'lib', 'src'))
        ..createSync(recursive: true);
      final file = File(p.join(nested.path, 'thing.dart'))
        ..writeAsStringSync('class T {}');

      expect(
        findProjectRoot(file.path),
        equals(p.normalize(tempDir.path)),
      );
    });

    test('returns null when no pubspec.yaml is found', () {
      final orphan = Directory(p.join(tempDir.path, 'no_pubspec'))
        ..createSync();
      expect(findProjectRoot(orphan.path), isNull);
    });
  });

  group('extractGenerateForPatterns (build.yaml fallback)', () {
    test('reads patterns from a reflection builder target', () {
      final yaml = loadYaml('''
targets:
  \$default:
    builders:
      tom_reflection_generator|reflection:
        generate_for:
          - lib/a.dart
          - lib/b.dart
''') as YamlMap;

      expect(
        extractGenerateForPatterns(yaml),
        equals(['lib/a.dart', 'lib/b.dart']),
      );
    });

    test('reads the top-level generate_for shorthand', () {
      final yaml = loadYaml('''
generate_for:
  - lib/**/*.dart
''') as YamlMap;

      expect(extractGenerateForPatterns(yaml), equals(['lib/**/*.dart']));
    });

    test('returns empty for an unrelated build.yaml', () {
      final yaml = loadYaml('''
targets:
  \$default:
    builders:
      some_other|builder:
        options:
          foo: bar
''') as YamlMap;

      // A single builder is treated as the reflection builder, but it has no
      // generate_for, so no patterns are produced.
      expect(extractGenerateForPatterns(yaml), isEmpty);
    });
  });

  group('extractBuilderOptions (build.yaml extension override)', () {
    test('collects builder options including extension', () {
      final yaml = loadYaml('''
targets:
  \$default:
    builders:
      tom_reflection_generator|reflection:
        options:
          extension: .refl.dart
''') as YamlMap;

      final options = extractBuilderOptions(yaml);
      expect(options['extension'], equals('.refl.dart'));
    });
  });

  // RCK27: a resolution crash (e.g. a corrupt analyzer summary throwing
  // RangeError) must be a distinct, loud failure — never collapsed into a
  // benign "skipped" that lets the run report success while regenerating
  // nothing. The seam is `LibraryResolver.resolveFile`: a thrown exception is a
  // hard failure, a plain `null` return is a benign skip.
  group('processReflectionFile outcome classification', () {
    test('resolveFile throwing yields ReflectionFileOutcome.failed', () async {
      final resolver = _ThrowingResolver(
        StateError('corrupt summary: RangeError (index) in StringTable'),
      );

      final outcome = await processReflectionFile(
        'lib/anything.dart',
        '/project/root',
        resolver,
        false, // verbose
        'tom_reflection',
        '.reflection.dart',
      );

      expect(
        outcome,
        ReflectionFileOutcome.failed,
        reason: 'a crash during resolution must be a hard failure, not a skip',
      );
    });

    test('resolveFile returning null yields ReflectionFileOutcome.skipped',
        () async {
      final resolver = _NullResolver();

      final outcome = await processReflectionFile(
        'lib/part_file.dart',
        '/project/root',
        resolver,
        false, // verbose
        'tom_reflection',
        '.reflection.dart',
      );

      expect(
        outcome,
        ReflectionFileOutcome.skipped,
        reason: 'a non-library (null) result is a benign skip, not a failure',
      );
    });
  });
}

/// A [LibraryResolver] whose [resolveFile] always throws, simulating a hard
/// resolution failure such as a corrupt analyzer summary in the cache. All
/// other members are unreachable for these tests and forwarded via
/// [noSuchMethod].
class _ThrowingResolver implements LibraryResolver {
  _ThrowingResolver(this.error);

  final Object error;

  @override
  Future<LibraryElement?> resolveFile(String filePath) async => throw error;

  @override
  Future<FileId?> fileIdForElement(LibraryElement library) =>
      throw UnimplementedError();

  @override
  Future<LibraryElement> libraryFor(FileId fileId) =>
      throw UnimplementedError();

  @override
  Future<AstNode?> astNodeFor(Fragment fragment, {bool resolve = false}) =>
      throw UnimplementedError();

  @override
  Future<bool> isImportable(LibraryElement library, FileId fromFile) =>
      throw UnimplementedError();

  @override
  Future<List<LibraryElement>> get libraries => throw UnimplementedError();
}

/// A [LibraryResolver] whose [resolveFile] returns null, simulating a file with
/// no resolvable library (a benign skip).
class _NullResolver implements LibraryResolver {
  @override
  Future<LibraryElement?> resolveFile(String filePath) async => null;

  @override
  Future<FileId?> fileIdForElement(LibraryElement library) =>
      throw UnimplementedError();

  @override
  Future<LibraryElement> libraryFor(FileId fileId) =>
      throw UnimplementedError();

  @override
  Future<AstNode?> astNodeFor(Fragment fragment, {bool resolve = false}) =>
      throw UnimplementedError();

  @override
  Future<bool> isImportable(LibraryElement library, FileId fromFile) =>
      throw UnimplementedError();

  @override
  Future<List<LibraryElement>> get libraries => throw UnimplementedError();
}

/// Creates a unique temp directory under the workspace `ztmp` folder (never
/// `/tmp`, per workspace rules).
Directory _makeTempDir(String label) {
  final ztmp = Directory(
    p.join(
      _workspaceRoot(),
      'ztmp',
      'reflgen_test_${label}_${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  ztmp.createSync(recursive: true);
  return ztmp;
}

/// Resolves the workspace root (tom_agent_container) from this test file's
/// location: test/ -> tom_reflection_generator -> reflection -> tom_ai -> root.
String _workspaceRoot() {
  // Directory.current is the package root when tests run via testkit/dart test.
  final pkgRoot = Directory.current.path;
  return p.normalize(p.join(pkgRoot, '..', '..', '..'));
}
