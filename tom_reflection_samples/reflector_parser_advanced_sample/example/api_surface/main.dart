// Scenario 3 — the tool: a deterministic API-surface index.
//
// This is the canonical engine-2 deliverable, the advanced cut: walk the model
// into a STABLE projection that captures the full type relationships — extends /
// with / implements, generic bounds, mixin `on` clauses, extension targets —
// and emit byte-identical JSON on every run. We build it from RE-READ data
// (round-trip through YAML first) to prove it works against a cached model,
// exactly as a downstream tool would.
import 'dart:convert';

import 'package:reflector_parser_advanced_sample/shop_analysis.dart';
import 'package:tom_reflector/tom_reflector.dart';

Future<void> main() async {
  final analysed = await analyzeShop();

  // Round-trip through YAML, then build the surface from the restored model.
  final model = YamlDeserializer.decode(YamlSerializer.encode(analysed));
  final surface = buildApiSurface(model);

  print(const JsonEncoder.withIndent('  ').convert(surface));
}
