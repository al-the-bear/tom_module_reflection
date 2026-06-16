// Domain model for the engine-2 reflection-generation sample.
//
// Unlike the parser sample's `sample_source/` (which is analyzed as *text* and
// never executed), THIS library is compiled into the sample. Its instances are
// created and driven entirely through the generated reflection in
// `catalog.r.dart` — no hand-written `Product(...)` calls in the scenarios.
library;

/// Marks a class as a persistable entity.
///
/// The reflection generator records this annotation **by name** on each target
/// class; engine 2 does not capture the constructor argument (`'products'`),
/// only that `@Entity` is present.
class Entity {
  final String table;
  const Entity(this.table);
}

/// A mutable domain object with a final field, mutable fields, two
/// constructors, a method, and a getter — each surfaces in the generated
/// reflection and is exercised at runtime.
@Entity('products')
class Product {
  /// Final field → reflected as read-only (no setter closure).
  final String sku;

  /// Mutable fields → reflected with both getter and setter closures.
  String name;
  double price;
  int stock;

  Product({
    required this.sku,
    this.name = '',
    this.price = 0,
    this.stock = 0,
  });

  /// A named constructor — reflected under the key `sample`.
  Product.sample()
      : sku = 'SKU-0001',
        name = 'Sample Widget',
        price = 9.99,
        stock = 5;

  /// An instance method — invoked dynamically in scenario 2.
  double discountedPrice(double pct) => price * (1 - pct);

  /// A getter — surfaced through the reflection's getter table.
  String get label => '$name ($sku)';

  @override
  String toString() => 'Product($sku)';
}

/// A second entity, to show the generic serializer in scenario 3 works across
/// types without any per-class code.
@Entity('warehouses')
class Warehouse {
  final String code;
  int capacity;

  Warehouse(this.code, {this.capacity = 100});

  bool get isFull => capacity <= 0;
  void receive(int units) => capacity -= units;
}

/// A standalone enum. The reflection generator records the enum's presence as a
/// named type; it does not enumerate the constant values (see the README).
enum Availability { inStock, backordered, discontinued }

/// A top-level function — reflected as a global and invoked in scenario 2.
int catalogVersion() => 7;
