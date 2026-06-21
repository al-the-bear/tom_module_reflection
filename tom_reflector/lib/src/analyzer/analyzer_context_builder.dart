import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:path/path.dart' as p;
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart'
    show resolveDartSdkPath;

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
      // cannot be found. `resolveDartSdkPath` (from tom_analyzer_shared) probes
      // DART_SDK/DART_HOME, the resolved executable, and `dart`/`flutter` on
      // PATH so the compiled binary works; it returns null to let the analyzer
      // fall back to its default detection.
      sdkPath: resolveDartSdkPath(),
      resourceProvider: resourceProvider ?? PhysicalResourceProvider.INSTANCE,
    );
  }

  String _normalizePath(String path) => p.normalize(p.absolute(path));
}
