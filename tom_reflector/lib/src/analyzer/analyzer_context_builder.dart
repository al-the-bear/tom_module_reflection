import 'dart:io' as io;

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:path/path.dart' as p;

/// Builds analyzer contexts with normalized paths.
class AnalyzerContextBuilder {
  AnalysisContextCollection build({
    required String rootPath,
    List<String>? includedPaths,
    List<String>? excludedPaths,
    ResourceProvider? resourceProvider,
  }) {
    final normalizedRoot = _normalizePath(rootPath);
    final includes = (includedPaths == null || includedPaths.isEmpty)
        ? [normalizedRoot]
        : includedPaths.map(_normalizePath).toList();
    final excludes = (excludedPaths ?? const [])
        .map(_normalizePath)
        .toList(growable: false);

    return AnalysisContextCollection(
      includedPaths: includes,
      excludedPaths: excludes,
      // Without an explicit SDK path the analyzer derives one from
      // `Platform.resolvedExecutable`. That is correct under `dart run` (it
      // points at the `dart` binary), but wrong for an AOT-compiled executable
      // (`dart compile exe`), where it points at the tool itself and the SDK
      // cannot be found. Resolve the real SDK so the compiled binary works.
      sdkPath: _resolveSdkPath(),
      resourceProvider: resourceProvider ?? PhysicalResourceProvider.INSTANCE,
    );
  }

  String _normalizePath(String path) => p.normalize(p.absolute(path));

  /// Locates the Dart SDK directory at runtime, or `null` to let the analyzer
  /// fall back to its default (executable-relative) detection.
  ///
  /// This mirrors `resolveDartSdkPath` in `tom_analyzer_shared`
  /// (`lib/src/sdk/dart_sdk_locator.dart`), kept as an independent copy so
  /// `tom_reflector` does not pull in the analyzer-summary dependency tree for
  /// a single utility. Keep the two in sync if either gains a new heuristic.
  ///
  /// Resolution order (first match wins):
  /// 1. `DART_SDK` environment variable.
  /// 2. `DART_HOME` environment variable.
  /// 3. [io.Platform.resolvedExecutable] — correct under `dart run` (it points
  ///    at the `dart` binary, so the SDK is its grandparent), harmlessly
  ///    skipped for AOT-compiled binaries (it points at the tool itself).
  /// 4. The `dart` executable on `PATH` (`which`/`where`), symlinks resolved —
  ///    standalone `<sdk>/bin/dart` or the Flutter wrapper `<flutter>/bin/dart`
  ///    whose real SDK is `<flutter>/bin/cache/dart-sdk`.
  /// 5. The `flutter` executable on `PATH` → `<flutter>/bin/cache/dart-sdk`.
  ///
  /// Every candidate is validated with [_looksLikeSdk], so a stale environment
  /// variable or an unrelated `dart` on `PATH` never yields a bogus path.
  static String? _resolveSdkPath() {
    // 1. DART_SDK environment variable.
    final dartSdkEnv = io.Platform.environment['DART_SDK'];
    if (_looksLikeSdk(dartSdkEnv)) return dartSdkEnv;

    // 2. DART_HOME environment variable.
    final dartHomeEnv = io.Platform.environment['DART_HOME'];
    if (_looksLikeSdk(dartHomeEnv)) return dartHomeEnv;

    // 3. Platform.resolvedExecutable — points at the `dart` binary under
    //    `dart run`; harmlessly skipped for compiled binaries.
    try {
      final fromExe = _sdkFromDartExecutable(io.Platform.resolvedExecutable);
      if (fromExe != null) return fromExe;
    } on Object {
      // resolvedExecutable can throw in some embedders — ignore.
    }

    // 4. `dart` on PATH.
    final dartOnPath = _firstOnPath('dart');
    if (dartOnPath != null) {
      final sdk = _sdkFromDartExecutable(dartOnPath);
      if (sdk != null) return sdk;
    }

    // 5. `flutter` on PATH → <flutter>/bin/cache/dart-sdk.
    final flutterOnPath = _firstOnPath('flutter');
    if (flutterOnPath != null) {
      var flutterPath = flutterOnPath;
      try {
        flutterPath = io.File(flutterPath).resolveSymbolicLinksSync();
      } on Object {
        // Keep the unresolved path.
      }
      // flutter lives at <flutter>/bin/flutter → root is the grandparent.
      final dartSdk = p.join(
          p.dirname(p.dirname(flutterPath)), 'bin', 'cache', 'dart-sdk');
      if (_looksLikeSdk(dartSdk)) return dartSdk;
    }

    return null;
  }

  /// Returns the first match for [command] on `PATH`, or `null`.
  static String? _firstOnPath(String command) {
    try {
      final locator = io.Platform.isWindows ? 'where' : 'which';
      final result = io.Process.runSync(locator, [command]);
      if (result.exitCode != 0) return null;
      final firstLine = (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');
      return firstLine.isEmpty ? null : firstLine;
    } on Object {
      return null;
    }
  }

  /// Derives the Dart SDK root from a path to a `dart` executable.
  ///
  /// Handles the standalone SDK (`<sdk>/bin/dart`, SDK is the grandparent) and
  /// the Flutter wrapper (`<flutter>/bin/dart`, real SDK at
  /// `<flutter>/bin/cache/dart-sdk`). Symlinks are resolved first. Returns
  /// `null` when no SDK-shaped directory is found.
  static String? _sdkFromDartExecutable(String dartPath) {
    var resolved = dartPath;
    try {
      resolved = io.File(dartPath).resolveSymbolicLinksSync();
    } on Object {
      // Keep the unresolved path.
    }

    final binDir = p.dirname(resolved);

    // Standalone SDK: <sdk>/bin/dart.
    final standaloneSdk = p.dirname(binDir);
    if (_looksLikeSdk(standaloneSdk)) return standaloneSdk;

    // Flutter wrapper: <flutter>/bin/dart → <flutter>/bin/cache/dart-sdk.
    final flutterSdk = p.join(binDir, 'cache', 'dart-sdk');
    if (_looksLikeSdk(flutterSdk)) return flutterSdk;

    return null;
  }

  static bool _looksLikeSdk(String? dir) {
    if (dir == null || dir.isEmpty) return false;
    return io.File(p.join(dir, 'lib', '_internal', 'allowed_experiments.json'))
        .existsSync();
  }
}
