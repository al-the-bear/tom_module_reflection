// Scenario 2 — serialize the cyclic graph to YAML and read it back.
//
// The model is a GRAPH, not a tree: Node.next points at Node, Order.lines at
// OrderLine, every field at its declaring type. Naively serializing that would
// loop forever. The serializers avoid it by giving every element a stable `id`
// and writing cross-references AS ids — so encoding terminates and the
// structure round-trips. This scenario proves it with YAML (JSON behaves the
// same; see the introduction sample for the JSON variant).
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reflector_parser_advanced_sample/shop_analysis.dart';
import 'package:tom_reflector/tom_reflector.dart';

Future<void> main() async {
  final original = await analyzeShop();

  // Encode the cyclic model to YAML — this terminates precisely because cross-
  // references are written as ids, not inlined.
  final yaml = YamlSerializer.encode(original);
  print('encoded YAML -> ${yaml.length} chars');
  // encoded YAML -> ~65000 chars (exact count varies by machine: the encoding
  // embeds absolute file paths and timestamps)

  // Persist under build/ (gitignored), then read back from disk — the
  // "cache the analysis" workflow.
  final outFile = File(p.join('build', 'shop.analysis.yaml'));
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(yaml);
  final restored = YamlDeserializer.decode(outFile.readAsStringSync());

  // Counts match across the round-trip.
  print('classes    ${original.allClasses.length} -> ${restored.allClasses.length}');
  // classes    6 -> 6
  print('mixins     ${original.allMixins.length} -> ${restored.allMixins.length}');
  // mixins     1 -> 1
  print('extensions ${original.allExtensions.length} -> ${restored.allExtensions.length}');
  // extensions 1 -> 1

  // Structure survives: the restored model renders identical type strings,
  // because renderType reads inline TypeReference data (name + typeArguments +
  // nullability), all of which is serialized.
  final order = restored.findClassesByName('Order').single;
  print('\nrestored Order extends    -> ${renderType(order.superclass!)}');
  // restored Order extends    -> Entity
  print('restored Order implements -> '
      '${order.interfaces.map(renderType).toList()}');
  // restored Order implements -> [Comparable<Order>]
  final grouped = order.methods.firstWhere((m) => m.name == 'groupedByDay');
  print('restored groupedByDay()   -> ${renderType(grouped.returnType)}');
  // restored groupedByDay()   -> Map<String, List<OrderLine>>

  final node = restored.findClassesByName('Node').single;
  print('restored Node param       -> '
      '${node.typeParameters.map(renderTypeParameter).toList()}');
  // restored Node param       -> [T extends Entity]

  // What does NOT survive: the in-memory `resolvedElement` cross-link. After a
  // round-trip the type still renders as Node<T>? (inline data), but the
  // resolved-object pointer is not rebuilt — consumers should key on
  // names/qualified names across a serialization boundary, not object identity.
  final next = node.fields.firstWhere((f) => f.name == 'next');
  print('restored Node.next type     -> ${renderType(next.type)}');
  // restored Node.next type     -> Node<T>?
  print('restored Node.next resolved -> ${next.type.isResolved}');
  // restored Node.next resolved -> false

  print('\nround-trip -> identical structure');
  // round-trip -> identical structure
}
