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
  /// Tries, in order: the `DART_SDK` environment variable, then the `dart`
  /// executable on `PATH`. From the resolved `dart` path two SDK layouts are
  /// considered: the standalone SDK (`<sdk>/bin/dart`, so the SDK is the
  /// grandparent), and the Flutter-bundled SDK (`<flutter>/bin/dart` is a
  /// wrapper whose real SDK lives at `<flutter>/bin/cache/dart-sdk`). Only a
  /// directory that actually looks like an SDK is returned.
  static String? _resolveSdkPath() {
    final fromEnv = io.Platform.environment['DART_SDK'];
    if (_looksLikeSdk(fromEnv)) return fromEnv;

    try {
      final locator = io.Platform.isWindows ? 'where' : 'which';
      final result = io.Process.runSync(locator, ['dart']);
      if (result.exitCode == 0) {
        final firstLine = (result.stdout as String)
            .split('\n')
            .map((l) => l.trim())
            .firstWhere((l) => l.isNotEmpty, orElse: () => '');
        if (firstLine.isNotEmpty) {
          // Resolve symlinks (e.g. Homebrew/fvm shims) before walking up.
          final resolved = io.File(firstLine).resolveSymbolicLinksSync();
          final binDir = p.dirname(resolved);

          // Standalone SDK: `<sdk>/bin/dart`.
          final standaloneSdk = p.dirname(binDir);
          if (_looksLikeSdk(standaloneSdk)) return standaloneSdk;

          // Flutter wrapper: `<flutter>/bin/dart` → `<flutter>/bin/cache/dart-sdk`.
          final flutterSdk = p.join(binDir, 'cache', 'dart-sdk');
          if (_looksLikeSdk(flutterSdk)) return flutterSdk;
        }
      }
    } on Object {
      // Best effort — fall through to the analyzer default.
    }
    return null;
  }

  static bool _looksLikeSdk(String? dir) {
    if (dir == null || dir.isEmpty) return false;
    return io.File(p.join(dir, 'lib', '_internal', 'allowed_experiments.json'))
        .existsSync();
  }
}
