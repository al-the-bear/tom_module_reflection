// Scenario 3 — walk the model and emit a stable JSON report.
//
// `JsonSerializer.encode` gives you the *whole* model, including volatile data
// (timestamps, absolute paths, content hashes). For a reviewable artifact you
// usually want a projection: just the shape, sorted, with the noise stripped.
// This scenario builds that report from the (round-tripped) model and prints it
// as deterministic JSON — the canonical "use case: JSON" for engine 2.
import 'dart:convert';

import 'package:reflector_parser_introduction_sample/catalog_analysis.dart';
import 'package:tom_reflector/tom_reflector.dart';

Future<void> main() async {
  // Analyze, then round-trip through JSON to show the report is built from
  // re-read data — exactly as a downstream tool consuming a cached model would.
  final analysed = await analyzeCatalog();
  final model = JsonDeserializer.decode(JsonSerializer.encode(analysed));

  // `buildCatalogReport` projects the model down to names/kinds/members and
  // sorts every collection, so the output bytes are identical on every run.
  final report = buildCatalogReport(model);
  print(const JsonEncoder.withIndent('  ').convert(report));
}

// Expected output (stable):
//
// {
//   "package": "catalog_domain",
//   "annotationNames": [
//     "Entity"
//   ],
//   "classes": [
//     {
//       "name": "Entity",
//       "isAbstract": false,
//       "fields": [
//         {
//           "name": "table",
//           "type": "String",
//           "isFinal": true
//         }
//       ],
//       "methods": []
//     },
//     {
//       "name": "Product",
//       "isAbstract": false,
//       "annotations": [
//         "Entity"
//       ],
//       "fields": [
//         { "name": "label", "type": "String", "isFinal": false },
//         { "name": "name", "type": "String", "isFinal": false },
//         { "name": "price", "type": "double", "isFinal": false },
//         { "name": "sku", "type": "String", "isFinal": true },
//         { "name": "tags", "type": "List<String>", "isFinal": true }
//       ],
//       "methods": [
//         { "name": "discounted", "returnType": "double", "parameters": ["pct"] }
//       ]
//     },
//     {
//       "name": "Repository",
//       "isAbstract": true,
//       "typeParameters": ["T"],
//       "fields": [],
//       "methods": [
//         { "name": "findAll", "returnType": "List<T>", "parameters": [] },
//         { "name": "findById", "returnType": "T?", "parameters": ["id"] }
//       ]
//     }
//   ],
//   "enums": [
//     { "name": "Availability",
//       "values": ["inStock", "backordered", "discontinued"] }
//   ],
//   "functions": [
//     { "name": "catalogVersion", "returnType": "int" }
//   ]
// }
