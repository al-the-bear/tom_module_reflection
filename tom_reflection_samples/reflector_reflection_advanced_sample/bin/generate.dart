// Regenerate `lib/store.r.dart` from `lib/store.dart`.
//
// Identical pipeline to the introduction sample — the advanced sample is about
// the RICHER DOMAIN (a class hierarchy with mixins, an interface, and static
// members), not a different generation path. It drives engine 2's reflection
// generator directly through its public API:
//
//   1. `TomAnalyzer().analyzeBarrel(...)` walks the package's element model.
//   2. `ReflectionModel.fromAnalysis(...)` distils it into the reflection model
//      — flattening inherited and mixed-in members onto each class.
//   3. `ReflectionGenerator().generate(model)` emits the `.r.dart` source.
//
// This is the LEGACY BARREL path (analyze a barrel, generate for everything it
// exports). The entry-point reachability path — include/exclude filters,
// transitive dependency resolution, coverage configuration — is the engine's
// designed configuration surface and is documented in the README; this sample's
// runnable generation uses the barrel path because that is the path that
// currently emits compiling, runnable output.
//
// The generated file is committed so the scenarios compile out of the box; run
// this script whenever `store.dart` changes to refresh it.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_reflector/tom_reflector.dart';

Future<void> main() async {
  // Resolve paths from the script location so this runs from any cwd.
  final projectRoot = p.dirname(p.dirname(Platform.script.toFilePath()));
  final barrel = p.join(projectRoot, 'lib', 'store.dart');
  final output = p.join(projectRoot, 'lib', 'store.r.dart');

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
