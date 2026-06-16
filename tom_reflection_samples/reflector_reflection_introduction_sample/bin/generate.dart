// Regenerate `lib/catalog.r.dart` from `lib/catalog.dart`.
//
// This is the "use case: generating code" step of engine 2. It drives the
// reflection generator directly through its public API:
//
//   1. `TomAnalyzer().analyzeBarrel(...)` walks the package's element model.
//   2. `ReflectionModel.fromAnalysis(...)` distils it into the reflection model
//      (classes, members, constructors, globals + their invoker closures).
//   3. `ReflectionGenerator().generate(model)` emits the `.r.dart` source.
//
// The generated file is committed so the scenarios compile out of the box; run
// this script whenever `catalog.dart` changes to refresh it.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_reflector/tom_reflector.dart';

Future<void> main() async {
  // Resolve paths from the script location so this runs from any cwd.
  final projectRoot = p.dirname(p.dirname(Platform.script.toFilePath()));
  final barrel = p.join(projectRoot, 'lib', 'catalog.dart');
  final output = p.join(projectRoot, 'lib', 'catalog.r.dart');

  final analysis = await TomAnalyzer().analyzeBarrel(
    barrelPath: barrel,
    workspaceRoot: projectRoot,
  );
  final model = ReflectionModel.fromAnalysis(analysis);
  final content = ReflectionGenerator().generate(model);

  File(output).writeAsStringSync(content);
  stdout.writeln('Generated ${p.relative(output, from: projectRoot)} '
      '(${content.length} chars)');
}
