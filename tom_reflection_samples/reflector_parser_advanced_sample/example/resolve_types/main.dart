// Scenario 1 — resolve the hard parts: generics, bounds, mixins, extensions.
//
// The introduction sample showed flat classes and fields. Here we walk the
// pieces that make a real type model useful: nested type arguments, generic
// bounds, the extends/with/implements triad, an `on`-clause mixin, an extension
// target, and a self-referential field whose cycle the analyzer resolves in
// memory without looping.
import 'package:reflector_parser_advanced_sample/shop_analysis.dart';

Future<void> main() async {
  final result = await analyzeShop();
  print('classes    -> ${result.allClasses.map((c) => c.name).toList()}');
  // classes    -> [Table, Id, Entity, Order, OrderLine, Node]
  print('mixins     -> ${result.allMixins.map((m) => m.name).toList()}');
  // mixins     -> [Timestamped]
  print('extensions -> ${result.allExtensions.map((e) => e.name).toList()}');
  // extensions -> [OrderQuery]

  // The extends/with/implements triad — each is a separate TypeReference.
  final order = result.findClassesByName('Order').single;
  print('\nOrder extends    -> ${renderType(order.superclass!)}');
  // Order extends    -> Entity
  print('Order with       -> ${order.mixins.map(renderType).toList()}');
  // Order with       -> [Timestamped]
  print('Order implements -> ${order.interfaces.map(renderType).toList()}');
  // Order implements -> [Comparable<Order>]

  // Nested type arguments survive two deep.
  final grouped = order.methods.firstWhere((m) => m.name == 'groupedByDay');
  print('groupedByDay() -> ${renderType(grouped.returnType)}');
  // groupedByDay() -> Map<String, List<OrderLine>>

  // Generic bounds and type parameters.
  final node = result.findClassesByName('Node').single;
  print('\nNode type params -> '
      '${node.typeParameters.map(renderTypeParameter).toList()}');
  // Node type params -> [T extends Entity]

  final valueField = node.fields.firstWhere((f) => f.name == 'value');
  print('Node.value type  -> ${renderType(valueField.type)} '
      '(isTypeParameter=${valueField.type.isTypeParameter})');
  // Node.value type  -> T (isTypeParameter=true)

  // The self-referential field: Node.next is Node<T>? — and the analyzer
  // resolves the cycle IN MEMORY (resolvedElement points back at Node) without
  // looping. (This cross-link is an in-memory convenience; it does not survive
  // a serialization round-trip — see scenario 2.)
  final nextField = node.fields.firstWhere((f) => f.name == 'next');
  print('Node.next type   -> ${renderType(nextField.type)}');
  // Node.next type   -> Node<T>?
  print('Node.next resolved -> ${nextField.type.isResolved} '
      '(-> ${nextField.type.resolvedElement?.name})');
  // Node.next resolved -> true (-> Node)

  // Mixin `on` clause and extension target.
  final mixin = result.allMixins.single;
  print('\nTimestamped on -> ${mixin.onTypes.map(renderType).toList()} '
      'methods=${mixin.methods.map((m) => m.name).toList()}');
  // Timestamped on -> [Entity] methods=[ageInDays]

  final ext = result.allExtensions.single;
  print('OrderQuery on  -> ${renderType(ext.extendedType)} '
      'methods=${ext.methods.map((m) => m.name).toList()}');
  // OrderQuery on  -> List<Order> methods=[openOnly]
}
