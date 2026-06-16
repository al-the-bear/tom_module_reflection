// Scenario 1 — load the generated reflection and query its shape.
//
// `catalog.r.dart` is pure generated data: descriptor objects plus invoker
// closures, assembled into a top-level `reflectionApi`. There is NO analyzer at
// runtime — this is the build-time engine's payoff, a ready-to-use index.
import 'package:reflector_reflection_introduction_sample/catalog.r.dart';

void main() {
  // Top-level inventory of everything the generator covered.
  print('classes -> ${reflectionApi.allClasses.map((c) => c.name).toList()}');
  // classes -> [Entity, Product, Warehouse]
  print('enums   -> ${reflectionApi.allEnums.map((e) => e.name).toList()}');
  // enums   -> [Availability]
  print('globals -> ${reflectionApi.allGlobals.map((g) => g.name).toList()}');
  // globals -> [catalogVersion]

  // Drill into one class. Every member group is a name-keyed map.
  final product = reflectionApi.findClass('Product')!;
  print('Product.qualifiedName -> ${product.qualifiedName}');
  print('Product annotations   -> '
      '${product.annotations.map((a) => '@${a.name}').toList()}');
  // Product annotations   -> [@Entity]
  print('Product constructors  -> ${product.constructors.keys.toList()}');
  // Product constructors  -> [new, sample]
  print('Product methods       -> ${product.methods.keys.toList()}');
  // Product methods       -> [discountedPrice, toString]
  print('Product fields        -> ${product.fields.keys.toList()}');
  // Product fields        -> [sku, name, price, stock, label]

  // Read-only vs mutable. A *final* field and a *getter* both reflect as fields
  // with no setter closure; only `isFinal` tells them apart.
  for (final name in ['sku', 'name', 'label']) {
    final f = product.fields[name]!;
    print('  field $name: final=${f.isFinal} '
        'writable=${f.setInstance != null} type=${f.typeQualifiedName}');
  }
  // field sku: final=true writable=false type=dart:core.String
  // field name: final=false writable=true type=dart:core.String
  // field label: final=false writable=false type=dart:core.String

  // Constructor parameters are captured — names, types, defaults.
  final ctor = product.constructors['new']!;
  print('Product() params -> '
      '${ctor.parameters.map((p) => '${p.name}:${p.typeQualifiedName}').toList()}');
  // Product() params -> [sku:dart:core.String, name:dart:core.String, price:dart:core.double, stock:dart:core.int]

  // The codegen use case: find every class marked @Entity, by annotation name.
  final entities = reflectionApi.allClasses
      .where((c) => c.annotations.any((a) => a.name == 'Entity'))
      .map((c) => c.name)
      .toList();
  print('@Entity classes -> $entities');
  // @Entity classes -> [Product, Warehouse]

  // Enums reflect as named types; the generator records presence, not values.
  final availability = reflectionApi.allEnums.single;
  print('enum ${availability.name}: kind=${availability.kind.name} '
      'fields=${availability.fields.length}');
  // enum Availability: kind=enumType fields=0
}
