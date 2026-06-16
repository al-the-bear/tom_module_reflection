// Scenario 2 — serialize the model to JSON and read it back.
//
// The whole point of engine 2 is that its model is *pure data*: it can be
// written to disk, shipped, cached, and re-read without re-running the
// analyzer. This scenario proves the round-trip preserves the model's
// structure — analyze once, encode, decode, and confirm the rebuilt model
// matches the original.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reflector_parser_introduction_sample/catalog_analysis.dart';
import 'package:tom_reflector/tom_reflector.dart';

Future<void> main() async {
  final original = await analyzeCatalog();

  // Encode to a JSON string. `JsonSerializer.encode` walks the object graph and
  // turns cross-references (a field's declaring type, a type's resolved element)
  // into stable IDs, so cycles round-trip safely.
  final json = JsonSerializer.encode(original);
  print('encoded JSON -> ${json.length} chars'); // (varies; ~40k)

  // Persist it, then read it back from disk — the realistic "cache the analysis"
  // use case. `build/` is gitignored.
  final outFile = File(p.join('build', 'catalog.analysis.json'));
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(json);
  final restored = JsonDeserializer.decode(outFile.readAsStringSync());

  // Structure survives the trip: same class / enum / function counts.
  print('classes   ${original.allClasses.length} -> ${restored.allClasses.length}');
  // classes   3 -> 3
  print('enums     ${original.allEnums.length} -> ${restored.allEnums.length}');
  // enums     1 -> 1
  print('functions ${original.allFunctions.length} -> ${restored.allFunctions.length}');
  // functions 1 -> 1

  // Detail survives too: spot-check Product's members and its annotation.
  final before = original.getClassOrThrow('Product');
  final after = restored.getClassOrThrow('Product');
  print('Product fields  ${before.fields.length} -> ${after.fields.length}'); // 5 -> 5
  print('Product methods ${before.methods.length} -> ${after.methods.length}'); // 1 -> 1
  print('Product @Entity preserved -> '
      '${after.annotations.any((a) => a.name == 'Entity')}'); // -> true

  final ok = original.allClasses.length == restored.allClasses.length &&
      before.fields.length == after.fields.length &&
      after.annotations.any((a) => a.name == 'Entity');
  if (!ok) {
    throw StateError('Round-trip lost structure.');
  }
  print('round-trip   -> identical structure');
}
