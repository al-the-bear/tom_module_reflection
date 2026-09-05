/// Tests for check mode — the guard against a committed `*.reflection.dart`
/// that no longer matches its source.
///
/// **Why this exists.** Widening a reflected parameter from `String?` to
/// `Object?` in two sample packages changed a type index in each generated
/// seed. Neither was regenerated, and both were committed stale. Nothing
/// noticed: `dart analyze` was clean and both suites were fully green, with
/// identical test counts before and after regeneration. The stale portion is
/// metadata the tests never exercise, so every signal we routinely look at was
/// blind to it. "Remember to regenerate" was the only thing standing between a
/// reflected signature change and a committed mismatch, and a habit is not a
/// control.
///
/// Check mode is that control: it runs the generator and compares what it
/// *would* emit against what is committed, rather than overwriting it.
///
/// These tests exercise [applyGeneratedOutput], the decision at the end of the
/// pipeline where writing and checking diverge, plus the counters the CLI and
/// the buildkit executor derive their exit status from. They deliberately avoid
/// the analyzer, matching `reflection_generation_test.dart` — the comparison is
/// what is under test here, not the generation that produces the string.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_reflection_generator/src/generation/reflection_generation.dart';

void main() {
  group('applyGeneratedOutput in write mode', () {
    late Directory tempDir;

    setUp(() => tempDir = _makeTempDir('write'));
    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('writes the file and reports it generated', () {
      final output = p.join(tempDir.path, 'model.reflection.dart');

      final outcome = applyGeneratedOutput(
        outputPath: output,
        generatedSource: '// generated v1\n',
        checkOnly: false,
      );

      expect(outcome, ReflectionFileOutcome.generated);
      expect(File(output).readAsStringSync(), '// generated v1\n');
    });

    test('overwrites an existing stale file', () {
      final output = p.join(tempDir.path, 'model.reflection.dart');
      File(output).writeAsStringSync('// generated v0\n');

      final outcome = applyGeneratedOutput(
        outputPath: output,
        generatedSource: '// generated v1\n',
        checkOnly: false,
      );

      expect(outcome, ReflectionFileOutcome.generated);
      expect(File(output).readAsStringSync(), '// generated v1\n');
    });
  });

  group('applyGeneratedOutput in check mode', () {
    late Directory tempDir;

    setUp(() => tempDir = _makeTempDir('check'));
    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('reports a matching file up to date', () {
      final output = p.join(tempDir.path, 'model.reflection.dart');
      File(output).writeAsStringSync('// generated v1\n');

      final outcome = applyGeneratedOutput(
        outputPath: output,
        generatedSource: '// generated v1\n',
        checkOnly: true,
      );

      expect(outcome, ReflectionFileOutcome.upToDate);
    });

    test('reports a differing file stale', () {
      final output = p.join(tempDir.path, 'model.reflection.dart');
      File(output).writeAsStringSync('// generated v0\n');

      final outcome = applyGeneratedOutput(
        outputPath: output,
        generatedSource: '// generated v1\n',
        checkOnly: true,
      );

      expect(outcome, ReflectionFileOutcome.stale);
    });

    // The property that makes this a *check*. A mode that repaired what it
    // found would make the drift invisible again — the working tree would come
    // back clean and the reason for the failure would be gone by the time
    // anyone read the report.
    test('leaves the stale file untouched', () {
      final output = p.join(tempDir.path, 'model.reflection.dart');
      File(output).writeAsStringSync('// generated v0\n');

      applyGeneratedOutput(
        outputPath: output,
        generatedSource: '// generated v1\n',
        checkOnly: true,
      );

      expect(
        File(output).readAsStringSync(),
        '// generated v0\n',
        reason: 'check mode must report drift, never silently repair it',
      );
    });

    // A source that should generate a seed but has none is drift too, and the
    // remedy is identical: run the generator. Treating it as up-to-date would
    // let a never-generated file pass forever.
    test('reports a missing file stale without creating it', () {
      final output = p.join(tempDir.path, 'model.reflection.dart');

      final outcome = applyGeneratedOutput(
        outputPath: output,
        generatedSource: '// generated v1\n',
        checkOnly: true,
      );

      expect(outcome, ReflectionFileOutcome.stale);
      expect(
        File(output).existsSync(),
        isFalse,
        reason: 'check mode must not write the file it is checking',
      );
    });

    test('a difference anywhere in the file counts, not just the first line', () {
      final output = p.join(tempDir.path, 'model.reflection.dart');
      File(output).writeAsStringSync('// header\nconst i = 55;\n// tail\n');

      final outcome = applyGeneratedOutput(
        outputPath: output,
        generatedSource: '// header\nconst i = 51;\n// tail\n',
        checkOnly: true,
      );

      expect(
        outcome,
        ReflectionFileOutcome.stale,
        reason: 'the real defect was a single changed type index mid-file',
      );
    });
  });

  group('ReflectionGenerationResult', () {
    test('stale outputs make the run a failure', () {
      const result = ReflectionGenerationResult(
        processedCount: 0,
        skippedCount: 3,
        upToDateCount: 4,
        staleCount: 1,
        staleFiles: ['lib/src/model.reflection.dart'],
      );

      expect(result.hasStaleOutputs, isTrue);
      expect(result.staleFiles, hasLength(1));
    });

    test('a clean check run has no stale outputs', () {
      const result = ReflectionGenerationResult(
        processedCount: 0,
        skippedCount: 3,
        upToDateCount: 5,
      );

      expect(result.hasStaleOutputs, isFalse);
      expect(result.hasFailures, isFalse);
    });

    // Staleness and crashes are independent axes: a run can hit both, and the
    // report must not let one mask the other.
    test('a crash and a stale output are reported separately', () {
      const result = ReflectionGenerationResult(
        processedCount: 0,
        skippedCount: 0,
        upToDateCount: 1,
        staleCount: 1,
        staleFiles: ['a.reflection.dart'],
        failedCount: 1,
      );

      expect(result.hasStaleOutputs, isTrue);
      expect(result.hasFailures, isTrue);
    });
  });
}

/// Creates a unique temp directory under the workspace `ztmp` folder (never
/// `/tmp`, per workspace rules).
Directory _makeTempDir(String label) {
  final ztmp = Directory(
    p.join(
      _workspaceRoot(),
      'ztmp',
      'reflcheck_test_${label}_${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  ztmp.createSync(recursive: true);
  return ztmp;
}

/// Resolves the workspace root (tom_agent_container) from the package root:
/// tom_reflection_generator -> reflection -> tom_ai -> root.
String _workspaceRoot() {
  final pkgRoot = Directory.current.path;
  return p.normalize(p.join(pkgRoot, '..', '..', '..'));
}
