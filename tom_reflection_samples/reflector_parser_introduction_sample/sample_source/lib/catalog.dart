/// A tiny pure-Dart domain (no package imports) used as the *input* to the
/// engine-2 analyzer. Nothing here is run — it is read as source text.
library;

/// Marks a class as a persistable entity.
class Entity {
  final String table;
  const Entity(this.table);
}

/// A product in the catalog.
@Entity('products')
class Product {
  final String sku;
  String name;
  double price;
  final List<String> tags;

  Product({required this.sku, this.name = '', this.price = 0.0, this.tags = const []});

  double discounted(double pct) => price * (1 - pct);
  String get label => '$name ($sku)';
}

/// Availability states for a product.
enum Availability { inStock, backordered, discontinued }

/// A generic repository contract.
abstract class Repository<T> {
  T? findById(String id);
  List<T> findAll();
}

int catalogVersion() => 3;
